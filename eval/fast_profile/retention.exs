Mix.Task.run("app.start")

defmodule Obscura.FastProfileRetentionProbe do
  @moduledoc false

  alias Obscura.Analyzer.Result

  defmodule BorrowingRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :borrowing_retention_probe

    @impl true
    def supported_entities, do: [:url]

    @impl true
    def analyze(text, _opts) do
      {start, length} = :binary.match(text, "https://")
      value = binary_part(text, start, byte_size(text) - start)

      [
        %Result{
          entity: :url,
          start: start,
          end: start + length + byte_size(value) - length,
          byte_start: start,
          byte_end: start + byte_size(value),
          score: 0.9,
          text: value,
          source_entity: "URL",
          recognizer: :borrowing_retention_probe,
          metadata: %{}
        }
      ]
    end
  end

  def run(args) do
    opts = parse_args(args)

    report = %{
      schema_version: 1,
      kind: "fast_profile_binary_retention",
      label: opts.label,
      source: source_metadata(),
      environment: environment(),
      cases: Enum.map(cases(), &run_case/1)
    }

    File.mkdir_p!(Path.dirname(opts.output))
    File.write!(opts.output, Jason.encode_to_iodata!(report, pretty: true))
    File.write!(Path.rootname(opts.output) <> ".md", markdown(report))

    IO.puts("Wrote #{opts.output}")
  end

  defp parse_args(args) do
    args = Enum.drop_while(args, &(&1 == "--"))

    {parsed, remaining, invalid} =
      OptionParser.parse(args, strict: [label: :string, output: :string])

    if remaining != [] or invalid != [], do: raise(ArgumentError, "invalid retention options")

    %{
      label: Keyword.get(parsed, :label, "working"),
      output:
        Keyword.get(
          parsed,
          :output,
          "eval/reports/fast_profile/fast_profile_retention.json"
        )
    }
  end

  defp cases do
    [
      %{
        name: "short_email_with_text",
        expectation: :owned_text,
        operation: fn ->
          text = padded_text(131_072, "probe@example.test")

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:email],
              include_text: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "long_url_with_text",
        expectation: :owned_text,
        operation: fn ->
          text = long_url_text()

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:url],
              include_text: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "long_url_without_text",
        expectation: :no_text,
        operation: fn ->
          text = long_url_text()

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:url],
              include_text: false,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "long_url_analyze_many_with_text",
        expectation: :owned_text,
        operation: fn ->
          text = long_url_text()

          {:ok, [[result]]} =
            Obscura.Analyzer.analyze_many([text],
              profile: :fast,
              entities: [:url],
              include_text: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "custom_borrowed_with_text",
        expectation: :owned_text,
        operation: fn ->
          text = custom_text()

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:url],
              recognizers: [BorrowingRecognizer],
              include_text: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "custom_borrowed_without_text",
        expectation: :no_text,
        operation: fn ->
          text = custom_text()

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:url],
              recognizers: [BorrowingRecognizer],
              include_text: false,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "deny_list_with_text",
        expectation: :owned_text,
        operation: fn ->
          value = String.duplicate("sensitive-", 64) <> "marker"
          text = padded_text(400_000, value)

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:url],
              deny_lists: [%{entity: :url, values: [value]}],
              include_text: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "allow_list_rejected_without_text",
        expectation: :no_results,
        operation: fn ->
          text = long_url_text()
          [value] = Regex.run(~r/https?:\/\/\S+/, text)

          {:ok, []} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:url],
              allow_list: [%{entity: :url, values: [value]}],
              include_text: false,
              telemetry: false
            )

          []
        end
      }
    ]
  end

  defp run_case(case_data) do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        result = case_data.operation.()
        send(parent, {:retention_result, self(), result})
      end)

    result =
      receive do
        {:retention_result, ^pid, result} ->
          receive do
            {:DOWN, ^monitor, :process, ^pid, :normal} -> result
          after
            5_000 -> raise "retention worker did not terminate"
          end

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          raise "retention worker failed: #{inspect(reason)}"
      after
        120_000 -> raise "retention worker timed out"
      end

    :erlang.garbage_collect(self())
    observation = observe(result)

    Map.merge(
      %{
        name: case_data.name,
        expectation: Atom.to_string(case_data.expectation),
        passed: passes?(case_data.expectation, observation)
      },
      observation
    )
  end

  defp observe(%Result{text: nil}) do
    %{result_count: 1, text_bytes: 0, referenced_bytes: 0, amplification: 0.0}
  end

  defp observe(%Result{text: text}) when is_binary(text) do
    text_bytes = byte_size(text)
    referenced_bytes = :binary.referenced_byte_size(text)

    %{
      result_count: 1,
      text_bytes: text_bytes,
      referenced_bytes: referenced_bytes,
      amplification: referenced_bytes / max(text_bytes, 1)
    }
  end

  defp observe([]) do
    %{result_count: 0, text_bytes: 0, referenced_bytes: 0, amplification: 0.0}
  end

  defp passes?(:owned_text, observation) do
    observation.text_bytes > 0 and observation.referenced_bytes == observation.text_bytes
  end

  defp passes?(:no_text, observation) do
    observation.result_count == 1 and observation.text_bytes == 0 and
      observation.referenced_bytes == 0
  end

  defp passes?(:no_results, observation), do: observation.result_count == 0

  defp long_url_text do
    url = "https://example.test/" <> String.duplicate("segment/", 64)
    padded_text(400_000, url)
  end

  defp custom_text do
    prefix = safe_padding(200_000)
    prefix <> "https://" <> String.duplicate("custom-path/", 64)
  end

  defp padded_text(target_bytes, match) do
    remaining = max(target_bytes - byte_size(match), 0)
    prefix_bytes = div(remaining, 2)
    suffix_bytes = remaining - prefix_bytes

    safe_padding(prefix_bytes) <> match <> safe_padding(suffix_bytes)
  end

  defp safe_padding(bytes) do
    pattern = "safe text "
    repeats = div(bytes, byte_size(pattern))
    rest = rem(bytes, byte_size(pattern))
    String.duplicate(pattern, repeats) <> binary_part(pattern, 0, rest)
  end

  defp source_metadata do
    %{
      commit: command("git", ["rev-parse", "HEAD"]),
      dirty: command("git", ["status", "--porcelain"]) != ""
    }
  end

  defp environment do
    %{
      elixir: System.version(),
      otp: System.otp_release(),
      architecture: to_string(:erlang.system_info(:system_architecture))
    }
  end

  defp command(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {_output, _status} -> "unavailable"
    end
  rescue
    _error -> "unavailable"
  end

  defp markdown(report) do
    rows =
      Enum.map(report.cases, fn result ->
        "| `#{result.name}` | `#{result.expectation}` | #{result.text_bytes} | " <>
          "#{result.referenced_bytes} | #{format(result.amplification)}x | " <>
          "#{result.passed} |"
      end)

    [
      "# Fast Profile Binary Retention Probe",
      "",
      "- Label: `#{report.label}`",
      "- Source: `#{report.source.commit}`",
      "- Dirty: `#{report.source.dirty}`",
      "- Elixir / OTP: `#{report.environment.elixir}` / `#{report.environment.otp}`",
      "",
      "| Case | Expectation | Text bytes | Referenced bytes | Amplification | Passed |",
      "| --- | --- | ---: | ---: | ---: | --- |",
      rows,
      ""
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format(value), do: :erlang.float_to_binary(value / 1, decimals: 3)
end

Obscura.FastProfileRetentionProbe.run(System.argv())
