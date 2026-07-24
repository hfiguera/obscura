Mix.Task.run("app.start")

defmodule Obscura.FastProfileBenchmark do
  @moduledoc false

  alias Obscura.Eval.Operational.Statistics
  alias Obscura.Recognizer.Registry
  alias Obscura.Vault.Memory

  @common_text """
  Rachel works at Google in Paris. Contact her at info@example.test or
  +1 202-555-0188. Visit example.test. Card 4111 1111 1111 1111.
  """

  @entities [:email, :phone, :credit_card, :us_ssn, :ip_address, :url, :domain]
  @all_entities Registry.entities()

  @entity_samples %{
    credit_card: "Card 4111 1111 1111 1111",
    date_time: "Recorded 2026-07-23 12:34:56",
    domain: "Visit example.test",
    email: "Contact probe@example.test",
    iban: "IBAN GB82 WEST 1234 5698 7654 32",
    ip_address: "Address 192.0.2.1",
    location: "Where: Paris",
    person: "My name is Rachel Green,",
    phone: "Call +1 202-555-0188",
    street_address: "address: 12 Main Street, Denver",
    title: "Dr. Green",
    url: "Visit https://example.test/path",
    us_ssn: "SSN 123-45-6789"
  }

  def run(args) do
    opts = parse_args(args)
    {:ok, vault} = Memory.start_link()
    {:ok, _token} = Obscura.Vault.get_or_create(vault, :email, "probe@example.test")

    report =
      try do
        %{
          schema_version: 2,
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
          cases:
            opts
            |> cases(vault)
            |> select_cases(opts.only)
            |> Enum.map(&run_case(&1, opts))
        }
      after
        GenServer.stop(vault)
      end

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
          scale: :float,
          only: :string
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
      scale: scale,
      only: parsed |> Keyword.get(:only) |> parse_case_names()
    }
  end

  defp cases(opts, vault) do
    one_kib = padded_text(1_024, "probe@example.test")
    sixty_four_kib = padded_text(65_536, "probe@example.test")
    one_mib = padded_text(1_048_576, "probe@example.test")
    long_url = "https://example.test/" <> String.duplicate("segment/", 64)
    retained_url = padded_text(400_000, long_url)

    base_cases = [
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

    base_cases ++
      batch_boundary_cases(opts) ++
      operator_cases(opts, vault) ++
      boundary_integration_cases(opts) ++
      recognizer_cases(opts) ++
      input_shape_cases(opts) ++
      phone_parser_cases(opts)
  end

  defp parse_case_names(nil), do: nil

  defp parse_case_names(value) do
    value
    |> String.split(",", trim: true)
    |> MapSet.new()
  end

  defp select_cases(cases, nil), do: cases

  defp select_cases(cases, names) do
    selected = Enum.filter(cases, &MapSet.member?(names, &1.name))
    found = MapSet.new(selected, & &1.name)
    missing = MapSet.difference(names, found)

    if MapSet.size(missing) > 0 do
      raise ArgumentError, "unknown benchmark cases: #{inspect(MapSet.to_list(missing))}"
    end

    selected
  end

  defp batch_boundary_cases(opts) do
    for batch_size <- [1, 128] do
      benchmark_case(
        "analyze_many_batch_#{batch_size}",
        byte_size(@common_text) * batch_size,
        iterations(if(batch_size == 1, do: 3_000, else: 50), opts),
        fn ->
          Obscura.Analyzer.analyze_many(List.duplicate(@common_text, batch_size),
            profile: :fast,
            entities: @entities,
            include_text: false,
            telemetry: false
          )
        end
      )
    end
  end

  defp operator_cases(opts, vault) do
    text = "Contact probe@example.test"
    span = %{entity: :email, byte_start: 8, byte_end: 26}

    operators = [
      replace: %{type: :replace, value: "[EMAIL]"},
      redact: %{type: :redact},
      mask: %{type: :mask, char: "*", keep_last: 4},
      hash: %{
        type: :hash,
        algorithm: :sha256,
        mode: :deterministic,
        salt: "0123456789abcdef"
      },
      pseudonymize: %{type: :pseudonymize, vault: vault}
    ]

    Enum.map(operators, fn {name, config} ->
      benchmark_case(
        "anonymize_operator_#{name}",
        byte_size(text),
        iterations(4_000, opts),
        fn ->
          Obscura.anonymize(text, [span],
            operators: %{email: config},
            telemetry: false
          )
        end
      )
    end)
  end

  defp boundary_integration_cases(opts) do
    logger_input = %{request: %{contact: @common_text}}

    plug_conn =
      :post
      |> Plug.Test.conn("/", %{})
      |> Map.put(:params, %{"contact" => @common_text})

    [
      benchmark_case(
        "logger_redact_term",
        byte_size(@common_text),
        iterations(1_500, opts),
        fn ->
          Obscura.Logger.redact_term(logger_input,
            profile: :fast,
            entities: @entities,
            telemetry: false
          )
        end
      ),
      benchmark_case(
        "plug_replace_params",
        byte_size(@common_text),
        iterations(1_500, opts),
        fn ->
          Obscura.Phoenix.Plug.call(plug_conn,
            fields: [:params],
            mode: :replace,
            profile: :fast,
            entities: @entities,
            telemetry: false
          )
        end
      )
    ]
  end

  defp recognizer_cases(opts) do
    Enum.map(@all_entities, fn entity ->
      text = Map.fetch!(@entity_samples, entity)

      benchmark_case(
        "recognizer_#{entity}",
        byte_size(text),
        iterations(2_000, opts),
        fn ->
          Obscura.analyze(text,
            profile: :fast,
            entities: [entity],
            include_text: false,
            telemetry: false
          )
        end
      )
    end)
  end

  defp input_shape_cases(opts) do
    email = "probe@example.test"
    multibyte = "Jos\u00E9 \u6771\u4EAC \uD55C\uAD6D\uC5B4 "
    dense = Enum.join(List.duplicate(email, 100), " ")
    many_lines = Enum.join(List.duplicate("safe line\n", 200), "") <> email
    overlap = "https://subdomain.example.test/path"
    invalid = <<0xFF, 0xFE, 0xFD>>

    [
      analyze_case("analyze_no_match_128b", safe_padding(128), @entities, 6_000, opts),
      analyze_case("analyze_no_match_64k", safe_padding(65_536), @entities, 300, opts),
      analyze_case("analyze_no_match_1m", safe_padding(1_048_576), @entities, 20, opts),
      analyze_case(
        "analyze_match_at_beginning_64k",
        email <> safe_padding(65_536 - byte_size(email)),
        [:email],
        500,
        opts
      ),
      analyze_case(
        "analyze_match_at_end_64k",
        safe_padding(65_536 - byte_size(email)) <> email,
        [:email],
        500,
        opts
      ),
      analyze_case(
        "analyze_multibyte_utf8",
        multibyte <> email <> multibyte,
        [:email],
        3_000,
        opts
      ),
      analyze_case("analyze_dense_matches", dense, [:email], 200, opts),
      analyze_case("analyze_many_short_lines", many_lines, [:email], 500, opts),
      analyze_case("analyze_overlapping_url_domain", overlap, [:url, :domain], 2_000, opts),
      benchmark_case(
        "analyze_malformed_utf8_error",
        byte_size(invalid),
        iterations(5_000, opts),
        fn -> {:ok, Obscura.analyze(invalid, profile: :fast, entities: [:email])} end
      )
    ]
  end

  defp phone_parser_cases(opts) do
    text = "Office +44 20 7946 0958"

    disabled =
      analyze_case("phone_parser_disabled", text, [:phone], 2_000, opts, phone_parser: nil)

    if Code.ensure_loaded?(ExPhoneNumber) do
      [
        disabled,
        analyze_case("phone_parser_enabled", text, [:phone], 2_000, opts,
          phone_parser: Obscura.Recognizer.Phone.ExPhoneNumberValidator,
          phone_regions: ["GB"]
        )
      ]
    else
      [disabled]
    end
  end

  defp analyze_case(name, text, entities, base_iterations, opts, extra_opts \\ []) do
    benchmark_case(name, byte_size(text), iterations(base_iterations, opts), fn ->
      Obscura.analyze(
        text,
        [
          profile: :fast,
          entities: entities,
          include_text: false,
          telemetry: false
        ] ++ extra_opts
      )
    end)
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
    system_before = system_snapshot()

    repetitions =
      for repetition <- 1..opts.repetitions do
        run_repetition(case_data, warmup_iterations, repetition)
      end

    system_after = system_snapshot()

    %{
      name: case_data.name,
      input_bytes: case_data.input_bytes,
      iterations: case_data.iterations,
      warmup_iterations: warmup_iterations,
      repetitions: repetitions,
      median: median_repetition(repetitions),
      system: %{
        binary_delta_bytes: system_after.binary_bytes - system_before.binary_bytes,
        processes_delta_bytes: system_after.processes_bytes - system_before.processes_bytes,
        total_delta_bytes: system_after.total_bytes - system_before.total_bytes,
        rss_delta_bytes: numeric_delta(system_after.rss_bytes, system_before.rss_bytes)
      }
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
      garbage_collections: after_snapshot.garbage_collections - before.garbage_collections,
      reclaimed_words: after_snapshot.reclaimed_words - before.reclaimed_words,
      memory_before_bytes: before.memory,
      memory_after_bytes: after_snapshot.memory,
      total_heap_before_words: before.total_heap_size,
      total_heap_after_words: after_snapshot.total_heap_size,
      process_binary_before_bytes: before.process_binary_bytes,
      process_binary_after_bytes: after_snapshot.process_binary_bytes,
      result_count: result_count(first),
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
        :garbage_collection,
        :binary
      ])

    garbage_collection = Keyword.fetch!(info, :garbage_collection)
    process_binaries = Keyword.fetch!(info, :binary)
    {garbage_collections, reclaimed_words, _} = :erlang.statistics(:garbage_collection)

    %{
      memory: Keyword.fetch!(info, :memory),
      reductions: Keyword.fetch!(info, :reductions),
      total_heap_size: Keyword.fetch!(info, :total_heap_size),
      minor_gcs: Keyword.get(garbage_collection, :minor_gcs, 0),
      garbage_collections: garbage_collections,
      reclaimed_words: reclaimed_words,
      process_binary_bytes: Enum.sum(Enum.map(process_binaries, &elem(&1, 1)))
    }
  end

  defp system_snapshot do
    memory = :erlang.memory([:binary, :processes, :total])

    %{
      binary_bytes: Keyword.fetch!(memory, :binary),
      processes_bytes: Keyword.fetch!(memory, :processes),
      total_bytes: Keyword.fetch!(memory, :total),
      rss_bytes: rss_bytes()
    }
  end

  defp rss_bytes do
    case System.cmd("ps", ["-o", "rss=", "-p", System.pid()], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> Integer.parse()
        |> case do
          {rss_kib, ""} -> rss_kib * 1_024
          _invalid -> nil
        end

      _error ->
        nil
    end
  rescue
    _error -> nil
  end

  defp result_count(results) when is_list(results), do: length(List.flatten(results))
  defp result_count(%{items: items}) when is_list(items), do: length(items)
  defp result_count(%Plug.Conn{} = conn), do: map_size(conn.params)
  defp result_count(result) when is_map(result), do: map_size(result)
  defp result_count(_result), do: 0

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
      minor_gcs: median(repetitions, & &1.minor_gcs),
      garbage_collections: median(repetitions, & &1.garbage_collections),
      reclaimed_words: median(repetitions, & &1.reclaimed_words),
      process_binary_delta_bytes:
        median(
          repetitions,
          &(&1.process_binary_after_bytes - &1.process_binary_before_bytes)
        )
    }
  end

  defp numeric_delta(after_value, before_value)
       when is_number(after_value) and is_number(before_value),
       do: after_value - before_value

  defp numeric_delta(_after_value, _before_value), do: 0

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
          "#{format(median.reductions_per_operation)} | " <>
          "#{median.process_binary_delta_bytes} | #{benchmark.system.binary_delta_bytes} | " <>
          "#{benchmark.system.rss_delta_bytes} |"
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
      "| Case | Input bytes | p50 us | p95 us | p99 us | ops/s | reductions/op | " <>
        "Process binary delta | System binary delta | RSS delta |",
      "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
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
