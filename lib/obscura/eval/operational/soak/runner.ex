defmodule Obscura.Eval.Operational.Soak.Runner do
  @moduledoc """
  Orchestrates one prepared-runtime, mixed-dataset operational soak.
  """

  alias Obscura.Eval.Operational.AssetEvidence
  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Eval.Operational.Metadata
  alias Obscura.Eval.Operational.ReportPrivacy
  alias Obscura.Eval.Operational.Resilience
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.Soak.LoadRunner
  alias Obscura.Eval.Operational.Soak.Report
  alias Obscura.Eval.Operational.Soak.Schema
  alias Obscura.Eval.Operational.StageTracker
  alias Obscura.Profile

  @spec run(Profile.name(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(profile, opts) do
    Common.with_datasets_and_tracker(Dataset.names(), profile, fn datasets, tracker ->
      run_with_tracker(profile, datasets, tracker, opts)
    end)
  end

  defp run_with_tracker(profile, datasets, tracker, opts) do
    with {:ok, runtime, preparation_ms} <- Common.prepare_runtime(profile, tracker, opts),
         {:ok, supervisor, host} <- start_runtime(runtime, Keyword.fetch!(opts, :concurrency)) do
      try do
        execute(profile, runtime, datasets, tracker, supervisor, host, preparation_ms, opts)
      after
        if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
      end
    end
  end

  defp execute(profile, runtime, datasets, tracker, supervisor, host, preparation_ms, opts) do
    samples = Common.interleave_samples(datasets)

    load =
      LoadRunner.run(host, samples,
        duration_ms: Keyword.fetch!(opts, :duration_ms),
        concurrency: Keyword.fetch!(opts, :concurrency),
        timeout: Common.request_timeout(profile, opts),
        gpu: Common.gpu?(profile),
        sample_interval: Keyword.get(opts, :sample_interval, 1_000),
        window_ms: Keyword.get(opts, :window_ms, 60_000),
        idle_ms: Keyword.get(opts, :idle_ms, 10_000),
        gc_settle_ms: Keyword.get(opts, :gc_settle_ms, 1_000)
      )

    resilience = Resilience.run(runtime, supervisor, Common.replacement_host(supervisor), samples)
    stages = StageTracker.snapshot(tracker)

    report =
      build_report(
        profile,
        runtime,
        datasets,
        load,
        resilience,
        stages,
        preparation_ms,
        opts
      )

    with :ok <- validate_generated(report, opts),
         {:ok, paths} <-
           Report.write(report, Keyword.get(opts, :output_root, "eval/reports/operational/soak")) do
      {:ok, %{report: report, paths: paths}}
    end
  end

  defp start_runtime(runtime, concurrency) do
    child_opts = [
      runtime: runtime,
      max_in_flight: concurrency,
      id: :operational_soak_runtime_host
    ]

    case Supervisor.start_link([{RuntimeHost, child_opts}], strategy: :one_for_one) do
      {:ok, supervisor} ->
        {:ok, supervisor, Common.replacement_host(supervisor)}

      {:error, reason} ->
        {:error, {:soak_supervisor_start_failed, Common.safe_reason(reason)}}
    end
  end

  defp build_report(profile, runtime, datasets, load, resilience, stages, preparation_ms, opts) do
    %{
      schema_version: Schema.version(),
      status: if(Keyword.get(opts, :authoritative, false), do: :complete, else: :exploratory),
      generated_at: DateTime.utc_now(),
      profile: profile,
      resolved_profile: runtime.implementation_profile,
      datasets: Enum.map(datasets, &Common.dataset_metadata/1),
      workload: Map.drop(load, [:memory_analysis, :memory_classification, :post_soak]),
      memory_analysis: load.memory_analysis,
      memory_classification: load.memory_classification,
      post_soak: load.post_soak,
      resilience: resilience,
      runtime_reuse: runtime_reuse(stages),
      preparation: %{
        in_process_runtime_preparation_ms: preparation_ms,
        stages: stages.events
      },
      environment: Common.environment(profile, runtime.backend_metadata),
      hardware: Metadata.hardware(),
      runtime: Metadata.runtime(),
      asset_evidence: asset_evidence(profile, datasets),
      source: Metadata.git(),
      limitations: [
        :emily_allocator_statistics_are_not_physical_gpu_residency,
        :sampling_is_periodic_not_kernel_high_water,
        :linux_exla_not_measured_on_apple_runner,
        :classification_is_bounded_to_this_duration_and_workload
      ],
      settings: %{
        duration_ms: Keyword.fetch!(opts, :duration_ms),
        concurrency: Keyword.fetch!(opts, :concurrency),
        request_timeout_ms: Common.request_timeout(profile, opts),
        sample_interval_ms: Keyword.get(opts, :sample_interval, 1_000),
        window_ms: Keyword.get(opts, :window_ms, 60_000),
        idle_ms: Keyword.get(opts, :idle_ms, 10_000),
        authoritative: Keyword.get(opts, :authoritative, false),
        model_downloads_allowed: false
      }
    }
  end

  defp asset_evidence(profile, datasets) do
    Map.new(datasets, fn dataset ->
      {:ok, evidence} = AssetEvidence.for_profile_dataset(profile, dataset.selection)
      {dataset.name, ReportPrivacy.drop_keys(evidence, ["checkpoint", "path"])}
    end)
  end

  defp runtime_reuse(stages) do
    per_request_rebuild =
      Enum.any?(stages.counts, fn {stage, count} ->
        stage in lifecycle_stages() and count > 1
      end)

    %{
      normal_runtime_builds: 1,
      per_request_rebuild_detected: per_request_rebuild,
      lifecycle_stage_counts: stages.counts
    }
  end

  defp lifecycle_stages do
    [
      :model_registry,
      :backend_configuration,
      :dependency_validation,
      :compiler_start,
      :model_load,
      :tokenizer_load,
      :checkpoint_layout,
      :checkpoint_validation,
      :config_load,
      :label_info_load,
      :weights_load,
      :dtypes_load,
      :parameter_load,
      :serving_construction
    ]
  end

  defp validate_generated(report, opts) do
    if Keyword.get(opts, :authoritative, false) do
      report
      |> Jason.encode!()
      |> Jason.decode!()
      |> Schema.validate()
    else
      :ok
    end
  end
end
