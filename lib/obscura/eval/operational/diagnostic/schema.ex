defmodule Obscura.Eval.Operational.Diagnostic.Schema do
  @moduledoc """
  Validation for promotable sustained-latency diagnostic evidence.
  """

  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.ReportPrivacy

  @schema_version 1
  @dataset_ids ~w(generated_large_template_heldout synth_dataset_v2_all nemotron_pii_test_subset_all)
  @sensitive_keys ~w(text value raw raw_text source_text prompt content token checkpoint path)
  @required_stages ~w(queue_admission service_total recognizer_execution model_serving conflict_resolution final_assembly)

  @spec version() :: pos_integer()
  def version, do: @schema_version

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(report) when is_map(report) do
    with {:ok, fields} <- shape(report),
         :ok <- validate_canonical(fields.profile, fields.workload),
         :ok <- validate_backend(fields.environment),
         :ok <- validate_datasets(fields.datasets, fields.workload),
         :ok <- validate_workload(fields.workload),
         :ok <- validate_diagnostics(fields.diagnostics, fields.analysis),
         :ok <- validate_overhead(fields.overhead),
         :ok <- validate_resources(fields.resource_series, fields.workload),
         :ok <-
           Common.validate_resilience(
             fields.resilience,
             :incomplete_diagnostic_resilience
           ),
         :ok <- validate_reuse(fields.reuse),
         :ok <- validate_assets(fields.assets) do
      validate_privacy(report)
    end
  end

  def validate(_report), do: {:error, :invalid_diagnostic_report_schema}

  @spec validate_privacy(term()) :: :ok | {:error, term()}
  def validate_privacy(term) do
    encoded = Jason.encode!(term)
    normalized = Jason.decode!(encoded)

    case ReportPrivacy.find_sensitive_key(normalized, @sensitive_keys) do
      nil ->
        if Regex.match?(~r/(?:\/Users\/|\/home\/|[A-Za-z]:\\\\)/, encoded),
          do: {:error, :diagnostic_report_contains_absolute_path},
          else: :ok

      key ->
        {:error, {:sensitive_diagnostic_report_key, key}}
    end
  end

  defp shape(%{
         "schema_version" => @schema_version,
         "status" => "complete",
         "profile" => profile,
         "experiment" => %{
           "kind" => "instrumented",
           "diagnostics_enabled" => true,
           "sample_mode" => "mixed",
           "behavior_changes_allowed" => false
         },
         "datasets" => datasets,
         "workload" => workload,
         "stage_diagnostics" => diagnostics,
         "diagnostic_analysis" => analysis,
         "instrumentation_overhead" => overhead,
         "resource_series" => resource_series,
         "resilience" => resilience,
         "runtime_reuse" => reuse,
         "environment" => environment,
         "asset_evidence" => assets,
         "source" => %{"dirty_worktree" => false}
       })
       when profile in ~w(balanced openmed_pii) do
    {:ok,
     %{
       profile: profile,
       datasets: datasets,
       workload: workload,
       diagnostics: diagnostics,
       analysis: analysis,
       overhead: overhead,
       resource_series: resource_series,
       resilience: resilience,
       reuse: reuse,
       environment: environment,
       assets: assets
     }}
  end

  defp shape(_report), do: {:error, :invalid_diagnostic_report_schema}

  defp validate_canonical("balanced", %{
         "concurrency" => 4,
         "requested_duration_ms" => duration
       })
       when duration >= 600_000,
       do: :ok

  defp validate_canonical("openmed_pii", %{
         "concurrency" => 4,
         "requested_duration_ms" => duration
       })
       when duration >= 1_800_000,
       do: :ok

  defp validate_canonical(_profile, _workload), do: {:error, :noncanonical_diagnostic_run}

  defp validate_backend(%{
         "requested_backend" => "emily",
         "requested_device" => "gpu",
         "emily_fallback" => "raise",
         "backend_proven" => true,
         "fallback_occurred" => false
       }),
       do: :ok

  defp validate_backend(_environment), do: {:error, :diagnostic_gpu_backend_not_proven}

  defp validate_datasets(datasets, %{"dataset_coverage" => coverage})
       when is_list(datasets) and is_map(coverage) do
    ids = datasets |> Enum.map(& &1["id"]) |> Enum.sort()

    metadata_complete =
      Enum.all?(datasets, fn dataset ->
        dataset["sample_count"] > 0 and
          Enum.all?(
            ~w(sha256 sample_ids_sha256 selection_sha256 entity_policy_sha256 scoring_sha256),
            &sha256?(dataset[&1])
          )
      end)

    covered =
      Enum.all?(@dataset_ids, fn id ->
        match?(%{"requests" => requests} when requests > 0, coverage[id])
      end)

    if ids == Enum.sort(@dataset_ids) and metadata_complete and covered,
      do: :ok,
      else: {:error, :incomplete_diagnostic_dataset_evidence}
  end

  defp validate_datasets(_datasets, _workload),
    do: {:error, :incomplete_diagnostic_dataset_evidence}

  defp validate_workload(%{
         "stop_reason" => "duration",
         "elapsed_ms" => elapsed,
         "requested_duration_ms" => requested,
         "completed" => completed,
         "failed" => 0,
         "rejected" => 0,
         "timed_out" => 0,
         "resource_sampling_coverage" => coverage,
         "output_stability" => %{"stable" => true, "mismatches" => 0},
         "windows" => windows
       })
       when elapsed >= requested and completed > 0 and coverage >= 0.95 and is_list(windows) and
              windows != [],
       do: :ok

  defp validate_workload(_workload),
    do: {:error, :incomplete_or_unstable_diagnostic_workload}

  defp validate_diagnostics(
         %{
           "status" => "measured",
           "request_count" => count,
           "stages" => stages,
           "input" => input,
           "model_shapes" => shapes,
           "unavailable_stages" => unavailable
         },
         analysis
       )
       when count > 0 do
    checks = [
      required_stages?(stages),
      complete_input?(input),
      complete_shapes?(shapes),
      complete_unavailable?(unavailable),
      complete_analysis?(analysis)
    ]

    if Enum.all?(checks),
      do: :ok,
      else: {:error, :incomplete_stage_diagnostics}
  end

  defp validate_diagnostics(_diagnostics, _analysis),
    do: {:error, :incomplete_stage_diagnostics}

  defp required_stages?(stages) when is_map(stages),
    do: Enum.all?(@required_stages, &positive_summary?(stages[&1]))

  defp required_stages?(_stages), do: false

  defp complete_input?(input) when is_map(input) do
    Enum.all?(
      ~w(input_bytes token_count model_sequence_length),
      &positive_summary?(input[&1])
    )
  end

  defp complete_input?(_input), do: false

  defp complete_shapes?(%{
         "tracked_shape_count" => tracked,
         "first_seen_requests" => first_seen,
         "repeated_requests" => repeated,
         "first_seen_model_ms" => first_summary,
         "repeated_model_ms" => repeated_summary
       }) do
    Enum.all?([tracked, first_seen, repeated], &positive_number?/1) and
      positive_summary?(first_summary) and positive_summary?(repeated_summary)
  end

  defp complete_shapes?(_shapes), do: false

  defp complete_unavailable?(%{
         "privacy_filter_attention" => attention,
         "privacy_filter_moe" => moe
       }),
       do: is_binary(attention) and is_binary(moe)

  defp complete_unavailable?(_unavailable), do: false

  defp complete_analysis?(%{
         "timeline" => [_first | _rest],
         "correlations" => correlations,
         "first_middle_last" => %{"status" => "measured"},
         "observability" => observability,
         "hypotheses" => hypotheses
       }),
       do: is_map(correlations) and is_map(observability) and is_list(hypotheses)

  defp complete_analysis?(_analysis), do: false

  defp positive_summary?(%{"count" => count}), do: positive_number?(count)
  defp positive_summary?(_summary), do: false
  defp positive_number?(number), do: is_number(number) and number > 0

  defp validate_overhead(%{
         "status" => "measured",
         "same_source_commit" => true,
         "same_profile" => true,
         "same_concurrency" => true,
         "same_duration" => true,
         "same_sample_mode" => true,
         "output_probe_match" => true,
         "throughput_delta_ratio" => throughput,
         "p95_latency_delta_ratio" => p95
       })
       when is_number(throughput) and is_number(p95),
       do: :ok

  defp validate_overhead(_overhead), do: {:error, :invalid_instrumentation_overhead}

  defp validate_resources(series, %{"resource_sample_count" => expected})
       when is_list(series) and length(series) == expected and expected > 0 do
    if Enum.all?(series, &complete_resource?/1),
      do: :ok,
      else: {:error, :incomplete_diagnostic_resource_series}
  end

  defp validate_resources(_series, _workload),
    do: {:error, :incomplete_diagnostic_resource_series}

  defp complete_resource?(row) when is_map(row) do
    numeric = Enum.all?(~w(elapsed_ms scheduler_utilization run_queue), &is_number(row[&1]))
    maps = Enum.all?(~w(beam_memory gpu_memory host system), &is_map(row[&1]))
    numeric and maps
  end

  defp validate_reuse(%{
         "normal_runtime_builds" => 1,
         "per_request_rebuild_detected" => false,
         "lifecycle_stage_counts" => counts
       })
       when is_map(counts),
       do: :ok

  defp validate_reuse(_reuse), do: {:error, :diagnostic_runtime_reuse_not_proven}

  defp validate_assets(assets) when is_map(assets) and map_size(assets) == 3 do
    if Enum.all?(assets, fn {_dataset, evidence} ->
         sha256?(evidence["source_manifest_sha256"]) and is_map(evidence["models"]) and
           is_map(evidence["asset_hashes"])
       end),
       do: :ok,
       else: {:error, :incomplete_diagnostic_asset_evidence}
  end

  defp validate_assets(_assets), do: {:error, :incomplete_diagnostic_asset_evidence}
  defp sha256?(value), do: is_binary(value) and byte_size(value) == 64
end
