defmodule Obscura.Eval.Operational.Soak.Report do
  @moduledoc false

  @spec write(map(), Path.t()) :: {:ok, %{json: Path.t(), markdown: Path.t()}} | {:error, term()}
  def write(report, output_root) do
    duration = report.workload.requested_duration_ms
    base = Path.join(output_root, "#{report.profile}-c#{report.workload.concurrency}-#{duration}")
    json_path = base <> ".json"
    markdown_path = base <> ".md"
    File.mkdir_p!(output_root)

    with :ok <- File.write(json_path, Jason.encode!(report, pretty: true) <> "\n"),
         :ok <- File.write(markdown_path, markdown(report)) do
      {:ok, %{json: json_path, markdown: markdown_path}}
    end
  end

  defp markdown(report) do
    windows =
      Enum.map_join(report.workload.windows, "\n", fn window ->
        "| #{window.index} | #{format(window.throughput_rps)} | " <>
          "#{format(window.latency_ms.p50)} | #{format(window.latency_ms.p95)} | " <>
          "#{format(window.latency_ms.p99)} | #{window.completed} |"
      end)

    memory =
      report.memory_analysis.metrics
      |> Enum.map_join("\n", fn {metric, row} ->
        "| #{metric} | #{row.status} | #{format(Map.get(row, :baseline))} | " <>
          "#{format(Map.get(row, :final))} | #{format(Map.get(row, :absolute_growth))} | " <>
          "#{format(get_in(row, [:final_half_regression, :slope_bytes_per_minute]))} | " <>
          "#{Map.get(row, :trend, :unavailable)} |"
      end)

    correlations =
      report.memory_analysis.request_correlations
      |> Enum.map_join("\n", fn {metric, row} ->
        "| #{metric} | #{row.status} | #{format(Map.get(row, :coefficient))} | " <>
          "#{format(Map.get(row, :sample_count))} |"
      end)

    """
    # Operational Soak: #{report.profile}

    Status: `#{report.status}`
    Source commit: `#{report.source.source_commit}`
    Classification: `#{report.memory_classification.classification}`

    ## Workload

    - Requested duration: `#{report.workload.requested_duration_ms} ms`
    - Measured duration: `#{format(report.workload.elapsed_ms)} ms`
    - Concurrency: `#{report.workload.concurrency}`
    - Completed: `#{report.workload.completed}`
    - Failed / rejected / timed out: `#{report.workload.failed} / #{report.workload.rejected} / #{report.workload.timed_out}`
    - Throughput: `#{format(report.workload.throughput_rps)} req/s`
    - Resource samples: `#{report.workload.resource_sample_count}`
    - Sampling coverage: `#{format(report.workload.resource_sampling_coverage)}`
    - Stable output: `#{report.workload.output_stability.stable}`

    ## Time Windows

    | Window | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed |
    | ---: | ---: | ---: | ---: | ---: | ---: |
    #{windows}

    ## Memory Analysis

    | Metric | Status | Baseline | Final | Growth | Final slope bytes/min | Trend |
    | --- | --- | ---: | ---: | ---: | ---: | --- |
    #{memory}

    Classification reasons: `#{Enum.join(report.memory_classification.reasons, ", ")}`

    Emily values are direct allocator statistics, not inferred physical GPU
    residency.

    ## Request Correlation

    | Metric | Status | Pearson coefficient | Samples |
    | --- | --- | ---: | ---: |
    #{correlations}

    ## Post-Soak Diagnostics

    - Idle duration: `#{report.post_soak.idle_duration_ms} ms`
    - Cache clear: `#{report.post_soak.cache_clear.status}`
    - Timeout probe: `#{report.resilience.timeout.status}`
    - Overload probe: `#{report.resilience.overload.status}`
    - Gateway recovery: `#{report.resilience.serving_crash_recovery.status}`
    - Runtime builds: `#{report.runtime_reuse.normal_runtime_builds}`
    - Per-request rebuild: `#{report.runtime_reuse.per_request_rebuild_detected}`

    No raw input, detected value, checkpoint path, cache content, model asset,
    credential, or absolute local path is included.
    """
  end

  defp format(nil), do: "unavailable"
  defp format(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format(value), do: to_string(value)
end
