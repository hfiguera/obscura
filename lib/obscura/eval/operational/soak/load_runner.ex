defmodule Obscura.Eval.Operational.Soak.LoadRunner do
  @moduledoc false

  alias Obscura.Eval.Operational.ResourceSampler
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.Soak.Analysis
  alias Obscura.Eval.Operational.Soak.Histogram
  alias Obscura.Eval.Operational.Statistics

  @default_sample_interval 1_000
  @default_window_ms 60_000
  @default_idle_ms 10_000
  @default_gc_settle_ms 1_000

  @spec run(pid(), [map()], keyword()) :: map()
  def run(host, samples, opts) when is_pid(host) and is_list(samples) and samples != [] do
    duration_ms = Keyword.fetch!(opts, :duration_ms)
    concurrency = Keyword.fetch!(opts, :concurrency)
    timeout = Keyword.fetch!(opts, :timeout)
    gpu? = Keyword.get(opts, :gpu, false)
    sample_interval = Keyword.get(opts, :sample_interval, @default_sample_interval)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)
    idle_ms = Keyword.get(opts, :idle_ms, @default_idle_ms)
    gc_settle_ms = Keyword.get(opts, :gc_settle_ms, @default_gc_settle_ms)
    diagnostics? = Keyword.get(opts, :diagnostics, false)
    environmental? = Keyword.get(opts, :environmental, diagnostics?)
    include_resource_series? = Keyword.get(opts, :include_resource_series, false)
    fingerprint_probe = fingerprint_probe(host, samples, timeout)
    :ok = RuntimeHost.reset_diagnostic_shapes(host)
    started = System.monotonic_time()
    deadline = started + milliseconds_to_native(duration_ms)

    {:ok, sampler} =
      ResourceSampler.start_link(
        gpu: gpu?,
        host: host,
        detailed: true,
        environmental: environmental?,
        interval: sample_interval
      )

    context = %{
      deadline: deadline,
      started: started,
      timeout: timeout,
      stride: concurrency,
      window_ms: window_ms,
      diagnostics: diagnostics?
    }

    sample_tuple = List.to_tuple(samples)

    workers =
      0..(concurrency - 1)
      |> Task.async_stream(
        fn worker ->
          worker(host, sample_tuple, worker, context, empty_worker())
        end,
        max_concurrency: concurrency,
        ordered: true,
        timeout: duration_ms + timeout + 5_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, summary} -> summary
        {:exit, _reason} -> %{empty_worker() | failed: 1}
      end)

    elapsed_ms = elapsed_ms(started)
    series = ResourceSampler.series(sampler)
    GenServer.stop(sampler)

    post_soak = post_soak_observations(host, gpu?, idle_ms, gc_settle_ms)
    analysis = Analysis.analyze(series, rolling_samples: rolling_samples(sample_interval))
    classification = Analysis.classify(analysis, post_soak)

    context = %{
      elapsed_ms: elapsed_ms,
      duration_ms: duration_ms,
      concurrency: concurrency,
      sample_interval: sample_interval,
      window_ms: window_ms,
      post_soak: post_soak,
      classification: classification,
      fingerprint_probe: fingerprint_probe,
      diagnostics: diagnostics?,
      resource_series: if(include_resource_series?, do: series, else: nil)
    }

    summarize(workers, samples, series, analysis, context)
  end

  defp worker(host, samples, index, context, summary) do
    if System.monotonic_time() >= context.deadline do
      summary
    else
      sample = elem(samples, rem(index, tuple_size(samples)))
      request_started = System.monotonic_time()

      result =
        RuntimeHost.analyze(host, sample.text,
          timeout: context.timeout,
          include_text: false
        )

      latency_ms = elapsed_ms(request_started)
      completion_ms = elapsed_ms(context.started)
      window = floor(completion_ms / context.window_ms)

      next_summary =
        summary
        |> record_result(result, sample, latency_ms, window)
        |> record_coverage(result, sample)

      worker(host, samples, index + context.stride, context, next_summary)
    end
  end

  defp record_result(summary, {:ok, results, service}, sample, latency_ms, window) do
    output_hash = output_hash(results)
    key = sample_key(sample)

    {fingerprints, rechecks, mismatches} =
      update_fingerprint(summary.fingerprints, key, output_hash)

    summary
    |> Map.update!(:completed, &(&1 + 1))
    |> Map.put(:fingerprints, fingerprints)
    |> Map.update!(:fingerprint_rechecks, &(&1 + rechecks))
    |> Map.update!(:fingerprint_mismatches, &(&1 + mismatches))
    |> update_window(window, :completed, latency_ms)
    |> record_diagnostics(window, service)
  end

  defp record_result(summary, {:error, %{code: :overloaded}}, _sample, _latency_ms, window) do
    summary
    |> Map.update!(:rejected, &(&1 + 1))
    |> update_window(window, :rejected, nil)
  end

  defp record_result(summary, {:error, %{code: code}}, _sample, _latency_ms, window)
       when code in [:request_timeout, :caller_timeout] do
    summary
    |> Map.update!(:timed_out, &(&1 + 1))
    |> update_window(window, :timed_out, nil)
  end

  defp record_result(summary, _result, _sample, _latency_ms, window) do
    summary
    |> Map.update!(:failed, &(&1 + 1))
    |> update_window(window, :failed, nil)
  end

  defp record_coverage(summary, {:ok, _results, _service}, sample) do
    dataset = sample.dataset_id

    coverage =
      Map.update(
        summary.coverage,
        dataset,
        %{requests: 1, unique: MapSet.new([sample.id])},
        fn row ->
          %{requests: row.requests + 1, unique: MapSet.put(row.unique, sample.id)}
        end
      )

    %{summary | coverage: coverage}
  end

  defp record_coverage(summary, _result, _sample), do: summary

  defp update_window(summary, index, status, latency_ms) do
    window = Map.get(summary.windows, index, empty_window())

    window =
      window
      |> Map.update!(status, &(&1 + 1))
      |> maybe_add_latency(latency_ms)

    put_in(summary.windows[index], window)
  end

  defp maybe_add_latency(window, nil), do: window

  defp maybe_add_latency(window, latency_ms),
    do: %{window | histogram: Histogram.add(window.histogram, latency_ms)}

  defp summarize(workers, samples, series, analysis, context) do
    counts = count_summary(workers)
    merged_windows = merge_windows(workers)
    fingerprints = merge_fingerprints(workers)
    configured_counts = Enum.frequencies_by(samples, & &1.dataset_id)
    coverage = coverage_summary(workers, configured_counts)
    fingerprint_rechecks = sum(workers, :fingerprint_rechecks)
    fingerprint_mismatches = sum(workers, :fingerprint_mismatches)

    %{
      status: :measured,
      requested_duration_ms: context.duration_ms,
      elapsed_ms: context.elapsed_ms,
      stop_reason:
        if(context.elapsed_ms >= context.duration_ms, do: :duration, else: :worker_failure),
      concurrency: context.concurrency,
      worker_count: length(workers),
      completed: counts.completed,
      failed: counts.failed,
      rejected: counts.rejected,
      timed_out: counts.timed_out,
      throughput_rps: Statistics.throughput(counts.completed, context.elapsed_ms),
      latency_ms: overall_latency(merged_windows),
      windows: window_summaries(merged_windows, context.elapsed_ms, context.window_ms),
      window_duration_ms: context.window_ms,
      sample_interval_ms: context.sample_interval,
      resource_sample_count: length(series),
      resource_sampling_coverage:
        sampling_coverage(series, context.duration_ms, context.sample_interval),
      dataset_coverage: coverage,
      output_stability: %{
        stable: fingerprint_mismatches == 0 and context.fingerprint_probe.stable,
        unique_samples: map_size(fingerprints),
        rechecks: fingerprint_rechecks,
        mismatches: fingerprint_mismatches,
        fingerprint: fingerprint(fingerprints),
        probe: context.fingerprint_probe
      },
      memory_analysis: analysis,
      memory_classification: context.classification,
      post_soak: context.post_soak,
      diagnostics: diagnostics_summary(merged_windows, context.diagnostics),
      resource_series: context.resource_series
    }
  end

  defp count_summary(workers) do
    %{
      completed: sum(workers, :completed),
      failed: sum(workers, :failed),
      rejected: sum(workers, :rejected),
      timed_out: sum(workers, :timed_out)
    }
  end

  defp merge_windows(workers) do
    workers
    |> Enum.flat_map(&Map.to_list(&1.windows))
    |> Enum.reduce(%{}, fn {index, row}, acc ->
      Map.update(acc, index, row, &merge_window(&1, row))
    end)
  end

  defp merge_window(left, right) do
    %{
      histogram: Histogram.merge(left.histogram, right.histogram),
      completed: left.completed + right.completed,
      failed: left.failed + right.failed,
      rejected: left.rejected + right.rejected,
      timed_out: left.timed_out + right.timed_out,
      diagnostic_requests: left.diagnostic_requests + right.diagnostic_requests,
      stage_histograms: merge_histogram_maps(left.stage_histograms, right.stage_histograms),
      metadata_histograms:
        merge_histogram_maps(left.metadata_histograms, right.metadata_histograms),
      unavailable_stages: Map.merge(left.unavailable_stages, right.unavailable_stages),
      first_seen_shapes: left.first_seen_shapes + right.first_seen_shapes,
      repeated_shapes: left.repeated_shapes + right.repeated_shapes,
      first_seen_shape_model_histogram:
        Histogram.merge(
          left.first_seen_shape_model_histogram,
          right.first_seen_shape_model_histogram
        ),
      repeated_shape_model_histogram:
        Histogram.merge(
          left.repeated_shape_model_histogram,
          right.repeated_shape_model_histogram
        ),
      sequence_lengths: MapSet.union(left.sequence_lengths, right.sequence_lengths),
      tracked_shape_count: max(left.tracked_shape_count, right.tracked_shape_count),
      shape_tracking_overflow: left.shape_tracking_overflow or right.shape_tracking_overflow
    }
  end

  defp window_summaries(windows, elapsed_ms, window_ms) do
    windows
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {index, row} ->
      start_ms = index * window_ms
      measured_ms = max(1.0, min(window_ms, elapsed_ms - start_ms))

      %{
        index: index,
        start_ms: start_ms,
        measured_ms: measured_ms,
        completed: row.completed,
        failed: row.failed,
        rejected: row.rejected,
        timed_out: row.timed_out,
        throughput_rps: Statistics.throughput(row.completed, measured_ms),
        latency_ms: Histogram.summarize(row.histogram),
        diagnostics: summarize_window_diagnostics(row)
      }
    end)
  end

  defp coverage_summary(workers, configured_counts) do
    merged =
      workers
      |> Enum.flat_map(&Map.to_list(&1.coverage))
      |> Enum.reduce(%{}, fn {dataset, row}, acc ->
        Map.update(acc, dataset, row, fn current ->
          %{
            requests: current.requests + row.requests,
            unique: MapSet.union(current.unique, row.unique)
          }
        end)
      end)

    Map.new(configured_counts, fn {dataset, configured} ->
      measured = Map.get(merged, dataset, %{requests: 0, unique: MapSet.new()})

      {dataset,
       %{
         configured_samples: configured,
         requests: measured.requests,
         unique_samples: MapSet.size(measured.unique),
         unique_coverage_ratio: MapSet.size(measured.unique) / configured
       }}
    end)
  end

  defp merge_fingerprints(workers) do
    Enum.reduce(workers, %{}, fn worker, acc ->
      Map.merge(acc, worker.fingerprints, &merge_fingerprint/3)
    end)
  end

  defp merge_fingerprint(_key, left, left), do: left
  defp merge_fingerprint(_key, _left, _right), do: :mismatch

  defp update_fingerprint(fingerprints, key, output_hash) do
    case Map.fetch(fingerprints, key) do
      :error -> {Map.put(fingerprints, key, output_hash), 0, 0}
      {:ok, ^output_hash} -> {fingerprints, 1, 0}
      {:ok, _other} -> {fingerprints, 1, 1}
    end
  end

  defp fingerprint_probe(host, samples, timeout) do
    selected =
      samples
      |> Enum.group_by(& &1.dataset_id)
      |> Enum.map(fn {_dataset, dataset_samples} -> List.first(dataset_samples) end)
      |> Enum.sort_by(&to_string(&1.dataset_id))

    rows =
      Enum.map(selected, fn sample ->
        hashes = Enum.map(1..2, fn _attempt -> probe_hash(host, sample, timeout) end)

        %{
          dataset: sample.dataset_id,
          stable: stable_hashes?(hashes),
          fingerprint: if(stable_hashes?(hashes), do: List.first(hashes), else: :mismatch)
        }
      end)

    %{stable: Enum.all?(rows, & &1.stable), datasets: rows}
  end

  defp stable_hashes?([first | rest]), do: Enum.all?(rest, &(&1 == first))
  defp stable_hashes?([]), do: false

  defp overall_latency(windows) do
    windows
    |> Map.values()
    |> Enum.reduce(Histogram.new(), fn row, histogram ->
      Histogram.merge(histogram, row.histogram)
    end)
    |> Histogram.summarize()
  end

  defp probe_hash(host, sample, timeout) do
    case RuntimeHost.analyze(host, sample.text, timeout: timeout, include_text: false) do
      {:ok, results, _service} -> output_hash(results)
      {:error, error} -> {:error, Map.take(error, [:code, :retryable])}
    end
  end

  defp post_soak_observations(host, gpu?, idle_ms, gc_settle_ms) do
    before_idle = ResourceSampler.capture(gpu: gpu?, host: host)
    Process.sleep(idle_ms)
    after_idle = ResourceSampler.capture(gpu: gpu?, host: host)
    :erlang.garbage_collect()
    :erlang.garbage_collect(host)
    Process.sleep(gc_settle_ms)
    after_gc = ResourceSampler.capture(gpu: gpu?, host: host)
    cache_clear = maybe_clear_emily_cache(gpu?)
    Process.sleep(gc_settle_ms)
    after_cache_clear = ResourceSampler.capture(gpu: gpu?, host: host)

    %{
      idle_duration_ms: idle_ms,
      gc_settle_ms: gc_settle_ms,
      before_idle: before_idle,
      after_idle: after_idle,
      after_gc: after_gc,
      cache_clear: cache_clear,
      after_cache_clear: after_cache_clear
    }
  end

  defp maybe_clear_emily_cache(false), do: %{status: :not_applicable}

  defp maybe_clear_emily_cache(true) do
    module = Module.concat([Emily, Memory])

    if Code.ensure_loaded?(module) and function_exported?(module, :clear_cache, 0) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(module, :clear_cache, [])
      %{status: :executed}
    else
      %{status: :unavailable}
    end
  rescue
    _error -> %{status: :failed}
  end

  defp output_hash(results) do
    results
    |> Enum.map(&{&1.entity, &1.byte_start, &1.byte_end})
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp fingerprint(fingerprints) do
    fingerprints
    |> Enum.sort_by(fn {key, _hash} -> key end)
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp sample_key(sample), do: "#{sample.dataset_id}:#{sample.id}"

  defp empty_worker do
    %{
      completed: 0,
      failed: 0,
      rejected: 0,
      timed_out: 0,
      windows: %{},
      coverage: %{},
      fingerprints: %{},
      fingerprint_rechecks: 0,
      fingerprint_mismatches: 0
    }
  end

  defp empty_window do
    %{
      histogram: Histogram.new(),
      completed: 0,
      failed: 0,
      rejected: 0,
      timed_out: 0,
      diagnostic_requests: 0,
      stage_histograms: %{},
      metadata_histograms: %{},
      unavailable_stages: %{},
      first_seen_shapes: 0,
      repeated_shapes: 0,
      first_seen_shape_model_histogram: Histogram.new(),
      repeated_shape_model_histogram: Histogram.new(),
      sequence_lengths: MapSet.new(),
      tracked_shape_count: 0,
      shape_tracking_overflow: false
    }
  end

  defp merge_histogram_maps(left, right) do
    Map.merge(left, right, fn _key, left_histogram, right_histogram ->
      Histogram.merge(left_histogram, right_histogram)
    end)
  end

  defp record_diagnostics(summary, window_index, service) when is_map(service) do
    case get_in(service, [:diagnostics, :status]) do
      :measured ->
        window = Map.fetch!(summary.windows, window_index)

        stages =
          service
          |> diagnostic_stage_values()
          |> Enum.reduce(window.stage_histograms, fn {stage, duration_ms}, acc ->
            add_histogram(acc, stage, duration_ms)
          end)

        metadata =
          service
          |> diagnostic_metadata_values()
          |> Enum.reduce(window.metadata_histograms, fn {key, value}, acc ->
            add_histogram(acc, key, value)
          end)

        unavailable =
          Map.merge(
            window.unavailable_stages,
            get_in(service, [:diagnostics, :unavailable]) || %{}
          )

        updated = %{
          window
          | diagnostic_requests: window.diagnostic_requests + 1,
            stage_histograms: stages,
            metadata_histograms: metadata,
            unavailable_stages: unavailable
        }

        put_in(summary.windows[window_index], record_model_shape(updated, service))

      _other ->
        summary
    end
  end

  defp diagnostic_stage_values(service) do
    base = [
      queue_admission: Map.get(service, :queue_ms),
      service_total: Map.get(service, :service_ms)
    ]

    nested =
      service
      |> get_in([:diagnostics, :stages])
      |> Kernel.||(%{})
      |> Enum.map(fn {stage, row} -> {stage, Map.get(row, :total_ms)} end)

    Enum.filter(base ++ nested, fn {_stage, value} -> is_number(value) and value >= 0 end)
  end

  defp add_histogram(histograms, key, value) do
    Map.update(histograms, key, Histogram.add(Histogram.new(), value), fn histogram ->
      Histogram.add(histogram, value)
    end)
  end

  defp diagnostic_metadata_values(service) do
    service
    |> get_in([:diagnostics, :metadata])
    |> Kernel.||(%{})
    |> Enum.filter(fn {_key, value} -> is_number(value) and value >= 0 end)
  end

  defp record_model_shape(window, %{model_shape: %{first_seen: first_seen} = shape})
       when is_boolean(first_seen) do
    model_ms = get_in(shape, [:model_ms])
    model_ms = model_ms || 0.0

    histogram_key =
      if first_seen, do: :first_seen_shape_model_histogram, else: :repeated_shape_model_histogram

    count_key = if first_seen, do: :first_seen_shapes, else: :repeated_shapes

    window
    |> Map.update!(count_key, &(&1 + 1))
    |> Map.update!(histogram_key, &Histogram.add(&1, model_ms))
    |> Map.update!(:sequence_lengths, &MapSet.put(&1, shape.sequence_length))
    |> Map.put(:tracked_shape_count, max(window.tracked_shape_count, shape.tracked_shape_count))
    |> Map.put(
      :shape_tracking_overflow,
      window.shape_tracking_overflow or shape.tracking_overflow
    )
  end

  defp record_model_shape(window, _service), do: window

  defp diagnostics_summary(_windows, false) do
    %{status: :disabled, stages: %{}, input: %{}, unavailable_stages: %{}}
  end

  defp diagnostics_summary(windows, true) do
    merged =
      windows
      |> Map.values()
      |> Enum.reduce(empty_window(), &merge_window/2)

    summarize_window_diagnostics(merged)
  end

  defp summarize_window_diagnostics(%{diagnostic_requests: 0}) do
    %{status: :unavailable, reason: :no_instrumented_requests}
  end

  defp summarize_window_diagnostics(row) do
    %{
      status: :measured,
      request_count: row.diagnostic_requests,
      stages:
        Map.new(row.stage_histograms, fn {stage, histogram} ->
          {stage, Histogram.summarize(histogram)}
        end),
      input:
        Map.new(row.metadata_histograms, fn {key, histogram} ->
          {key, Histogram.summarize(histogram)}
        end),
      unavailable_stages: row.unavailable_stages,
      model_shapes: %{
        tracked_shape_count: row.tracked_shape_count,
        tracking_overflow: row.shape_tracking_overflow,
        sequence_lengths: row.sequence_lengths |> MapSet.to_list() |> Enum.sort(),
        first_seen_requests: row.first_seen_shapes,
        repeated_requests: row.repeated_shapes,
        first_seen_model_ms: Histogram.summarize(row.first_seen_shape_model_histogram),
        repeated_model_ms: Histogram.summarize(row.repeated_shape_model_histogram)
      }
    }
  end

  defp sampling_coverage(series, duration_ms, interval_ms) do
    expected = max(1, floor(duration_ms / interval_ms))
    min(1.0, length(series) / expected)
  end

  defp rolling_samples(interval_ms), do: max(2, floor(60_000 / interval_ms))
  defp sum(rows, key), do: Enum.reduce(rows, 0, &(&2 + Map.fetch!(&1, key)))

  defp milliseconds_to_native(milliseconds),
    do: System.convert_time_unit(milliseconds, :millisecond, :native)

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
