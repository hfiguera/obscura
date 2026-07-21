defmodule Obscura.Eval.Operational.Report do
  @moduledoc false

  @spec write(map(), Path.t()) :: {:ok, %{json: Path.t(), markdown: Path.t()}} | {:error, term()}
  def write(report, output_root) do
    profile = to_string(report.profile)
    dataset = to_string(report.dataset.id)
    base = Path.join(output_root, "#{profile}-#{dataset}")
    json_path = base <> ".json"
    markdown_path = base <> ".md"

    File.mkdir_p!(output_root)

    with :ok <- File.write(json_path, Jason.encode!(report, pretty: true) <> "\n"),
         :ok <- File.write(markdown_path, markdown(report)) do
      {:ok, %{json: json_path, markdown: markdown_path}}
    end
  end

  defp markdown(report) do
    rows =
      Enum.map_join(report.warm_load.concurrency_results, "\n", fn row ->
        "| #{row.concurrency} | #{format(row.throughput_rps.mean)} | " <>
          "#{format(row.latency_ms.p50)} | #{format(row.latency_ms.p95)} | " <>
          "#{format(row.latency_ms.p99)} | #{row.completed} | #{row.failed} | " <>
          "#{row.rejected} | #{row.timed_out} |"
      end)

    """
    # Operational Benchmark: #{report.profile} / #{report.dataset.id}

    Status: `#{report.status}`

    Dataset SHA-256: `#{report.dataset.sha256}`
    Selection SHA-256: `#{report.dataset.selection_sha256}`
    Samples: `#{report.dataset.sample_count}`
    Source commit: `#{report.source.source_commit}`

    ## Cold Lifecycle

    - Fresh OS process: `#{report.cold_lifecycle.fresh_os_process}`
    - Application start: `#{format(report.cold_lifecycle.application_start_ms)} ms`
    - Runtime preparation: `#{format(report.cold_lifecycle.runtime_preparation_ms)} ms`
    - Compile-inclusive first inference: `#{format(report.cold_lifecycle.first_inference_ms)} ms`
    - Total process ready: `#{format(report.cold_lifecycle.total_ready_ms)} ms`
    - Empty-cache/network timing: unavailable; assets were pre-provisioned and offline loading was enforced.

    Nx does not expose lazy compilation as an independent public timing. First
    inference is therefore explicitly compile-inclusive.

    ## Warm Load

    | Concurrency | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed | Failed | Rejected | Timed out |
    | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    #{rows}

    Queue time is unavailable because the inline Nx serving path does not expose
    it independently. Service and end-to-end latency are recorded separately in
    the JSON artifact.

    ## Sustained Load

    - Requested duration: `#{report.sustained_load.requested_duration_ms} ms`
    - Measured duration: `#{report.sustained_load.elapsed_ms} ms`
    - Throughput: `#{format(report.sustained_load.throughput_rps)} req/s`
    - Latency drift ratio: `#{format(report.sustained_load.latency_drift_ratio)}`
    - RSS growth: `#{report.sustained_load.memory_growth_bytes || "unavailable"} bytes`
    - Failures: `#{report.sustained_load.failed}`

    ## Resilience And Reuse

    - Timeout behavior: `#{report.resilience.timeout.status}`
    - Bounded overload: `#{report.resilience.overload.status}`
    - Supervised crash recovery: `#{report.resilience.serving_crash_recovery.status}`
    - Privacy check: `#{report.resilience.privacy_check.status}`
    - Normal runtime builds: `#{report.runtime_reuse.normal_runtime_builds}`
    - Per-request rebuild detected: `#{report.runtime_reuse.per_request_rebuild_detected}`

    ## Environment

    - Platform: `#{report.environment.platform}`
    - Requested backend: `#{report.environment.requested_backend}`
    - Requested device: `#{report.environment.requested_device}`
    - Fallback policy: `#{report.environment.emily_fallback}`
    - Backend proven: `#{report.environment.backend_proven}`
    - Fallback occurred: `#{report.environment.fallback_occurred}`
    - Linux/EXLA: `#{get_in(report.environment, [:linux_exla, :status])}`
    #{openmed_policy_markdown(report)}

    No raw input, detected value, model asset, cache content, or absolute local
    path is included in this report.
    """
  end

  defp format(nil), do: "unavailable"
  defp format(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp format(value), do: to_string(value)

  defp openmed_policy_markdown(%{profile: :openmed_pii} = report) do
    policy = get_in(report, [:environment, :actual, :openmed_optimization])

    """
    - OpenMed optimization policy: `#{policy.id}`
    - Sequence-length buckets: `#{inspect(policy.sequence_length_buckets)}`
    - Sequence-length bucket threshold: `#{policy.sequence_length_bucket_threshold}`
    - Log-prob conversion: `#{policy.logprob_conversion}`
    - Policy matches default: `#{policy.matches_default}`
    """
  end

  defp openmed_policy_markdown(_report), do: ""
end
