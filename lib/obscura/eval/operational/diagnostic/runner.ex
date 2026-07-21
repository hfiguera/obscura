defmodule Obscura.Eval.Operational.Diagnostic.Runner do
  @moduledoc """
  Runs a controlled, privacy-safe sustained-latency diagnostic.
  """

  alias Obscura.Eval.Operational.AssetEvidence
  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Eval.Operational.Diagnostic.Analysis
  alias Obscura.Eval.Operational.Diagnostic.Report
  alias Obscura.Eval.Operational.Diagnostic.Schema
  alias Obscura.Eval.Operational.Metadata
  alias Obscura.Eval.Operational.ReportPrivacy
  alias Obscura.Eval.Operational.Resilience
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.Soak.LoadRunner
  alias Obscura.Eval.Operational.StageTracker
  alias Obscura.Profile

  @spec run(Profile.name(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(profile, opts) when profile in [:balanced, :openmed_pii] do
    Common.with_datasets_and_tracker(Dataset.names(), profile, fn datasets, tracker ->
      run_with_tracker(profile, datasets, tracker, opts)
    end)
  end

  defp run_with_tracker(profile, datasets, tracker, opts) do
    with {:ok, runtime, preparation_ms} <- Common.prepare_runtime(profile, tracker, opts),
         {:ok, supervisor, host} <- start_runtime(runtime, opts) do
      try do
        execute(profile, runtime, datasets, tracker, supervisor, host, preparation_ms, opts)
      after
        if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
      end
    end
  end

  defp execute(profile, runtime, datasets, tracker, supervisor, host, preparation_ms, opts) do
    samples =
      datasets
      |> Common.interleave_samples()
      |> select_samples(Keyword.get(opts, :sample_mode, :mixed))

    diagnostics? = Keyword.get(opts, :diagnostics, true)

    load =
      LoadRunner.run(host, samples,
        duration_ms: Keyword.fetch!(opts, :duration_ms),
        concurrency: Keyword.fetch!(opts, :concurrency),
        timeout: Common.request_timeout(profile, opts),
        gpu: Common.gpu?(profile),
        diagnostics: diagnostics?,
        environmental: true,
        include_resource_series: true,
        sample_interval: Keyword.get(opts, :sample_interval, 1_000),
        window_ms: Keyword.get(opts, :window_ms, 60_000),
        idle_ms: Keyword.get(opts, :idle_ms, 10_000),
        gc_settle_ms: Keyword.get(opts, :gc_settle_ms, 1_000)
      )

    resilience = Resilience.run(runtime, supervisor, Common.replacement_host(supervisor), samples)
    stages = StageTracker.snapshot(tracker)

    report =
      build_report(profile, runtime, datasets, load, resilience, stages, preparation_ms, opts)

    with :ok <- validate_generated(report, opts),
         {:ok, paths} <-
           Report.write(
             report,
             Keyword.get(opts, :output_root, "eval/reports/operational/diagnostics")
           ) do
      {:ok, %{report: report, paths: paths}}
    end
  end

  defp start_runtime(runtime, opts) do
    child_opts = [
      runtime: runtime,
      max_in_flight: Keyword.fetch!(opts, :concurrency),
      diagnostics: Keyword.get(opts, :diagnostics, true),
      id: :operational_diagnostic_runtime_host
    ]

    case Supervisor.start_link([{RuntimeHost, child_opts}], strategy: :one_for_one) do
      {:ok, supervisor} ->
        {:ok, supervisor, Common.replacement_host(supervisor)}

      {:error, reason} ->
        {:error, {:diagnostic_supervisor_start_failed, Common.safe_reason(reason)}}
    end
  end

  defp select_samples(samples, :mixed), do: samples

  defp select_samples(samples, :fixed_triplet) do
    samples
    |> Enum.group_by(& &1.dataset_id)
    |> Enum.map(fn {_dataset, rows} -> List.first(rows) end)
    |> Enum.sort_by(&to_string(&1.dataset_id))
  end

  defp build_report(profile, runtime, datasets, load, resilience, stages, preparation_ms, opts) do
    analysis = Analysis.analyze(load)

    %{
      schema_version: Schema.version(),
      status: if(Keyword.get(opts, :authoritative, false), do: :complete, else: :exploratory),
      generated_at: DateTime.utc_now(),
      profile: profile,
      resolved_profile: runtime.implementation_profile,
      experiment: %{
        id: Keyword.fetch!(opts, :run_id),
        kind: Keyword.get(opts, :kind, :instrumented),
        repetition: Keyword.get(opts, :repetition, 1),
        diagnostics_enabled: Keyword.get(opts, :diagnostics, true),
        sample_mode: Keyword.get(opts, :sample_mode, :mixed),
        behavior_changes_allowed: false
      },
      datasets: Enum.map(datasets, &Common.dataset_metadata/1),
      workload:
        Map.drop(load, [
          :memory_analysis,
          :memory_classification,
          :post_soak,
          :resource_series,
          :diagnostics
        ]),
      stage_diagnostics: load.diagnostics,
      diagnostic_analysis: analysis,
      instrumentation_overhead: instrumentation_overhead(load, profile, opts),
      resource_series: load.resource_series,
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
        :attention_and_moe_are_fused_in_the_compiled_device_graph,
        :powermetrics_requires_superuser_on_this_runner,
        :emily_allocator_statistics_are_not_physical_gpu_residency,
        :correlation_alone_does_not_prove_causation
      ],
      settings: %{
        duration_ms: Keyword.fetch!(opts, :duration_ms),
        concurrency: Keyword.fetch!(opts, :concurrency),
        request_timeout_ms: Common.request_timeout(profile, opts),
        sample_interval_ms: Keyword.get(opts, :sample_interval, 1_000),
        window_ms: Keyword.get(opts, :window_ms, 60_000),
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
    lifecycle = [
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

    %{
      normal_runtime_builds: 1,
      per_request_rebuild_detected:
        Enum.any?(stages.counts, fn {stage, count} -> stage in lifecycle and count > 1 end),
      lifecycle_stage_counts: stages.counts
    }
  end

  defp validate_generated(report, opts) do
    if Keyword.get(opts, :authoritative, false) do
      report
      |> Jason.encode!()
      |> Jason.decode!()
      |> Schema.validate()
    else
      Schema.validate_privacy(report)
    end
  end

  defp instrumentation_overhead(load, profile, opts) do
    case Keyword.get(opts, :control_report) do
      nil ->
        %{status: :unavailable, reason: :control_report_not_supplied}

      path ->
        with {:ok, body} <- File.read(path),
             {:ok, control} <- Jason.decode(body),
             :ok <- validate_control(control, profile, load, opts) do
          control_throughput = get_in(control, ["workload", "throughput_rps"])
          control_p95 = get_in(control, ["workload", "latency_ms", "p95"])
          measured_p95 = load.latency_ms.p95
          source_commit = Metadata.git().source_commit

          %{
            status: :measured,
            control_experiment_id: get_in(control, ["experiment", "id"]),
            same_source_commit: get_in(control, ["source", "source_commit"]) == source_commit,
            same_profile: control["profile"] == Atom.to_string(profile),
            same_concurrency:
              get_in(control, ["workload", "concurrency"]) ==
                Keyword.fetch!(opts, :concurrency),
            same_duration:
              get_in(control, ["workload", "requested_duration_ms"]) ==
                Keyword.fetch!(opts, :duration_ms),
            same_sample_mode:
              get_in(control, ["experiment", "sample_mode"]) ==
                Atom.to_string(Keyword.get(opts, :sample_mode, :mixed)),
            output_probe_match:
              get_in(control, ["workload", "output_stability", "probe"]) ==
                json_normalize(load.output_stability.probe),
            throughput_delta_ratio: relative_delta(control_throughput, load.throughput_rps),
            p95_latency_delta_ratio: relative_delta(control_p95, measured_p95),
            control: %{
              throughput_rps: control_throughput,
              p95_latency_ms: control_p95
            },
            instrumented: %{
              throughput_rps: load.throughput_rps,
              p95_latency_ms: measured_p95
            }
          }
        else
          {:error, reason} -> %{status: :invalid, reason: Common.safe_reason(reason)}
        end
    end
  end

  defp validate_control(control, profile, load, opts) do
    checks = [
      control["profile"] == Atom.to_string(profile),
      get_in(control, ["experiment", "kind"]) == "control",
      get_in(control, ["experiment", "diagnostics_enabled"]) == false,
      get_in(control, ["experiment", "sample_mode"]) ==
        Atom.to_string(Keyword.get(opts, :sample_mode, :mixed)),
      get_in(control, ["workload", "concurrency"]) == Keyword.fetch!(opts, :concurrency),
      get_in(control, ["workload", "requested_duration_ms"]) ==
        Keyword.fetch!(opts, :duration_ms),
      get_in(control, ["workload", "output_stability", "probe"]) ==
        json_normalize(load.output_stability.probe)
    ]

    if Enum.all?(checks), do: :ok, else: {:error, :control_report_mismatch}
  end

  defp relative_delta(baseline, measured)
       when is_number(baseline) and baseline != 0 and is_number(measured),
       do: (measured - baseline) / baseline

  defp relative_delta(_baseline, _measured), do: nil

  defp json_normalize(term), do: term |> Jason.encode!() |> Jason.decode!()
end
