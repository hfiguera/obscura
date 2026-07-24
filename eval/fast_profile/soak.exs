Mix.Task.run("app.start")

defmodule Obscura.FastProfileRetentionSoak do
  @moduledoc false

  @counter_completed 1
  @counter_failures 2
  @counter_controlled_failures 3
  @counter_held 4
  @counter_released 5
  @counter_slots 5

  defmodule ControlledFailureRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :fast_profile_controlled_failure

    @impl true
    def supported_entities, do: [:email]

    @impl true
    def analyze(_text, _opts), do: {:error, :expected_retention_probe_failure}
  end

  def run(args) do
    opts = parse_args(args)
    counters = :atomics.new(@counter_slots, signed: false)
    holder = start_holder(opts.hold_ms, counters)
    deadline = System.monotonic_time(:millisecond) + opts.duration_ms
    worker_inputs = inputs()

    workers =
      for worker_id <- 1..opts.concurrency do
        spawn_monitor(fn ->
          worker_loop(worker_id, 0, deadline, worker_inputs, holder, counters)
        end)
      end

    samples = sample_until_workers_stop(workers, holder, counters, opts)
    send(holder, {:release_all, self()})

    receive do
      {:holder_released, ^holder} -> :ok
    after
      5_000 -> raise "holder did not release retained results"
    end

    Process.sleep(opts.idle_ms)
    :erlang.garbage_collect(self())
    send(holder, {:collect, self()})

    final_holder =
      receive do
        {:holder_sample, ^holder, sample} -> sample
      after
        5_000 -> raise "holder did not provide final sample"
      end

    post_gc = memory_sample(counters, final_holder, elapsed_ms(opts))
    send(holder, :stop)

    report = build_report(opts, samples, post_gc, counters)
    write_report(opts.output, report)
    IO.puts("Wrote #{opts.output}")
  end

  defp parse_args(args) do
    args = Enum.drop_while(args, &(&1 == "--"))

    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          label: :string,
          output: :string,
          duration_ms: :integer,
          concurrency: :integer,
          sample_interval_ms: :integer,
          hold_ms: :integer,
          idle_ms: :integer
        ]
      )

    if remaining != [] or invalid != [], do: raise(ArgumentError, "invalid soak options")

    opts = %{
      label: Keyword.get(parsed, :label, "working"),
      output:
        Keyword.get(
          parsed,
          :output,
          "eval/reports/fast_profile/fast_profile_retention_soak.json"
        ),
      duration_ms: Keyword.get(parsed, :duration_ms, 1_800_000),
      concurrency: Keyword.get(parsed, :concurrency, 4),
      sample_interval_ms: Keyword.get(parsed, :sample_interval_ms, 1_000),
      hold_ms: Keyword.get(parsed, :hold_ms, 5_000),
      idle_ms: Keyword.get(parsed, :idle_ms, 10_000),
      started_at_ms: System.monotonic_time(:millisecond)
    }

    Enum.each(
      [:duration_ms, :concurrency, :sample_interval_ms, :hold_ms, :idle_ms],
      fn key ->
        if Map.fetch!(opts, key) < 1, do: raise(ArgumentError, "#{key} must be positive")
      end
    )

    opts
  end

  defp inputs do
    %{
      no_match: safe_padding(262_144),
      tiny_match: padded_text(262_144, "probe@example.test"),
      many_candidates:
        padded_text(
          262_144,
          Enum.map_join(1..200, " ", &"candidate#{&1}@example.test")
        ),
      structured: safe_padding(131_072),
      failure: safe_padding(131_072)
    }
  end

  defp worker_loop(worker_id, sequence, deadline, inputs, holder, counters) do
    if System.monotonic_time(:millisecond) < deadline do
      unique = Integer.to_string(worker_id) <> ":" <> Integer.to_string(sequence)

      case run_workload(rem(sequence, 6), unique, inputs, holder, counters) do
        :ok -> :atomics.add(counters, @counter_completed, 1)
        :controlled_failure -> :atomics.add(counters, @counter_controlled_failures, 1)
        :failure -> :atomics.add(counters, @counter_failures, 1)
      end

      worker_loop(worker_id, sequence + 1, deadline, inputs, holder, counters)
    end
  end

  defp run_workload(0, unique, inputs, _holder, _counters) do
    text = inputs.no_match <> unique

    case Obscura.analyze(text,
           profile: :fast,
           entities: [:email],
           include_text: false,
           telemetry: false
         ) do
      {:ok, []} -> :ok
      _other -> :failure
    end
  end

  defp run_workload(1, unique, inputs, _holder, _counters) do
    text = inputs.tiny_match <> unique

    case Obscura.analyze(text,
           profile: :fast,
           entities: [:email],
           include_text: false,
           telemetry: false
         ) do
      {:ok, [%{text: nil}]} -> :ok
      _other -> :failure
    end
  end

  defp run_workload(2, unique, inputs, _holder, _counters) do
    text = inputs.many_candidates <> unique

    case Obscura.analyze(text,
           profile: :fast,
           entities: [:email],
           include_text: false,
           score_threshold: 1.1,
           telemetry: false
         ) do
      {:ok, []} -> :ok
      _other -> :failure
    end
  end

  defp run_workload(3, unique, inputs, holder, counters) do
    text = inputs.tiny_match <> unique

    case Obscura.analyze(text,
           profile: :fast,
           entities: [:email],
           include_text: true,
           telemetry: false
         ) do
      {:ok, [%{text: value} = result]} when is_binary(value) ->
        if :binary.referenced_byte_size(value) == byte_size(value) do
          send(holder, {:hold, result})
          :atomics.add(counters, @counter_held, 1)
          :ok
        else
          :failure
        end

      _other ->
        :failure
    end
  end

  defp run_workload(4, unique, inputs, _holder, _counters) do
    value = inputs.structured <> unique

    case Obscura.Structured.redact(
           %{payload: value, nested: [%{value: value}, value]},
           profile: :fast,
           entities: [:email],
           telemetry: false
         ) do
      {:ok, _result} -> :ok
      _other -> :failure
    end
  end

  defp run_workload(5, unique, inputs, _holder, _counters) do
    text = inputs.failure <> unique

    case Obscura.analyze(text,
           profile: :fast,
           built_ins: false,
           entities: [:email],
           recognizers: [ControlledFailureRecognizer],
           include_text: false,
           telemetry: false
         ) do
      {:error, {:recognizer_failed, :fast_profile_controlled_failure, _reason}} ->
        :controlled_failure

      _other ->
        :failure
    end
  end

  defp start_holder(hold_ms, counters) do
    spawn_link(fn -> holder_loop([], hold_ms, counters) end)
  end

  defp holder_loop(held, hold_ms, counters) do
    receive do
      {:hold, result} ->
        now = System.monotonic_time(:millisecond)

        holder_loop(
          [{now + hold_ms, result} | release_expired(held, now, counters)],
          hold_ms,
          counters
        )

      {:collect, caller} ->
        now = System.monotonic_time(:millisecond)
        current = release_expired(held, now, counters)
        :erlang.garbage_collect(self())
        send(caller, {:holder_sample, self(), holder_sample(current)})
        holder_loop(current, hold_ms, counters)

      {:release_all, caller} ->
        :atomics.add(counters, @counter_released, length(held))
        :erlang.garbage_collect(self())
        send(caller, {:holder_released, self()})
        holder_loop([], hold_ms, counters)

      :stop ->
        :ok
    after
      min(hold_ms, 1_000) ->
        now = System.monotonic_time(:millisecond)
        holder_loop(release_expired(held, now, counters), hold_ms, counters)
    end
  end

  defp release_expired(held, now, counters) do
    {expired, current} = Enum.split_with(held, fn {expires_at, _result} -> expires_at <= now end)
    :atomics.add(counters, @counter_released, length(expired))
    current
  end

  defp holder_sample(held) do
    info = Process.info(self(), [:memory, :message_queue_len, :binary])
    binaries = Keyword.get(info, :binary, [])

    %{
      held_results: length(held),
      memory_bytes: Keyword.fetch!(info, :memory),
      message_queue_len: Keyword.fetch!(info, :message_queue_len),
      binary_count: length(binaries),
      binary_bytes: Enum.reduce(binaries, 0, fn {_binary, size, _refs}, acc -> acc + size end)
    }
  end

  defp sample_until_workers_stop(workers, holder, counters, opts) do
    monitors = Map.new(workers, fn {pid, monitor} -> {monitor, pid} end)
    next_sample = System.monotonic_time(:millisecond)
    collect_samples(monitors, holder, counters, opts, next_sample, [])
  end

  defp collect_samples(monitors, holder, counters, opts, next_sample, samples) do
    now = System.monotonic_time(:millisecond)

    cond do
      map_size(monitors) == 0 ->
        Enum.reverse(samples)

      now >= next_sample ->
        send(holder, {:collect, self()})

        holder_observation =
          receive do
            {:holder_sample, ^holder, sample} -> sample
          after
            5_000 -> raise "holder sampling timed out"
          end

        sample = memory_sample(counters, holder_observation, elapsed_ms(opts))

        collect_samples(
          monitors,
          holder,
          counters,
          opts,
          now + opts.sample_interval_ms,
          [sample | samples]
        )

      true ->
        receive do
          {:DOWN, monitor, :process, _pid, :normal} ->
            collect_samples(
              Map.delete(monitors, monitor),
              holder,
              counters,
              opts,
              next_sample,
              samples
            )

          {:DOWN, _monitor, :process, _pid, reason} ->
            raise "soak worker failed: #{inspect(reason)}"
        after
          min(next_sample - now, 100) ->
            collect_samples(monitors, holder, counters, opts, next_sample, samples)
        end
    end
  end

  defp memory_sample(counters, holder, elapsed_ms) do
    memory = :erlang.memory()

    %{
      elapsed_ms: elapsed_ms,
      completed_requests: :atomics.get(counters, @counter_completed),
      failures: :atomics.get(counters, @counter_failures),
      controlled_failures: :atomics.get(counters, @counter_controlled_failures),
      beam_total_bytes: memory[:total],
      beam_process_bytes: memory[:processes],
      beam_binary_bytes: memory[:binary],
      beam_ets_bytes: memory[:ets],
      rss_bytes: rss_bytes(),
      run_queue: :erlang.statistics(:run_queue),
      holder: holder
    }
  end

  defp build_report(opts, samples, post_gc, counters) do
    all_samples = samples ++ [Map.put(post_gc, :phase, "post_idle_gc")]
    first = List.first(samples) || post_gc
    last = List.last(samples) || post_gc
    half = max(div(length(samples), 2), 1)
    first_half = Enum.take(samples, half)
    final_half = Enum.drop(samples, half)

    slopes = %{
      first_half_binary_bytes_per_minute: slope(first_half, :beam_binary_bytes),
      final_half_binary_bytes_per_minute: slope(final_half, :beam_binary_bytes),
      first_half_rss_bytes_per_minute: slope(first_half, :rss_bytes),
      final_half_rss_bytes_per_minute: slope(final_half, :rss_bytes)
    }

    %{
      schema_version: 1,
      kind: "fast_profile_targeted_retention_soak",
      label: opts.label,
      source: source_metadata(),
      environment: environment(),
      configuration: %{
        profile: "fast",
        duration_ms: opts.duration_ms,
        concurrency: opts.concurrency,
        sample_interval_ms: opts.sample_interval_ms,
        hold_ms: opts.hold_ms,
        idle_ms: opts.idle_ms,
        input_values_recorded: false
      },
      workload: [
        "large_no_match_without_text",
        "large_tiny_match_without_text",
        "many_rejected_candidates_without_text",
        "large_tiny_match_with_bounded_hold",
        "structured_large_binary_leaves",
        "controlled_recognizer_failure"
      ],
      counters: %{
        completed_requests: :atomics.get(counters, @counter_completed),
        failures: :atomics.get(counters, @counter_failures),
        controlled_failures: :atomics.get(counters, @counter_controlled_failures),
        held_results: :atomics.get(counters, @counter_held),
        released_results: :atomics.get(counters, @counter_released)
      },
      observations: %{
        initial: first,
        final_active: last,
        post_idle_gc: post_gc,
        peak: peak_sample(all_samples),
        slopes: slopes,
        throughput: throughput_summary(samples)
      },
      classification: classify(first, last, post_gc, slopes),
      samples: all_samples
    }
  end

  defp classify(first, last, post_gc, slopes) do
    binary_growth = post_gc.beam_binary_bytes - first.beam_binary_bytes
    final_slope = slopes.final_half_binary_bytes_per_minute

    {status, reason} =
      cond do
        binary_growth > 16 * 1_048_576 and final_slope > 1_048_576 ->
          {"probable_leak", "binary memory grows after idle GC and in the final half"}

        binary_growth <= 4 * 1_048_576 and final_slope <= 256 * 1_024 and
            post_gc.holder.binary_bytes <= 1_048_576 ->
          {"stable_plateau", "post-GC binary growth and final-half slope stayed within bounds"}

        true ->
          {"inconclusive", "finite-run memory evidence did not satisfy leak or plateau bounds"}
      end

    %{
      status: status,
      reason: reason,
      finite_run_only: true,
      secure_erasure_proven: false,
      post_gc_binary_growth_bytes: binary_growth,
      active_binary_growth_bytes: last.beam_binary_bytes - first.beam_binary_bytes,
      stable_binary_growth_limit_bytes: 4 * 1_048_576,
      stable_final_slope_limit_bytes_per_minute: 256 * 1_024
    }
  end

  defp peak_sample(samples) do
    %{
      beam_total_bytes: max_value(samples, :beam_total_bytes),
      beam_process_bytes: max_value(samples, :beam_process_bytes),
      beam_binary_bytes: max_value(samples, :beam_binary_bytes),
      beam_ets_bytes: max_value(samples, :beam_ets_bytes),
      rss_bytes: max_value(samples, :rss_bytes),
      run_queue: max_value(samples, :run_queue),
      holder_memory_bytes: max_nested_value(samples, [:holder, :memory_bytes]),
      holder_binary_bytes: max_nested_value(samples, [:holder, :binary_bytes]),
      holder_message_queue_len: max_nested_value(samples, [:holder, :message_queue_len])
    }
  end

  defp throughput_summary([]), do: %{}

  defp throughput_summary(samples) do
    half = max(div(length(samples), 2), 1)

    %{
      overall_requests_per_second: request_rate(samples),
      first_half_requests_per_second: request_rate(Enum.take(samples, half)),
      final_half_requests_per_second: request_rate(Enum.drop(samples, half))
    }
  end

  defp request_rate(samples) when length(samples) < 2, do: 0.0

  defp request_rate(samples) do
    first = List.first(samples)
    last = List.last(samples)
    elapsed_seconds = max(last.elapsed_ms - first.elapsed_ms, 1) / 1_000
    (last.completed_requests - first.completed_requests) / elapsed_seconds
  end

  defp slope(samples, _key) when length(samples) < 2, do: 0.0

  defp slope(samples, key) do
    first = List.first(samples)
    last = List.last(samples)
    elapsed_minutes = max(last.elapsed_ms - first.elapsed_ms, 1) / 60_000
    (Map.fetch!(last, key) - Map.fetch!(first, key)) / elapsed_minutes
  end

  defp max_value(samples, key), do: samples |> Enum.map(&Map.fetch!(&1, key)) |> Enum.max()

  defp max_nested_value(samples, path),
    do: samples |> Enum.map(&get_in(&1, path)) |> Enum.max()

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

  defp elapsed_ms(opts), do: System.monotonic_time(:millisecond) - opts.started_at_ms

  defp rss_bytes do
    pid = System.pid()

    case System.cmd("ps", ["-o", "rss=", "-p", pid], stderr_to_stdout: true) do
      {output, 0} ->
        case Integer.parse(String.trim(output)) do
          {kilobytes, ""} -> kilobytes * 1_024
          _other -> 0
        end

      _other ->
        0
    end
  rescue
    _error -> 0
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

  defp write_report(path, report) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode_to_iodata!(report, pretty: true))
    File.write!(Path.rootname(path) <> ".md", markdown(report))
  end

  defp markdown(report) do
    observations = report.observations

    [
      "# Fast Profile Targeted Retention Soak",
      "",
      "- Label: `#{report.label}`",
      "- Source: `#{report.source.commit}`",
      "- Dirty: `#{report.source.dirty}`",
      "- Duration / concurrency: #{report.configuration.duration_ms} ms / " <>
        "#{report.configuration.concurrency}",
      "- Classification: `#{report.classification.status}`",
      "- Reason: #{report.classification.reason}",
      "- Finite run only: `#{report.classification.finite_run_only}`",
      "- Secure erasure proven: `#{report.classification.secure_erasure_proven}`",
      "",
      "| Metric | Initial | Final active | Post-idle GC | Peak |",
      "| --- | ---: | ---: | ---: | ---: |",
      row(
        "BEAM total bytes",
        observations,
        :beam_total_bytes,
        observations.peak.beam_total_bytes
      ),
      row(
        "BEAM binary bytes",
        observations,
        :beam_binary_bytes,
        observations.peak.beam_binary_bytes
      ),
      row("RSS bytes", observations, :rss_bytes, observations.peak.rss_bytes),
      row(
        "Holder binary bytes",
        observations,
        [:holder, :binary_bytes],
        observations.peak.holder_binary_bytes
      ),
      "",
      "## Throughput",
      "",
      "- Overall: #{format(observations.throughput.overall_requests_per_second)} req/s",
      "- First half: #{format(observations.throughput.first_half_requests_per_second)} req/s",
      "- Final half: #{format(observations.throughput.final_half_requests_per_second)} req/s",
      "",
      "## Counters",
      "",
      "- Completed: #{report.counters.completed_requests}",
      "- Unexpected failures: #{report.counters.failures}",
      "- Controlled failures: #{report.counters.controlled_failures}",
      "- Held / released results: #{report.counters.held_results} / " <>
        "#{report.counters.released_results}",
      "",
      "Input values are not recorded. This classifies bounded finite-run retention evidence; " <>
        "it does not prove secure erasure or universal absence of leaks.",
      ""
    ]
    |> Enum.join("\n")
  end

  defp row(label, observations, key, peak) when is_atom(key) do
    "| #{label} | #{Map.fetch!(observations.initial, key)} | " <>
      "#{Map.fetch!(observations.final_active, key)} | " <>
      "#{Map.fetch!(observations.post_idle_gc, key)} | #{peak} |"
  end

  defp row(label, observations, path, peak) do
    "| #{label} | #{get_in(observations.initial, path)} | " <>
      "#{get_in(observations.final_active, path)} | " <>
      "#{get_in(observations.post_idle_gc, path)} | #{peak} |"
  end

  defp format(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format(value), do: to_string(value)
end

Obscura.FastProfileRetentionSoak.run(System.argv())
