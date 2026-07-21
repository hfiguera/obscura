defmodule Obscura.Eval.Operational.Diagnostic.Report do
  @moduledoc false

  @spec write(map(), Path.t()) :: {:ok, %{json: Path.t(), markdown: Path.t()}} | {:error, term()}
  def write(report, output_root) do
    base =
      Path.join(
        output_root,
        "#{report.profile}-#{report.experiment.id}-c#{report.workload.concurrency}-#{report.workload.requested_duration_ms}"
      )

    json_path = base <> ".json"
    markdown_path = base <> ".md"
    File.mkdir_p!(output_root)

    with :ok <- File.write(json_path, Jason.encode!(report, pretty: true) <> "\n"),
         :ok <- File.write(markdown_path, markdown(report)) do
      {:ok, %{json: json_path, markdown: markdown_path}}
    end
  end

  defp markdown(report) do
    timeline =
      Enum.map_join(report.diagnostic_analysis.timeline, "\n", fn row ->
        model = get_in(row, [:stages, :model_serving, :p95])
        queue = get_in(row, [:stages, :queue_admission, :p95])
        cpu = get_in(row, [:resources, :process_cpu_percent, :mean])

        "| #{row.index} | #{format(row.throughput_rps)} | #{format(row.latency_ms.p95)} | " <>
          "#{format(queue)} | #{format(model)} | #{format(cpu)} |"
      end)

    stages =
      report.stage_diagnostics
      |> Map.get(:stages, %{})
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("\n", fn {stage, row} ->
        share = get_in(report, [:diagnostic_analysis, :stage_share_percent, stage])

        "| #{stage} | #{row.count} | #{format(row.mean)} | #{format(row.p95)} | " <>
          "#{format(row.p99)} | #{format(share)} |"
      end)

    """
    # Sustained Latency Diagnostic: #{report.profile}

    Status: `#{report.status}`
    Experiment: `#{report.experiment.id}`
    Source commit: `#{report.source.source_commit}`
    Diagnostics enabled: `#{report.experiment.diagnostics_enabled}`

    ## Workload

    - Duration: `#{report.workload.requested_duration_ms} ms`
    - Concurrency: `#{report.workload.concurrency}`
    - Completed: `#{report.workload.completed}`
    - Failed / rejected / timed out: `#{report.workload.failed} / #{report.workload.rejected} / #{report.workload.timed_out}`
    - Throughput: `#{format(report.workload.throughput_rps)} req/s`
    - Stable output: `#{report.workload.output_stability.stable}`
    - Instrumentation throughput delta: `#{format(Map.get(report.instrumentation_overhead, :throughput_delta_ratio))}`
    - Instrumentation p95 delta: `#{format(Map.get(report.instrumentation_overhead, :p95_latency_delta_ratio))}`

    ## Timeline

    | Window | Throughput req/s | Request p95 ms | Queue p95 ms | Model p95 ms | BEAM CPU % |
    | ---: | ---: | ---: | ---: | ---: | ---: |
    #{timeline}

    ## Stage Distributions

    | Stage | Count | Mean ms | p95 ms | p99 ms | Mean share % |
    | --- | ---: | ---: | ---: | ---: | ---: |
    #{stages}

    Earliest degrading stage:
    `#{inspect(report.diagnostic_analysis.earliest_degrading_stage)}`

    Attention and MoE are fused into the compiled Emily device graph. They are
    not assigned invented host timings. GPU utilization, frequency, and power
    require privileged `powermetrics` on this host and are reported as
    unavailable.

    No raw input, token ID, decoded value, span text, checkpoint path,
    credential, or absolute local path is included.
    """
  end

  defp format(nil), do: "unavailable"
  defp format(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format(value), do: to_string(value)
end
