Mix.Task.run("app.start")

defmodule Obscura.FastProfileBenchmark do
  @moduledoc false

  alias Obscura.Eval.Operational.Statistics

  @common_text """
  Rachel works at Google in Paris. Contact her at info@example.test or
  +1 202-555-0188. Visit example.test. Card 4111 1111 1111 1111.
  """

  @entities [:email, :phone, :credit_card, :us_ssn, :ip_address, :url, :domain]

  def run(args) do
    opts = parse_args(args)
    cases = cases(opts)

    report = %{
      schema_version: 1,
      kind: "fast_profile_microbenchmark",
      label: opts.label,
      source: source_metadata(),
      environment: environment(),
      configuration: %{
        repetitions: opts.repetitions,
        scale: opts.scale,
        telemetry: false,
        profile: "fast"
      },
      cases: Enum.map(cases, &run_case(&1, opts))
    }

    File.mkdir_p!(Path.dirname(opts.output))
    File.write!(opts.output, Jason.encode_to_iodata!(report, pretty: true))
    File.write!(Path.rootname(opts.output) <> ".md", markdown(report))

    IO.puts("Wrote #{opts.output}")
  end

  defp parse_args(args) do
    args = Enum.drop_while(args, &(&1 == "--"))

    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          label: :string,
          output: :string,
          repetitions: :integer,
          scale: :float
        ]
      )

    if remaining != [] or invalid != [], do: raise(ArgumentError, "invalid benchmark options")

    repetitions = Keyword.get(parsed, :repetitions, 3)
    scale = Keyword.get(parsed, :scale, 1.0)

    if repetitions < 1, do: raise(ArgumentError, "repetitions must be positive")
    if scale <= 0.0, do: raise(ArgumentError, "scale must be positive")

    %{
      label: Keyword.get(parsed, :label, "working"),
      output:
        Keyword.get(
          parsed,
          :output,
          "eval/reports/fast_profile/fast_profile_microbenchmark.json"
        ),
      repetitions: repetitions,
      scale: scale
    }
  end

  defp cases(opts) do
    one_kib = padded_text(1_024, "probe@example.test")
    sixty_four_kib = padded_text(65_536, "probe@example.test")
    one_mib = padded_text(1_048_576, "probe@example.test")
    long_url = "https://example.test/" <> String.duplicate("segment/", 64)
    retained_url = padded_text(400_000, long_url)

    [
      benchmark_case(
        "analyze_common_without_text",
        byte_size(@common_text),
        iterations(8_000, opts),
        fn ->
          Obscura.analyze(@common_text,
            profile: :fast,
            entities: @entities,
            include_text: false,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_common_with_text",
        byte_size(@common_text),
        iterations(8_000, opts),
        fn ->
          Obscura.analyze(@common_text,
            profile: :fast,
            entities: @entities,
            include_text: true,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_no_match_1k",
        byte_size(one_kib),
        iterations(5_000, opts),
        fn ->
          Obscura.analyze(one_kib,
            profile: :fast,
            entities: @entities,
            include_text: false,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_one_match_64k_without_text",
        byte_size(sixty_four_kib),
        iterations(500, opts),
        fn ->
          Obscura.analyze(sixty_four_kib,
            profile: :fast,
            entities: [:email],
            include_text: false,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_one_match_64k_with_text",
        byte_size(sixty_four_kib),
        iterations(500, opts),
        fn ->
          Obscura.analyze(sixty_four_kib,
            profile: :fast,
            entities: [:email],
            include_text: true,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_one_match_1m_without_text",
        byte_size(one_mib),
        iterations(30, opts),
        fn ->
          Obscura.analyze(one_mib,
            profile: :fast,
            entities: [:email],
            include_text: false,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_long_url_with_text",
        byte_size(retained_url),
        iterations(100, opts),
        fn ->
          Obscura.analyze(retained_url,
            profile: :fast,
            entities: [:url],
            include_text: true,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_many_batch_8",
        byte_size(@common_text) * 8,
        iterations(800, opts),
        fn ->
          Obscura.Analyzer.analyze_many(List.duplicate(@common_text, 8),
            profile: :fast,
            entities: @entities,
            include_text: false,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "analyze_many_batch_32",
        byte_size(@common_text) * 32,
        iterations(200, opts),
        fn ->
          Obscura.Analyzer.analyze_many(List.duplicate(@common_text, 32),
            profile: :fast,
            entities: @entities,
            include_text: false,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "detect_and_redact_common",
        byte_size(@common_text),
        iterations(4_000, opts),
        fn ->
          with {:ok, results} <-
                 Obscura.analyze(@common_text,
                   profile: :fast,
                   entities: @entities,
                   include_text: false,
                   telemetry: false
                 ) do
            Obscura.anonymize(@common_text, results, telemetry: false)
          end
        end
      ),
      benchmark_case(
        "structured_redact",
        byte_size(@common_text) * 4,
        iterations(1_000, opts),
        fn ->
          Obscura.Structured.redact(
            %{
              user: %{contact: @common_text, notes: [@common_text, %{value: @common_text}]},
              audit: @common_text
            },
            profile: :fast,
            entities: @entities,
            telemetry: false
          )
        end
      )
    ]
  end

  defp benchmark_case(name, input_bytes, iterations, fun) do
    %{name: name, input_bytes: input_bytes, iterations: iterations, fun: fun}
  end

  defp iterations(base, opts), do: max(1, round(base * opts.scale))

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

  defp run_case(case_data, opts) do
    warmup_iterations = max(3, min(100, div(case_data.iterations, 10)))

    repetitions =
      for repetition <- 1..opts.repetitions do
        run_repetition(case_data, warmup_iterations, repetition)
      end

    %{
      name: case_data.name,
      input_bytes: case_data.input_bytes,
      iterations: case_data.iterations,
      warmup_iterations: warmup_iterations,
      repetitions: repetitions,
      median: median_repetition(repetitions)
    }
  end

  defp run_repetition(case_data, warmup_iterations, repetition) do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        result =
          execute_repetition(case_data.fun, case_data.iterations, warmup_iterations, repetition)

        send(parent, {:benchmark_repetition, self(), result})
      end)

    receive do
      {:benchmark_repetition, ^pid, result} ->
        receive do
          {:DOWN, ^monitor, :process, ^pid, :normal} -> result
        after
          5_000 -> raise "benchmark worker did not terminate"
        end

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        raise "benchmark worker failed: #{inspect(reason)}"
    after
      900_000 -> raise "benchmark worker timed out"
    end
  end

  defp execute_repetition(fun, iterations, warmup_iterations, repetition) do
    first = checked_run(fun)

    for _index <- 1..warmup_iterations do
      checked_run(fun)
    end

    :erlang.garbage_collect(self())
    before = process_snapshot()
    wall_start = System.monotonic_time(:nanosecond)

    durations =
      for _index <- 1..iterations do
        started = System.monotonic_time(:nanosecond)
        checked_run(fun)
        System.monotonic_time(:nanosecond) - started
      end

    wall_ns = System.monotonic_time(:nanosecond) - wall_start
    after_snapshot = process_snapshot()

    summary =
      durations
      |> Enum.map(&(&1 / 1_000.0))
      |> Statistics.summarize()

    %{
      repetition: repetition,
      latency_us: summary,
      throughput_per_second: iterations * 1_000_000_000.0 / wall_ns,
      wall_ms: wall_ns / 1_000_000.0,
      reductions_per_operation: (after_snapshot.reductions - before.reductions) / iterations,
      minor_gcs: after_snapshot.minor_gcs - before.minor_gcs,
      memory_before_bytes: before.memory,
      memory_after_bytes: after_snapshot.memory,
      total_heap_before_words: before.total_heap_size,
      total_heap_after_words: after_snapshot.total_heap_size,
      output_fingerprint: fingerprint(first)
    }
  end

  defp checked_run(fun) do
    case fun.() do
      {:ok, result} -> result
      {:error, reason} -> raise "benchmark operation failed: #{inspect(reason)}"
      other -> other
    end
  end

  defp process_snapshot do
    info =
      Process.info(self(), [
        :memory,
        :reductions,
        :total_heap_size,
        :garbage_collection
      ])

    garbage_collection = Keyword.fetch!(info, :garbage_collection)

    %{
      memory: Keyword.fetch!(info, :memory),
      reductions: Keyword.fetch!(info, :reductions),
      total_heap_size: Keyword.fetch!(info, :total_heap_size),
      minor_gcs: Keyword.get(garbage_collection, :minor_gcs, 0)
    }
  end

  defp fingerprint(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp median_repetition(repetitions) do
    %{
      latency_us: %{
        mean: median(repetitions, &get_in(&1, [:latency_us, :mean])),
        p50: median(repetitions, &get_in(&1, [:latency_us, :p50])),
        p95: median(repetitions, &get_in(&1, [:latency_us, :p95])),
        p99: median(repetitions, &get_in(&1, [:latency_us, :p99])),
        max: median(repetitions, &get_in(&1, [:latency_us, :max]))
      },
      throughput_per_second: median(repetitions, & &1.throughput_per_second),
      reductions_per_operation: median(repetitions, & &1.reductions_per_operation),
      minor_gcs: median(repetitions, & &1.minor_gcs)
    }
  end

  defp median(values, mapper) do
    sorted = values |> Enum.map(mapper) |> Enum.sort()
    Enum.at(sorted, div(length(sorted), 2))
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
      os: inspect(:os.type()),
      architecture: to_string(:erlang.system_info(:system_architecture)),
      schedulers: :erlang.system_info(:schedulers_online),
      logical_processors: :erlang.system_info(:logical_processors_available)
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
      Enum.map(report.cases, fn benchmark ->
        median = benchmark.median

        "| `#{benchmark.name}` | #{benchmark.input_bytes} | #{format(median.latency_us.p50)} | " <>
          "#{format(median.latency_us.p95)} | #{format(median.latency_us.p99)} | " <>
          "#{format(median.throughput_per_second)} | " <>
          "#{format(median.reductions_per_operation)} |"
      end)

    [
      "# Fast Profile Microbenchmark",
      "",
      "- Label: `#{report.label}`",
      "- Source: `#{report.source.commit}`",
      "- Dirty: `#{report.source.dirty}`",
      "- Elixir / OTP: `#{report.environment.elixir}` / `#{report.environment.otp}`",
      "- Repetitions: `#{report.configuration.repetitions}`",
      "",
      "| Case | Input bytes | p50 us | p95 us | p99 us | ops/s | reductions/op |",
      "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
      rows,
      ""
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format(nil), do: "n/a"
  defp format(value) when is_integer(value), do: Integer.to_string(value)
  defp format(value), do: :erlang.float_to_binary(value / 1, decimals: 3)
end

Obscura.FastProfileBenchmark.run(System.argv())
