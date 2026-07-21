defmodule Obscura.Eval.Operational.Schema do
  @moduledoc """
  Validation for report-safe operational benchmark artifacts.
  """

  @schema_version 1
  @concurrencies [1, 2, 4, 8, 16]
  @sensitive_keys ~w(text value raw raw_text source_text prompt content token)

  alias Obscura.Eval.Operational.ReportPrivacy
  alias Obscura.PrivacyFilter.OpenMedPolicy

  @spec version() :: pos_integer()
  def version, do: @schema_version

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(report) when is_map(report) do
    with {:ok, fields} <- validate_shape(report),
         :ok <- validate_concurrencies(fields.warm),
         :ok <- validate_repetitions(fields.warm),
         :ok <- validate_dataset(fields.dataset),
         :ok <- validate_asset_evidence(fields.profile, fields.asset_evidence),
         :ok <- validate_backend(fields.profile, fields.environment),
         :ok <- validate_openmed_policy(fields.profile, fields.environment),
         :ok <- validate_reuse(fields.reuse),
         :ok <- validate_no_sensitive_values(report) do
      validate_completion(fields.cold, fields.sustained, fields.resilience)
    end
  end

  def validate(_report), do: {:error, :invalid_operational_report_schema}

  defp validate_shape(%{
         "schema_version" => @schema_version,
         "status" => "complete",
         "profile" => profile,
         "dataset" => dataset,
         "cold_lifecycle" => cold,
         "warm_load" => warm,
         "sustained_load" => sustained,
         "resilience" => resilience,
         "runtime_reuse" => reuse,
         "resources" => resources,
         "asset_evidence" => asset_evidence,
         "environment" => environment,
         "source" => source
       })
       when profile in ~w(fast balanced accurate openmed_pii) do
    fields = [
      dataset,
      cold,
      warm,
      sustained,
      resilience,
      reuse,
      resources,
      asset_evidence,
      environment,
      source
    ]

    if Enum.all?(fields, &is_map/1) do
      {:ok,
       %{
         profile: profile,
         dataset: dataset,
         cold: cold,
         warm: warm,
         sustained: sustained,
         resilience: resilience,
         reuse: reuse,
         asset_evidence: asset_evidence,
         environment: environment
       }}
    else
      {:error, :invalid_operational_report_schema}
    end
  end

  defp validate_shape(_report), do: {:error, :invalid_operational_report_schema}

  @spec validate_no_sensitive_values(term()) :: :ok | {:error, term()}
  def validate_no_sensitive_values(term) do
    case ReportPrivacy.find_sensitive_key(term, @sensitive_keys) do
      nil -> :ok
      key -> {:error, {:sensitive_operational_report_key, key}}
    end
  end

  defp validate_concurrencies(%{"concurrency_results" => rows}) when is_list(rows) do
    actual = rows |> Enum.map(& &1["concurrency"]) |> Enum.sort()
    if actual == @concurrencies, do: :ok, else: {:error, :incomplete_concurrency_matrix}
  end

  defp validate_concurrencies(_warm), do: {:error, :incomplete_concurrency_matrix}

  defp validate_repetitions(%{"concurrency_results" => rows}) do
    if Enum.all?(rows, fn row ->
         row["repetition_count"] >= 2 and row["stable_output"] == true and
           row["failed"] == 0 and row["timed_out"] == 0
       end),
       do: :ok,
       else: {:error, :unstable_or_incomplete_warm_measurements}
  end

  defp validate_dataset(%{
         "sample_count" => count,
         "sha256" => dataset_hash,
         "sample_ids_sha256" => ids_hash,
         "selection_sha256" => selection_hash
       })
       when count > 0 do
    if Enum.all?([dataset_hash, ids_hash, selection_hash], &sha256?/1),
      do: :ok,
      else: {:error, :incomplete_operational_dataset_fingerprints}
  end

  defp validate_dataset(_dataset), do: {:error, :incomplete_operational_dataset_fingerprints}

  defp validate_asset_evidence("fast", %{
         "source_manifest_sha256" => hash,
         "models" => models,
         "asset_hashes" => asset_hashes
       })
       when is_map(models) and asset_hashes == %{} do
    if sha256?(hash), do: :ok, else: {:error, :incomplete_operational_asset_evidence}
  end

  defp validate_asset_evidence(_profile, %{
         "source_manifest_sha256" => hash,
         "models" => models,
         "asset_hashes" => asset_hashes
       })
       when is_map(models) and map_size(models) > 0 and is_map(asset_hashes) and
              map_size(asset_hashes) > 0 do
    if sha256?(hash), do: :ok, else: {:error, :incomplete_operational_asset_evidence}
  end

  defp validate_asset_evidence(_profile, _evidence),
    do: {:error, :incomplete_operational_asset_evidence}

  defp validate_backend("fast", %{"requested_backend" => "beam_cpu"}), do: :ok

  defp validate_backend(_profile, %{
         "requested_backend" => "emily",
         "requested_device" => "gpu",
         "emily_fallback" => "raise",
         "fallback_occurred" => false,
         "backend_proven" => true
       }),
       do: :ok

  defp validate_backend(_profile, %{
         "requested_backend" => "exla",
         "fallback_occurred" => false,
         "backend_proven" => true
       }),
       do: :ok

  defp validate_backend(_profile, _environment), do: {:error, :accelerator_not_proven}

  defp validate_openmed_policy(
         "openmed_pii",
         %{"actual" => %{"openmed_optimization" => policy}}
       ) do
    expected =
      OpenMedPolicy.default_metadata()
      |> Jason.encode!()
      |> Jason.decode!()

    if policy == expected,
      do: :ok,
      else: {:error, :openmed_optimization_policy_drift}
  end

  defp validate_openmed_policy("openmed_pii", _environment),
    do: {:error, :missing_openmed_optimization_policy}

  defp validate_openmed_policy(_profile, _environment), do: :ok

  defp validate_reuse(%{
         "normal_runtime_builds" => 1,
         "per_request_rebuild_detected" => false,
         "anti_pattern" => %{"status" => "measured"}
       }),
       do: :ok

  defp validate_reuse(_reuse), do: {:error, :runtime_reuse_not_proven}

  defp validate_completion(
         %{
           "status" => "measured",
           "fresh_os_process" => true,
           "assets_preprovisioned" => true,
           "network_downloads_allowed" => false
         },
         %{
           "status" => "measured",
           "stop_reason" => "duration",
           "elapsed_ms" => elapsed,
           "requested_duration_ms" => requested
         },
         %{
           "timeout" => %{"status" => "passed"},
           "overload" => %{"status" => "passed"},
           "serving_crash_recovery" => %{"status" => "passed"},
           "privacy_check" => %{"status" => "passed"}
         }
       )
       when elapsed >= requested,
       do: :ok

  defp validate_completion(_cold, _sustained, _resilience),
    do: {:error, :incomplete_operational_probes}

  defp sha256?(value), do: is_binary(value) and byte_size(value) == 64
end
