defmodule Obscura.Eval.Operational.Soak.Schema do
  @moduledoc """
  Promotion validation for privacy-safe long-duration soak evidence.
  """

  @schema_version 1
  @dataset_ids ~w(generated_large_template_heldout synth_dataset_v2_all nemotron_pii_test_subset_all)
  @classifications ~w(stable_plateau allocator_caching inconclusive probable_leak)
  @sensitive_keys ~w(text value raw raw_text source_text prompt content token checkpoint path)

  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.ReportPrivacy

  @spec version() :: pos_integer()
  def version, do: @schema_version

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(report) when is_map(report) do
    with {:ok, fields} <- shape(report),
         :ok <- validate_canonical_run(fields.profile, fields.workload),
         :ok <- validate_datasets(fields.datasets, fields.workload),
         :ok <- validate_backend(fields.profile, fields.environment),
         :ok <- validate_workload(fields.workload),
         :ok <-
           validate_memory(
             fields.profile,
             fields.memory,
             fields.classification,
             fields.post_soak
           ),
         :ok <-
           Common.validate_resilience(
             fields.resilience,
             :incomplete_soak_resilience
           ),
         :ok <- validate_reuse(fields.reuse),
         :ok <- validate_asset_evidence(fields.assets) do
      validate_no_sensitive_values(report)
    end
  end

  def validate(_report), do: {:error, :invalid_soak_report_schema}

  @spec validate_no_sensitive_values(term()) :: :ok | {:error, term()}
  def validate_no_sensitive_values(term) do
    case ReportPrivacy.find_sensitive_key(term, @sensitive_keys) do
      nil -> :ok
      key -> {:error, {:sensitive_soak_report_key, key}}
    end
  end

  defp shape(%{
         "schema_version" => @schema_version,
         "status" => "complete",
         "profile" => profile,
         "datasets" => datasets,
         "workload" => workload,
         "memory_analysis" => memory,
         "memory_classification" => classification,
         "post_soak" => post_soak,
         "resilience" => resilience,
         "runtime_reuse" => reuse,
         "environment" => environment,
         "asset_evidence" => assets,
         "source" => %{"dirty_worktree" => false}
       })
       when profile in ~w(fast balanced openmed_pii) do
    {:ok,
     %{
       profile: profile,
       datasets: datasets,
       workload: workload,
       memory: memory,
       classification: classification,
       post_soak: post_soak,
       resilience: resilience,
       reuse: reuse,
       environment: environment,
       assets: assets
     }}
  end

  defp shape(_report), do: {:error, :invalid_soak_report_schema}

  defp validate_canonical_run("openmed_pii", %{
         "concurrency" => 4,
         "requested_duration_ms" => duration
       })
       when duration >= 1_800_000,
       do: :ok

  defp validate_canonical_run("openmed_pii", %{
         "concurrency" => 1,
         "requested_duration_ms" => duration
       })
       when duration >= 600_000,
       do: :ok

  defp validate_canonical_run(profile, %{
         "concurrency" => 4,
         "requested_duration_ms" => duration
       })
       when profile in ~w(fast balanced) and duration >= 600_000,
       do: :ok

  defp validate_canonical_run(_profile, _workload), do: {:error, :noncanonical_soak_run}

  defp validate_datasets(datasets, %{"dataset_coverage" => coverage})
       when is_list(datasets) and is_map(coverage) do
    ids = datasets |> Enum.map(& &1["id"]) |> Enum.sort()

    complete_metadata =
      Enum.all?(datasets, fn dataset ->
        dataset["sample_count"] > 0 and
          Enum.all?(
            ~w(sha256 sample_ids_sha256 selection_sha256 entity_policy_sha256 scoring_sha256),
            &sha256?(dataset[&1])
          )
      end)

    covered =
      Enum.all?(@dataset_ids, fn id ->
        match?(
          %{"configured_samples" => configured, "requests" => requests}
          when configured > 0 and requests > 0,
          coverage[id]
        )
      end)

    if ids == Enum.sort(@dataset_ids) and complete_metadata and covered,
      do: :ok,
      else: {:error, :incomplete_soak_dataset_evidence}
  end

  defp validate_datasets(_datasets, _workload), do: {:error, :incomplete_soak_dataset_evidence}

  defp validate_backend("fast", %{
         "requested_backend" => "beam_cpu",
         "backend_proven" => true,
         "fallback_occurred" => false
       }),
       do: :ok

  defp validate_backend(_profile, %{
         "requested_backend" => "emily",
         "requested_device" => "gpu",
         "emily_fallback" => "raise",
         "backend_proven" => true,
         "fallback_occurred" => false
       }),
       do: :ok

  defp validate_backend(_profile, %{
         "requested_backend" => "exla",
         "requested_device" => requested_device,
         "backend_proven" => true,
         "fallback_occurred" => false
       })
       when not is_nil(requested_device),
       do: :ok

  defp validate_backend(_profile, _environment), do: {:error, :soak_accelerator_not_proven}

  defp validate_workload(%{
         "stop_reason" => "duration",
         "elapsed_ms" => elapsed,
         "requested_duration_ms" => requested,
         "sample_interval_ms" => sample_interval,
         "worker_count" => workers,
         "completed" => completed,
         "failed" => 0,
         "rejected" => 0,
         "timed_out" => 0,
         "resource_sample_count" => sample_count,
         "resource_sampling_coverage" => coverage,
         "windows" => windows,
         "output_stability" => %{
           "stable" => true,
           "mismatches" => 0,
           "probe" => %{"stable" => true}
         }
       })
       when elapsed >= requested and workers > 0 and completed > 0 and sample_count > 0 and
              coverage >= 0.95 and sample_interval in 1..1_000 and is_list(windows) and
              windows != [],
       do: :ok

  defp validate_workload(_workload), do: {:error, :incomplete_or_unstable_soak_workload}

  defp validate_memory(
         profile,
         %{
           "sample_count" => count,
           "request_correlations" => correlations,
           "metrics" => %{
             "beam_total" => beam,
             "os_rss" => rss,
             "emily_active" => emily_active,
             "emily_cache" => emily_cache,
             "in_flight" => in_flight,
             "mailbox_length" => mailbox
           }
         },
         %{"classification" => classification, "reasons" => reasons},
         %{
           "before_idle" => before_idle,
           "after_idle" => after_idle,
           "after_gc" => after_gc,
           "after_cache_clear" => after_cache_clear
         }
       ) do
    metrics =
      if profile == "fast",
        do: [beam, rss, in_flight, mailbox],
        else: [beam, rss, emily_active, emily_cache, in_flight, mailbox]

    if complete_memory_header?(count, classification, reasons) and
         complete_post_soak?([before_idle, after_idle, after_gc, after_cache_clear]) and
         Enum.all?(metrics, &complete_metric?/1) and complete_correlations?(correlations),
       do: :ok,
       else: {:error, :incomplete_soak_memory_analysis}
  end

  defp validate_memory(_profile, _memory, _classification, _post_soak),
    do: {:error, :incomplete_soak_memory_analysis}

  defp validate_reuse(%{
         "normal_runtime_builds" => 1,
         "per_request_rebuild_detected" => false,
         "lifecycle_stage_counts" => counts
       })
       when is_map(counts),
       do: :ok

  defp validate_reuse(_reuse), do: {:error, :soak_runtime_reuse_not_proven}

  defp validate_asset_evidence(assets) when is_map(assets) and map_size(assets) == 3 do
    if Enum.all?(assets, fn {_dataset, evidence} ->
         sha256?(evidence["source_manifest_sha256"]) and is_map(evidence["models"]) and
           is_map(evidence["asset_hashes"])
       end),
       do: :ok,
       else: {:error, :incomplete_soak_asset_evidence}
  end

  defp validate_asset_evidence(_assets), do: {:error, :incomplete_soak_asset_evidence}

  defp complete_metric?(%{
         "status" => "measured",
         "baseline" => baseline,
         "final" => final,
         "absolute_growth" => growth,
         "full_regression" => %{"status" => "measured"},
         "final_half_regression" => %{"status" => "measured"},
         "rolling_median" => %{"count" => count}
       })
       when is_number(baseline) and is_number(final) and is_number(growth) and count > 0,
       do: true

  defp complete_metric?(_metric), do: false

  defp complete_correlations?(correlations) when is_map(correlations) do
    Enum.all?(~w(beam_total os_rss emily_active emily_cache), fn key ->
      case correlations[key] do
        %{"status" => status} when status in ~w(measured unavailable) -> true
        _other -> false
      end
    end)
  end

  defp complete_correlations?(_correlations), do: false

  defp complete_memory_header?(count, classification, reasons) do
    count >= 2 and classification in @classifications and is_list(reasons)
  end

  defp complete_post_soak?(observations),
    do: Enum.all?(observations, &(is_map(&1) and map_size(&1) > 0))

  defp sha256?(value), do: is_binary(value) and byte_size(value) == 64
end
