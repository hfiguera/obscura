defmodule Obscura.Eval.Operational.Diagnostic.Analysis do
  @moduledoc false

  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.Statistics
  alias Obscura.Eval.Operational.SystemProbe

  @resource_metrics %{
    scheduler_utilization: [:scheduler_utilization],
    run_queue: [:run_queue],
    beam_rss_bytes: [:rss_bytes],
    beam_process_count: [:system, :beam_runtime, :process_count],
    process_cpu_percent: [:system, :process_cpu_percent],
    in_flight: [:host, :in_flight],
    mailbox_length: [:host, :message_queue_len],
    emily_active_bytes: [:gpu_memory, :active],
    emily_cache_bytes: [:gpu_memory, :cache]
  }

  @counter_metrics %{
    reductions: [:system, :beam_runtime, :reductions],
    garbage_collections: [:system, :beam_runtime, :garbage_collections],
    garbage_reclaimed_words: [:system, :beam_runtime, :garbage_reclaimed_words]
  }

  @spec analyze(map()) :: map()
  def analyze(load) do
    windows = complete_windows(load.windows, load.window_duration_ms)
    resources = resource_windows(load.resource_series || [], load.window_duration_ms, windows)
    timeline = build_timeline(windows, resources)

    %{
      window_count: length(timeline),
      timeline: timeline,
      first_middle_last: first_middle_last(timeline),
      stage_share_percent: stage_shares(load.diagnostics),
      correlations: correlations(timeline),
      earliest_degrading_stage: earliest_degrading_stage(timeline),
      hypotheses: hypotheses(timeline, load.diagnostics),
      observability: observability(load)
    }
  end

  defp complete_windows(windows, window_ms) do
    Enum.filter(windows, fn window ->
      window.measured_ms >= window_ms * 0.95
    end)
  end

  defp build_timeline(windows, resources) do
    Enum.map(windows, fn window ->
      %{
        index: window.index,
        start_ms: window.start_ms,
        measured_ms: window.measured_ms,
        completed: window.completed,
        throughput_rps: window.throughput_rps,
        latency_ms: window.latency_ms,
        stages: get_in(window, [:diagnostics, :stages]) || %{},
        input: get_in(window, [:diagnostics, :input]) || %{},
        model_shapes: get_in(window, [:diagnostics, :model_shapes]) || %{},
        unavailable_stages: get_in(window, [:diagnostics, :unavailable_stages]) || %{},
        resources: Map.get(resources, window.index, %{})
      }
    end)
  end

  defp resource_windows(series, window_ms, workload_windows) do
    grouped = Enum.group_by(series, &floor(&1.elapsed_ms / window_ms))
    indexes = Enum.map(workload_windows, & &1.index)

    Map.new(indexes, fn index ->
      samples = Map.get(grouped, index, [])

      gauges =
        Map.new(@resource_metrics, fn {metric, path} ->
          {metric, values(samples, path) |> Statistics.summarize()}
        end)

      counters =
        Map.new(@counter_metrics, fn {metric, path} ->
          {metric, counter_delta(samples, path)}
        end)

      {index, Map.merge(gauges, counters)}
    end)
  end

  defp correlations(timeline) do
    stage_keys =
      timeline
      |> Enum.flat_map(&Map.keys(&1.stages))
      |> Enum.uniq()

    input_keys =
      timeline
      |> Enum.flat_map(&Map.keys(&1.input))
      |> Enum.uniq()

    resource_keys =
      timeline
      |> Enum.flat_map(&Map.keys(&1.resources))
      |> Enum.uniq()

    %{
      latency:
        Map.new(~w(p50 p95 p99)a, fn percentile ->
          {percentile,
           correlate(timeline, & &1.throughput_rps, &get_in(&1, [:latency_ms, percentile]))}
        end),
      stages:
        Map.new(stage_keys, fn stage ->
          {stage, correlate(timeline, & &1.throughput_rps, &get_in(&1, [:stages, stage, :mean]))}
        end),
      input:
        Map.new(input_keys, fn key ->
          {key, correlate(timeline, & &1.throughput_rps, &get_in(&1, [:input, key, :mean]))}
        end),
      resources:
        Map.new(resource_keys, fn key ->
          {key, correlate(timeline, & &1.throughput_rps, &resource_value(&1, key))}
        end)
    }
  end

  defp correlate(rows, left_fun, right_fun) do
    points =
      rows
      |> Enum.map(&{left_fun.(&1), right_fun.(&1)})
      |> Enum.filter(fn {left, right} -> is_number(left) and is_number(right) end)

    case points do
      [_first, _second | _rest] ->
        case Common.pearson_coefficient(points) do
          {:ok, coefficient} ->
            %{status: :measured, coefficient: coefficient, sample_count: length(points)}

          {:error, :zero_variance} ->
            %{status: :unavailable, reason: :zero_variance, sample_count: length(points)}
        end

      _other ->
        %{status: :unavailable, reason: :insufficient_windows, sample_count: length(points)}
    end
  end

  defp first_middle_last([]), do: %{status: :unavailable}

  defp first_middle_last(timeline) do
    %{
      status: :measured,
      first: compact_window(List.first(timeline)),
      middle: compact_window(Enum.at(timeline, div(length(timeline), 2))),
      last: compact_window(List.last(timeline))
    }
  end

  defp compact_window(row) do
    Map.take(row, [:index, :throughput_rps, :latency_ms, :stages, :input, :resources])
  end

  defp stage_shares(%{status: :measured, stages: stages}) do
    service_mean = get_in(stages, [:service_total, :mean])

    if is_number(service_mean) and service_mean > 0 do
      Map.new(stages, fn {stage, summary} ->
        mean = summary.mean
        {stage, if(is_number(mean), do: mean / service_mean * 100, else: nil)}
      end)
    else
      %{}
    end
  end

  defp stage_shares(_diagnostics), do: %{}

  defp earliest_degrading_stage([]), do: %{status: :unavailable}

  defp earliest_degrading_stage([first | _rest] = timeline) do
    last = List.last(timeline)

    first.stages
    |> Map.keys()
    |> Enum.flat_map(&degrading_stage(&1, first, last))
    |> Enum.sort_by(fn {_stage, growth} -> -growth end)
    |> earliest_stage_result()
  end

  defp degrading_stage(stage, first, last) do
    first_mean = get_in(first, [:stages, stage, :mean])
    last_mean = get_in(last, [:stages, stage, :mean])

    case relative_growth(first_mean, last_mean) do
      growth when is_number(growth) and growth >= 0.15 -> [{stage, growth}]
      _other -> []
    end
  end

  defp earliest_stage_result([{stage, growth} | _rest]),
    do: %{status: :observed, stage: stage, first_to_last_growth_ratio: growth}

  defp earliest_stage_result([]), do: %{status: :not_observed}

  defp hypotheses(timeline, diagnostics) do
    [
      hypothesis(:changing_workload, changing_workload_evidence(timeline)),
      hypothesis(:first_seen_model_shape_compilation, shape_compilation_evidence(diagnostics)),
      hypothesis(:queue_buildup, growth_evidence(timeline, [:stages, :queue_admission, :mean])),
      hypothesis(:model_serving, growth_evidence(timeline, [:stages, :model_serving, :mean])),
      hypothesis(:scheduler_pressure, growth_evidence(timeline, [:resources, :run_queue, :mean])),
      hypothesis(
        :allocator_behavior,
        growth_evidence(timeline, [:resources, :emily_cache_bytes, :mean])
      ),
      %{
        hypothesis: :thermal_or_power_throttling,
        status: :inconclusive,
        reason: :requires_privileged_powermetrics_or_external_measurement
      },
      %{
        hypothesis: :attention_or_moe_internal_growth,
        status: :inconclusive,
        reason: :fused_compiled_device_graph
      }
    ]
  end

  defp shape_compilation_evidence(%{model_shapes: shapes}) do
    case shape_measurements(shapes) do
      {:ok, measurements} -> classify_shape_measurements(measurements)
      {:error, evidence} -> Map.put(evidence, :status, :inconclusive)
    end
  end

  defp shape_compilation_evidence(_diagnostics), do: %{status: :inconclusive}

  defp shape_measurements(shapes) do
    measurements = %{
      first_count: get_in(shapes, [:first_seen_model_ms, :count]) || 0,
      repeated_count: get_in(shapes, [:repeated_model_ms, :count]) || 0,
      first_mean: get_in(shapes, [:first_seen_model_ms, :mean]),
      repeated_mean: get_in(shapes, [:repeated_model_ms, :mean])
    }

    if valid_shape_measurements?(measurements),
      do: {:ok, measurements},
      else:
        {:error,
         %{
           first_seen_count: measurements.first_count,
           repeated_count: measurements.repeated_count
         }}
  end

  defp valid_shape_measurements?(measurements) do
    measurements.first_count >= 2 and measurements.repeated_count >= 2 and
      is_number(measurements.first_mean) and is_number(measurements.repeated_mean) and
      measurements.repeated_mean != 0
  end

  defp classify_shape_measurements(measurements) do
    ratio = measurements.first_mean / measurements.repeated_mean

    %{
      status: if(ratio >= 2, do: :supported, else: :rejected),
      first_seen_count: measurements.first_count,
      repeated_count: measurements.repeated_count,
      first_seen_mean_ms: measurements.first_mean,
      repeated_mean_ms: measurements.repeated_mean,
      first_seen_to_repeated_ratio: ratio
    }
  end

  defp hypothesis(name, %{status: status} = evidence) do
    %{hypothesis: name, status: status, evidence: Map.delete(evidence, :status)}
  end

  defp changing_workload_evidence(timeline) do
    keys = [:input_bytes, :token_count, :window_count]

    rows =
      Map.new(keys, fn key ->
        {key, first_last_growth(timeline, [:input, key, :mean])}
      end)

    measured = rows |> Map.values() |> Enum.filter(&is_number/1)

    cond do
      measured == [] -> %{status: :inconclusive, metrics: rows}
      Enum.any?(measured, &(abs(&1) >= 0.15)) -> %{status: :supported, metrics: rows}
      true -> %{status: :rejected, metrics: rows}
    end
  end

  defp growth_evidence(timeline, path) do
    case first_last_growth(timeline, path) do
      nil -> %{status: :inconclusive}
      growth when growth >= 0.15 -> %{status: :supported, first_to_last_growth_ratio: growth}
      growth -> %{status: :rejected, first_to_last_growth_ratio: growth}
    end
  end

  defp first_last_growth([], _path), do: nil

  defp first_last_growth(timeline, path) do
    first = get_in(List.first(timeline), path)
    last = get_in(List.last(timeline), path)

    relative_growth(first, last)
  end

  defp relative_growth(first, last)
       when is_number(first) and first != 0 and is_number(last),
       do: (last - first) / abs(first)

  defp relative_growth(_first, _last), do: nil

  defp observability(load) do
    unavailable =
      case load.diagnostics do
        %{unavailable_stages: unavailable} -> unavailable
        _other -> %{}
      end

    %{
      stage_instrumentation: load.diagnostics.status,
      unavailable_stages: unavailable,
      system_capabilities: SystemProbe.capabilities(),
      gpu_backend_proof_is_not_gpu_utilization: true,
      emily_allocator_statistics_are_not_physical_gpu_residency: true
    }
  end

  defp resource_value(row, key) do
    case get_in(row, [:resources, key]) do
      %{mean: mean} -> mean
      %{delta: delta} -> delta
      _other -> nil
    end
  end

  defp counter_delta(samples, path) do
    values = values(samples, path)

    case values do
      [] -> %{status: :unavailable, delta: nil}
      [_single] -> %{status: :unavailable, delta: nil}
      _ -> %{status: :measured, delta: List.last(values) - List.first(values)}
    end
  end

  defp values(samples, path) do
    samples
    |> Enum.map(&get_in(&1, path))
    |> Enum.filter(&is_number/1)
  end
end
