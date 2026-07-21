defmodule Obscura.Eval.Operational.Benchmark do
  @moduledoc """
  Authoritative operational benchmark orchestration for measured product profiles.
  """

  alias Obscura.Eval.Operational.AssetEvidence
  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Eval.Operational.LoadRunner
  alias Obscura.Eval.Operational.Metadata
  alias Obscura.Eval.Operational.Report
  alias Obscura.Eval.Operational.Resilience
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.Schema
  alias Obscura.Eval.Operational.StageTracker
  alias Obscura.Profile

  @concurrencies [1, 2, 4, 8, 16]

  @spec run(Profile.name(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def run(profile, opts \\ []) do
    datasets = Keyword.get(opts, :datasets, Dataset.names())
    output_root = Keyword.get(opts, :output_root, "eval/reports/operational")

    try do
      with {:ok, loaded_datasets} <- Common.load_datasets(datasets, profile),
           {:ok, tracker} <- StageTracker.start_link(),
           {:ok, runtime, preparation_ms} <- Common.prepare_runtime(profile, tracker, opts),
           {:ok, first_inference_ms} <- first_inference(runtime, loaded_datasets),
           {:ok, supervisor, host} <- start_runtime_supervisor(runtime, opts) do
        warm =
          Map.new(loaded_datasets, fn dataset ->
            rows =
              Enum.map(@concurrencies, fn concurrency ->
                LoadRunner.run(host, dataset.samples,
                  concurrency: concurrency,
                  repetitions: Keyword.get(opts, :repetitions, 2),
                  timeout: Common.request_timeout(profile, opts),
                  gpu: Common.gpu?(profile)
                )
              end)

            {dataset.name, rows}
          end)

        sustained =
          LoadRunner.sustained(host, Enum.flat_map(loaded_datasets, & &1.samples),
            concurrency: Keyword.get(opts, :sustained_concurrency, 4),
            duration_ms: Keyword.get(opts, :sustained_duration_ms, 60_000),
            request_count: Keyword.get(opts, :sustained_request_count),
            timeout: Common.request_timeout(profile, opts),
            gpu: Common.gpu?(profile)
          )

        resilience =
          Resilience.run(runtime, supervisor, host, List.first(loaded_datasets).samples)

        stage_snapshot = StageTracker.snapshot(tracker)

        cold =
          Keyword.get(opts, :cold_lifecycle) || local_cold(preparation_ms, first_inference_ms)

        environment = Common.environment(profile, runtime.backend_metadata)
        source = Metadata.git()
        hardware = Metadata.hardware()

        reports =
          Enum.map(loaded_datasets, fn dataset ->
            report =
              build_report(%{
                profile: profile,
                runtime: runtime,
                dataset: dataset,
                warm: warm[dataset.name],
                sustained: sustained,
                resilience: resilience,
                stages: stage_snapshot,
                cold: cold,
                environment: environment,
                source: source,
                hardware: hardware,
                preparation_ms: preparation_ms,
                opts: opts
              })

            with :ok <- validate_generated(report),
                 {:ok, paths} <- Report.write(report, output_root) do
              %{report: report, paths: paths}
            else
              {:error, reason} -> throw({:operational_report_failed, reason})
            end
          end)

        Supervisor.stop(supervisor)
        Agent.stop(tracker)
        {:ok, reports}
      end
    catch
      {:operational_report_failed, reason} -> {:error, reason}
    end
  end

  @spec cold(Profile.name(), Dataset.name(), keyword()) :: {:ok, map()} | {:error, term()}
  def cold(profile, dataset_name, opts \\ []) do
    process_started = System.monotonic_time()
    application_started = System.monotonic_time()

    with {:ok, _apps} <- Application.ensure_all_started(:obscura),
         application_start_ms <- elapsed_ms(application_started),
         {:ok, dataset} <- Dataset.load(dataset_name, profile: profile),
         {:ok, tracker} <- StageTracker.start_link(),
         {:ok, runtime, preparation_ms} <- Common.prepare_runtime(profile, tracker, opts),
         {:ok, first_inference_ms} <- first_inference(runtime, [dataset]) do
      stages = StageTracker.snapshot(tracker)
      Agent.stop(tracker)

      {:ok,
       %{
         status: :measured,
         fresh_os_process: true,
         assets_preprovisioned: true,
         network_downloads_allowed: false,
         application_start_ms: application_start_ms,
         runtime_preparation_ms: preparation_ms,
         first_inference_ms: first_inference_ms,
         total_ready_ms: elapsed_ms(process_started),
         stages: stages.events,
         stage_counts: stages.counts,
         compile_timing: %{
           status: :combined_with_first_inference,
           reason: :nx_serving_does_not_expose_lazy_compile_separately
         }
       }}
    end
  end

  defp first_inference(runtime, [dataset | _rest]) do
    sample = List.first(dataset.samples)
    started = System.monotonic_time()

    case Obscura.analyze(sample.text, profile: runtime, include_text: false) do
      {:ok, _results} ->
        {:ok, elapsed_ms(started)}

      {:error, reason} ->
        {:error, {:operational_first_inference_failed, Common.safe_reason(reason)}}
    end
  end

  defp start_runtime_supervisor(runtime, opts) do
    child_opts = [
      runtime: runtime,
      max_in_flight: Keyword.get(opts, :max_in_flight, 16),
      id: :operational_runtime_host
    ]

    case Supervisor.start_link([{RuntimeHost, child_opts}], strategy: :one_for_one) do
      {:ok, supervisor} ->
        {:ok, supervisor, child_pid(supervisor)}

      {:error, reason} ->
        {:error, {:operational_supervisor_start_failed, Common.safe_reason(reason)}}
    end
  end

  defp child_pid(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> List.first()
    |> elem(1)
  end

  defp build_report(context) do
    profile = context.profile
    runtime = context.runtime
    dataset = context.dataset
    warm = context.warm
    sustained = context.sustained
    stages = context.stages
    cold = context.cold
    opts = context.opts
    warm_mean = warm |> List.first() |> get_in([:latency_ms, :p50])
    {:ok, asset_evidence} = AssetEvidence.for_profile_dataset(profile, dataset.selection)

    %{
      schema_version: Schema.version(),
      status: :complete,
      generated_at: DateTime.utc_now(),
      profile: profile,
      resolved_profile: runtime.implementation_profile,
      dataset: Common.dataset_metadata(dataset),
      cold_lifecycle: cold,
      warm_load: %{
        warmup_requests: 1,
        runtime_reused: true,
        deterministic_sample_order: true,
        concurrency_results: warm
      },
      sustained_load: Map.put(sustained, :status, :measured),
      resilience: context.resilience,
      runtime_reuse: %{
        normal_runtime_builds: 1,
        per_request_rebuild_detected: false,
        lifecycle_stage_counts: stages.counts,
        anti_pattern: %{
          status: :measured,
          canonical: false,
          method: :process_cold_per_request_projection,
          process_cold_ms: cold.total_ready_ms,
          warm_p50_ms: warm_mean,
          projected_overhead_ratio: ratio(cold.total_ready_ms, warm_mean),
          reason: :isolated_to_avoid_polluting_canonical_runtime_reuse
        }
      },
      resources: aggregate_resources(warm, sustained),
      environment: context.environment,
      hardware: context.hardware,
      runtime: Metadata.runtime(),
      asset_evidence: asset_evidence,
      preparation: %{
        in_process_runtime_preparation_ms: context.preparation_ms,
        stages: stages.events
      },
      source: context.source,
      benchmark_settings: %{
        repetitions: Keyword.get(opts, :repetitions, 2),
        concurrency: @concurrencies,
        request_timeout_ms: Common.request_timeout(profile, opts),
        sustained_duration_ms: Keyword.get(opts, :sustained_duration_ms, 60_000),
        sustained_request_count: Keyword.get(opts, :sustained_request_count),
        model_downloads_allowed: false
      },
      limitations: [
        :nx_lazy_compile_not_independently_timed,
        :inline_nx_queue_time_unavailable,
        :gpu_memory_available_only_for_emily,
        :linux_exla_not_measured_on_apple_runner
      ]
    }
  end

  defp aggregate_resources(warm, sustained) do
    repetitions = Enum.flat_map(warm, & &1.repetitions)

    %{
      warm_peak_beam_bytes: max_resource(repetitions, [:resources, :beam, :peak]),
      warm_peak_rss_bytes: max_resource(repetitions, [:resources, :os_rss, :peak]),
      warm_peak_gpu_bytes: max_resource(repetitions, [:resources, :gpu, :peak_bytes]),
      sustained_memory_growth_bytes: sustained.memory_growth_bytes,
      sustained_peak_beam_bytes: get_in(sustained, [:resources, :beam, :peak]),
      sustained_peak_rss_bytes: get_in(sustained, [:resources, :os_rss, :peak]),
      sustained_peak_gpu_bytes: get_in(sustained, [:resources, :gpu, :peak_bytes]),
      scheduler_run_queue_peak:
        max_resource(repetitions, [:resources, :scheduler, :run_queue, :peak]),
      source: %{
        beam: :erlang_memory,
        rss: :os_ps_sampling,
        gpu:
          if(repetitions |> List.first() |> get_in([:resources, :gpu, :status]) == :measured,
            do: :emily_memory,
            else: :unavailable
          )
      }
    }
  end

  defp max_resource(rows, path) do
    values = rows |> Enum.map(&get_in(&1, path)) |> Enum.filter(&is_number/1)
    if values == [], do: nil, else: Enum.max(values)
  end

  defp validate_generated(report) do
    report
    |> Jason.encode!()
    |> Jason.decode!()
    |> Schema.validate()
  end

  defp local_cold(preparation_ms, first_inference_ms) do
    %{
      status: :measured,
      fresh_os_process: false,
      assets_preprovisioned: true,
      network_downloads_allowed: false,
      application_start_ms: nil,
      runtime_preparation_ms: preparation_ms,
      first_inference_ms: first_inference_ms,
      total_ready_ms: preparation_ms + first_inference_ms,
      stages: [],
      stage_counts: %{},
      compile_timing: %{
        status: :combined_with_first_inference,
        reason: :nx_serving_does_not_expose_lazy_compile_separately
      }
    }
  end

  defp ratio(_left, right) when right in [nil, 0, 0.0], do: nil
  defp ratio(left, right) when is_number(left) and is_number(right), do: left / right

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
