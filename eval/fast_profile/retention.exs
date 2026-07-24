Mix.Task.run("app.start")

defmodule Obscura.FastProfileRetentionProbe do
  @moduledoc false

  alias Obscura.Analyzer.Result
  alias Obscura.Recognizer.PatternDefinition

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

  defmodule OffsetOnlyRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :offset_only_retention_probe

    @impl true
    def supported_entities, do: [:person]

    @impl true
    def analyze(_text, _opts) do
      [
        %Result{
          entity: :person,
          start: 0,
          end: 5,
          byte_start: 0,
          byte_end: 5,
          score: 0.9,
          text: nil,
          source_entity: "PERSON",
          recognizer: :offset_only_retention_probe,
          metadata: %{}
        }
      ]
    end
  end

  defmodule FailureRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :failure_retention_probe

    @impl true
    def supported_entities, do: [:email]

    @impl true
    def analyze(text, opts) do
      case Keyword.fetch!(opts, :failure_mode) do
        :error -> {:error, text}
        :exception -> raise text
        :throw -> throw(text)
        :exit -> exit(text)
        :timeout -> Process.sleep(:infinity)
      end
    end
  end

  defmodule MalformedOwnershipRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :malformed_ownership_retention_probe

    @impl true
    def supported_entities, do: [:person]

    @impl true
    def analyze(text, opts) do
      borrowed = binary_part(text, 100_000, 1_024)

      result = %Result{
        entity: :person,
        start: 100_000,
        end: 101_024,
        byte_start: 100_000,
        byte_end: 101_024,
        score: 0.9,
        text: nil,
        source_entity: "PERSON",
        recognizer: :malformed_ownership_retention_probe,
        metadata: %{}
      }

      case Keyword.fetch!(opts, :malformed_field) do
        :recognizer -> %{result | recognizer: borrowed}
        :opaque_metadata -> %{result | metadata: %{deferred: fn -> borrowed end}}
      end
      |> List.wrap()
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
        name: "built_in_without_text_omits_source_value",
        expectation: :no_sensitive_text,
        operation: fn ->
          value = "OBSCURA-RETENTION-CANARY-42@example.test"
          text = padded_text(400_000, value)

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:email],
              include_text: false,
              telemetry: false
            )

          retention_probe(result, [value])
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
        name: "deny_list_without_text",
        expectation: :no_sensitive_text,
        operation: fn ->
          value = String.duplicate("OBSCURA-DENY-CANARY-", 64) <> "marker"
          text = padded_text(400_000, value)

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:url],
              deny_lists: [%{entity: :url, values: [value]}],
              include_text: false,
              telemetry: false
            )

          retention_probe(result, [value])
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
      },
      %{
        name: "custom_offset_only_with_text_enabled",
        expectation: :no_text,
        operation: fn ->
          source = "Alice" <> safe_padding(400_000)

          {:ok, [result]} =
            Obscura.analyze(source,
              profile: :fast,
              built_ins: false,
              entities: [:person],
              recognizers: [OffsetOnlyRecognizer],
              include_text: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "explanation_and_metadata_without_text",
        expectation: :no_text,
        operation: fn ->
          text = padded_text(400_000, "credit card 4111 1111 1111 1111")

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:credit_card],
              include_text: false,
              explain: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "anonymizer_result_and_items",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          {:ok, results} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:email],
              include_text: false,
              telemetry: false
            )

          {:ok, result} = Obscura.anonymize(text, results, telemetry: false)
          result
        end
      },
      %{
        name: "structured_result_and_items",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          {:ok, result} =
            Obscura.Structured.redact(
              %{nested: [%{payload: text}]},
              profile: :fast,
              entities: [:email],
              telemetry: false
            )

          result
        end
      },
      %{
        name: "logger_redacted_term",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          {:ok, result} =
            Obscura.Logger.redact_term(%{payload: text},
              profile: :fast,
              entities: [:email],
              telemetry: false
            )

          result
        end
      },
      %{
        name: "plug_replaced_params",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          conn =
            :post
            |> Plug.Test.conn("/", %{})
            |> Map.put(:params, %{"payload" => text})
            |> Obscura.Phoenix.Plug.call(
              fields: [:params],
              mode: :replace,
              profile: :fast,
              entities: [:email],
              telemetry: false
            )

          conn
        end
      },
      %{
        name: "pattern_definition_with_text",
        expectation: :owned_text,
        operation: fn ->
          text = padded_text(400_000, "probe-value")

          definition =
            PatternDefinition.new!(
              name: :retention_pattern,
              entity: :url,
              patterns: [%{name: :probe, regex: ~r/probe-value/u, score: 0.9}]
            )

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:url],
              recognizers: [definition],
              include_text: true,
              telemetry: false
            )

          result
        end
      },
      %{
        name: "pattern_definition_validation_metadata",
        expectation: :owned_sensitive_metadata,
        operation: fn ->
          value = String.duplicate("Z", 1_024)
          text = padded_text(400_000, value)

          definition =
            PatternDefinition.new!(
              name: :metadata_retention_pattern,
              entity: :url,
              patterns: [%{name: :probe, regex: ~r/Z{1024}/u, score: 0.9}],
              validate: fn match -> {:ok, %{nested: [%{captured: match}]}} end
            )

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:url],
              recognizers: [definition],
              include_text: false,
              explain: true,
              telemetry: false
            )

          retention_probe(result, [value])
        end
      },
      %{
        name: "many_accepted_matches_with_text",
        expectation: :clean_graph,
        operation: fn ->
          text = Enum.join(List.duplicate("probe@example.test", 100), " ")

          {:ok, results} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:email],
              include_text: true,
              telemetry: false
            )

          results
        end
      },
      %{
        name: "score_rejected_without_text",
        expectation: :no_results,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          {:ok, []} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:email],
              score_threshold: 0.99,
              include_text: false,
              telemetry: false
            )

          []
        end
      },
      %{
        name: "context_rejected_without_text",
        expectation: :no_results,
        operation: fn ->
          text = padded_text(400_000, "probe-value")

          definition =
            PatternDefinition.new!(
              name: :context_retention_pattern,
              entity: :url,
              context: ["account"],
              patterns: [
                %{
                  name: :probe,
                  regex: ~r/probe-value/u,
                  score: 0.4,
                  requires_context: true
                }
              ]
            )

          {:ok, []} =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:url],
              recognizers: [definition],
              include_text: false,
              telemetry: false
            )

          []
        end
      },
      %{
        name: "overlap_conflict_result_graph",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "https://subdomain.example.test/path")

          {:ok, results} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:url, :domain],
              include_text: true,
              telemetry: false
            )

          results
        end
      },
      %{
        name: "telemetry_enabled_result_graph",
        expectation: :no_text,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          {:ok, [result]} =
            Obscura.analyze(text,
              profile: :fast,
              entities: [:email],
              include_text: false,
              telemetry: true
            )

          result
        end
      },
      %{
        name: "recognizer_error_is_sanitized",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          Obscura.analyze(text,
            profile: :fast,
            built_ins: false,
            entities: [:email],
            recognizers: [{FailureRecognizer, failure_mode: :error}],
            telemetry: false
          )
        end
      },
      %{
        name: "recognizer_exception_is_sanitized",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          Obscura.analyze(text,
            profile: :fast,
            built_ins: false,
            entities: [:email],
            recognizers: [{FailureRecognizer, failure_mode: :exception}],
            telemetry: false
          )
        end
      },
      %{
        name: "parallel_recognizer_throw_is_sanitized",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          Obscura.analyze(text,
            profile: :fast,
            built_ins: false,
            entities: [:email],
            recognizers: [{FailureRecognizer, failure_mode: :throw}],
            parallel_recognizers: true,
            telemetry: false
          )
        end
      },
      %{
        name: "parallel_recognizer_exit_is_sanitized",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          Obscura.analyze(text,
            profile: :fast,
            built_ins: false,
            entities: [:email],
            recognizers: [{FailureRecognizer, failure_mode: :exit}],
            parallel_recognizers: true,
            telemetry: false
          )
        end
      },
      %{
        name: "parallel_recognizer_timeout_is_sanitized",
        expectation: :clean_graph,
        operation: fn ->
          text = padded_text(400_000, "probe@example.test")

          Obscura.analyze(text,
            profile: :fast,
            built_ins: false,
            entities: [:email],
            recognizers: [{FailureRecognizer, failure_mode: :timeout}],
            parallel_recognizers: true,
            recognizer_timeout: 10,
            telemetry: false
          )
        end
      },
      %{
        name: "malformed_recognizer_field_is_rejected",
        expectation: :no_sensitive_graph,
        operation: fn ->
          sensitive = String.duplicate("R", 1_024)
          text = safe_padding(100_000) <> sensitive <> safe_padding(100_000)

          result =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:person],
              recognizers: [
                {MalformedOwnershipRecognizer, malformed_field: :recognizer}
              ],
              include_text: false,
              telemetry: false
            )

          retention_probe(result, [sensitive])
        end
      },
      %{
        name: "opaque_metadata_closure_is_rejected",
        expectation: :no_sensitive_graph,
        operation: fn ->
          sensitive = String.duplicate("O", 1_024)
          text = safe_padding(100_000) <> sensitive <> safe_padding(100_000)

          result =
            Obscura.analyze(text,
              profile: :fast,
              built_ins: false,
              entities: [:person],
              recognizers: [
                {MalformedOwnershipRecognizer, malformed_field: :opaque_metadata}
              ],
              include_text: false,
              telemetry: false
            )

          retention_probe(result, [sensitive])
        end
      }
    ] ++ parser_metadata_cases()
  end

  defp parser_metadata_cases do
    if Code.ensure_loaded?(ExPhoneNumber) do
      [
        %{
          name: "phone_parser_normalized_sensitive_metadata",
          expectation: :owned_sensitive_metadata,
          operation: fn ->
            {:ok, [result]} =
              Obscura.analyze("Call +44 20 7946 0958",
                profile: :fast,
                entities: [:phone],
                include_text: false,
                phone_parser: Obscura.Recognizer.Phone.ExPhoneNumberValidator,
                phone_regions: ["GB"],
                telemetry: false
              )

            retention_probe(result, ["+442079460958"])
          end
        }
      ]
    else
      []
    end
  end

  defp retention_probe(term, sensitive_values) do
    {:retention_probe, term, sensitive_values}
  end

  defp run_case(case_data) do
    parent = self()
    binary_memory_before = :erlang.memory(:binary)

    {pid, monitor} =
      spawn_monitor(fn ->
        {result, sensitive_values} = normalize_probe(case_data.operation.())
        :erlang.garbage_collect(self())
        send(parent, {:retention_observation, self(), observe(result, sensitive_values)})

        receive do
          :release_retention_result -> :ok
        end
      end)

    observation =
      receive do
        {:retention_observation, ^pid, observation} ->
          Map.merge(observation, holder_snapshot(pid))

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          raise "retention worker failed: #{inspect(reason)}"
      after
        120_000 -> raise "retention worker timed out"
      end

    binary_memory_while_held = :erlang.memory(:binary)
    send(pid, :release_retention_result)

    receive do
      {:DOWN, ^monitor, :process, ^pid, :normal} ->
        :ok

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        raise "retention holder failed: #{inspect(reason)}"
    after
      5_000 -> raise "retention holder did not terminate"
    end

    :erlang.garbage_collect(self())
    binary_memory_after_release = :erlang.memory(:binary)

    observation =
      Map.merge(observation, %{
        holder_terminated: Process.info(pid) == nil,
        vm_binary_before_bytes: binary_memory_before,
        vm_binary_while_held_bytes: binary_memory_while_held,
        vm_binary_after_release_bytes: binary_memory_after_release
      })

    Map.merge(
      %{
        name: case_data.name,
        expectation: Atom.to_string(case_data.expectation),
        passed: passes?(case_data.expectation, observation)
      },
      observation
    )
  end

  defp normalize_probe({:retention_probe, term, sensitive_values}),
    do: {term, sensitive_values}

  defp normalize_probe(term), do: {term, []}

  defp observe(term, sensitive_values) do
    state = inspect_term(term, [], empty_observation(), sensitive_values)

    %{
      result_count: state.result_count,
      binary_count: state.binary_count,
      binary_bytes: state.binary_bytes,
      referenced_bytes: state.referenced_bytes,
      borrowed_binary_count: state.borrowed_binary_count,
      borrowed_paths: Enum.reverse(state.borrowed_paths),
      sensitive_binary_count: state.sensitive_binary_count,
      sensitive_paths: Enum.reverse(state.sensitive_paths),
      text_bytes: state.text_bytes,
      text_referenced_bytes: state.text_referenced_bytes,
      amplification: state.max_amplification
    }
  end

  defp passes?(:owned_text, observation) do
    clean_graph?(observation) and observation.text_bytes > 0 and
      observation.text_referenced_bytes == observation.text_bytes
  end

  defp passes?(:no_text, observation) do
    clean_graph?(observation) and observation.result_count == 1 and observation.text_bytes == 0 and
      observation.text_referenced_bytes == 0
  end

  defp passes?(:no_sensitive_text, observation) do
    passes?(:no_text, observation) and observation.sensitive_binary_count == 0
  end

  defp passes?(:no_sensitive_graph, observation) do
    clean_graph?(observation) and observation.sensitive_binary_count == 0
  end

  defp passes?(:owned_sensitive_metadata, observation) do
    passes?(:no_text, observation) and observation.sensitive_binary_count > 0
  end

  defp passes?(:no_results, observation),
    do: clean_graph?(observation) and observation.result_count == 0

  defp passes?(:clean_graph, observation), do: clean_graph?(observation)

  defp clean_graph?(observation) do
    observation.borrowed_binary_count == 0 and observation.holder_terminated
  end

  defp empty_observation do
    %{
      result_count: 0,
      binary_count: 0,
      binary_bytes: 0,
      referenced_bytes: 0,
      borrowed_binary_count: 0,
      borrowed_paths: [],
      sensitive_binary_count: 0,
      sensitive_paths: [],
      text_bytes: 0,
      text_referenced_bytes: 0,
      max_amplification: 0.0
    }
  end

  defp inspect_term(%Result{} = result, path, state, sensitive_values) do
    result
    |> Map.from_struct()
    |> inspect_term(path, %{state | result_count: state.result_count + 1}, sensitive_values)
  end

  defp inspect_term(value, path, state, sensitive_values) when is_binary(value) do
    bytes = byte_size(value)
    referenced = :binary.referenced_byte_size(value)
    amplification = referenced / max(bytes, 1)
    text? = List.last(path) == :text
    borrowed? = referenced > bytes
    sensitive? = Enum.any?(sensitive_values, &contains_sensitive_value?(value, &1))

    %{
      state
      | binary_count: state.binary_count + 1,
        binary_bytes: state.binary_bytes + bytes,
        referenced_bytes: state.referenced_bytes + referenced,
        borrowed_binary_count: state.borrowed_binary_count + if(borrowed?, do: 1, else: 0),
        borrowed_paths:
          if(borrowed?, do: [safe_path(path) | state.borrowed_paths], else: state.borrowed_paths),
        sensitive_binary_count: state.sensitive_binary_count + if(sensitive?, do: 1, else: 0),
        sensitive_paths:
          if(sensitive?,
            do: [safe_path(path) | state.sensitive_paths],
            else: state.sensitive_paths
          ),
        text_bytes: state.text_bytes + if(text?, do: bytes, else: 0),
        text_referenced_bytes: state.text_referenced_bytes + if(text?, do: referenced, else: 0),
        max_amplification: max(state.max_amplification, amplification)
    }
  end

  defp inspect_term(value, path, state, sensitive_values) when is_map(value) do
    value
    |> Map.delete(:__struct__)
    |> Enum.reduce(state, fn {key, nested}, acc ->
      acc = inspect_term(key, [:map_key | path], acc, sensitive_values)
      inspect_term(nested, path ++ [safe_path_part(key)], acc, sensitive_values)
    end)
  end

  defp inspect_term(value, path, state, sensitive_values) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce(state, fn {nested, index}, acc ->
      inspect_term(nested, path ++ [index], acc, sensitive_values)
    end)
  end

  defp inspect_term(value, path, state, sensitive_values) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> inspect_term(path, state, sensitive_values)
  end

  defp inspect_term(value, path, state, sensitive_values) when is_function(value) do
    {:env, environment} = :erlang.fun_info(value, :env)
    inspect_term(environment, path ++ [:function_env], state, sensitive_values)
  end

  defp inspect_term(_value, _path, state, _sensitive_values), do: state

  defp contains_sensitive_value?(_value, ""), do: false

  defp contains_sensitive_value?(value, sensitive_value) when is_binary(sensitive_value) do
    :binary.match(value, sensitive_value) != :nomatch
  end

  defp holder_snapshot(pid) do
    info = Process.info(pid, [:memory, :message_queue_len, :binary])
    binaries = Keyword.get(info, :binary, [])

    %{
      holder_memory_bytes: Keyword.get(info, :memory, 0),
      holder_message_queue_len: Keyword.get(info, :message_queue_len, 0),
      holder_binary_count: length(binaries),
      holder_binary_bytes: Enum.sum(Enum.map(binaries, &elem(&1, 1)))
    }
  end

  defp safe_path(path), do: Enum.map_join(path, ".", &to_string/1)
  defp safe_path_part(value) when is_atom(value), do: value
  defp safe_path_part(value) when is_integer(value), do: value
  defp safe_path_part(_value), do: :dynamic_key

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
          "#{result.text_referenced_bytes} | #{result.binary_count} | " <>
          "#{result.borrowed_binary_count} | #{result.sensitive_binary_count} | " <>
          "#{format(result.amplification)}x | " <>
          "#{result.holder_binary_bytes} | #{result.holder_terminated} | #{result.passed} |"
      end)

    [
      "# Fast Profile Binary Retention Probe",
      "",
      "- Label: `#{report.label}`",
      "- Source: `#{report.source.commit}`",
      "- Dirty: `#{report.source.dirty}`",
      "- Elixir / OTP: `#{report.environment.elixir}` / `#{report.environment.otp}`",
      "",
      "| Case | Expectation | Text bytes | Text referenced | Graph binaries | " <>
        "Borrowed graph binaries | Sensitive graph binaries | Max amplification | " <>
        "Holder binary bytes | " <>
        "Holder terminated | Passed |",
      "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |",
      rows,
      ""
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp format(value), do: :erlang.float_to_binary(value / 1, decimals: 3)
end

Obscura.FastProfileRetentionProbe.run(System.argv())
