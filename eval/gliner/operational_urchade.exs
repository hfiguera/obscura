defmodule Obscura.Eval.GLiNERUrchadeOperational do
  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Eval.Operational.LoadRunner
  alias Obscura.Eval.Operational.Resilience
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Profile.Runtime
  alias Obscura.Recognizer.GLiNER
  alias Obscura.Recognizer.GLiNER.Ortex, as: GLiNEROrtex

  def run do
    model_dir =
      System.get_env("OBSCURA_GLINER_URCHADE_MODEL_DIR") ||
        raise "OBSCURA_GLINER_URCHADE_MODEL_DIR is required"

    output =
      System.get_env("OBSCURA_GLINER_OPERATIONAL_OUTPUT") ||
        "eval/reports/urchade-gliner-operational-characterization.json"

    provider =
      case System.get_env("OBSCURA_GLINER_OPERATIONAL_PROVIDER", "cpu") do
        "cpu" -> :cpu
        "coreml" -> :coreml
        other -> raise "unsupported provider: #{other}"
      end

    profile_prefix =
      if provider == :coreml do
        System.get_env(
          "OBSCURA_GLINER_OPERATIONAL_PROFILE_PREFIX",
          "eval/reports/profiles/urchade-coreml"
        )
      end

    concurrencies = [1, 2, 4, 8, 16]

    dataset_names = [
      :generated_large_template_heldout,
      :synth_dataset_v2_all,
      :nemotron_pii_test_subset_all
    ]

    started = System.monotonic_time()

    {:ok, serving} =
      GLiNEROrtex.build(
        model: :urchade_gliner_multi_pii_v1,
        model_dir: model_dir,
        execution_providers: [provider],
        profile_prefix: profile_prefix
      )

    preparation_ms =
      System.monotonic_time()
      |> Kernel.-(started)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1_000)

    thresholds = %{"person" => 0.5, "organization" => 0.9, "location" => 0.5}
    entities = [:credit_card, :email, :ip_address, :location, :person, :phone, :url, :us_ssn]

    runtime = %Runtime{
      profile: :hybrid_gliner_urchade,
      implementation_profile: :hybrid_gliner_urchade,
      resources: %{gliner: serving},
      analyzer_options: [
        profile: :hybrid_gliner_urchade,
        entities: entities,
        recognizers: [
          :default,
          {GLiNER,
           [
             serving: serving,
             model: :urchade_gliner_multi_pii_v1,
             label_profile: :open_class,
             threshold: 0.5,
             per_label_thresholds: thresholds
           ]}
        ],
        recognizer_timeout: 300_000,
        include_text: false
      ],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{
        runtime: :ortex,
        requested_execution_providers: [provider],
        provider_verified: provider == :cpu,
        provider_verification:
          if(provider == :cpu, do: :only_cpu_provider_requested, else: :pending_profile),
        coreml_options: serving.provider_metadata[:coreml_options]
      }
    }

    loaded =
      Enum.map(dataset_names, fn name ->
        {:ok, dataset} = Dataset.load(name, profile: :hybrid_gliner_urchade)
        selected = length_stratified(dataset.samples, 32)
        Map.put(dataset, :selected_samples, selected)
      end)

    first_sample = loaded |> List.first() |> Map.fetch!(:selected_samples) |> List.first()
    first_started = System.monotonic_time()

    {:ok, _first_results} =
      Obscura.analyze(first_sample.text, profile: runtime, include_text: false)

    first_inference_ms =
      System.monotonic_time()
      |> Kernel.-(first_started)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1_000)

    {:ok, supervisor} =
      Supervisor.start_link(
        [{RuntimeHost, runtime: runtime, max_in_flight: 16, id: :urchade_operational_runtime}],
        strategy: :one_for_one
      )

    host = supervisor |> Supervisor.which_children() |> List.first() |> elem(1)

    dataset_reports =
      Enum.map(loaded, fn dataset ->
        warm =
          Enum.map(concurrencies, fn concurrency ->
            LoadRunner.run(host, dataset.selected_samples,
              concurrency: concurrency,
              repetitions: 2,
              timeout: 300_000,
              gpu: provider == :coreml
            )
          end)

        %{
          dataset: dataset.name,
          full_sample_count: length(dataset.samples),
          selected_sample_count: length(dataset.selected_samples),
          selected_sample_ids_sha256:
            dataset.selected_samples |> Enum.map(& &1.id) |> canonical_sha256(),
          selection_method: :length_stratified_32,
          warm_load: warm
        }
      end)

    sustained =
      LoadRunner.sustained(
        host,
        Enum.flat_map(loaded, & &1.selected_samples),
        concurrency: 4,
        duration_ms: 300_000,
        request_count: 200,
        timeout: 300_000,
        gpu: provider == :coreml
      )

    resilience =
      Resilience.run(runtime, supervisor, host, List.first(loaded).selected_samples)

    Supervisor.stop(supervisor)

    provider_evidence = provider_evidence(provider, serving)

    report = %{
      schema_version: 1,
      status: :candidate_characterization_only,
      promotion_eligible: false,
      reason: :accuracy_gate_failed_before_full_operational_protocol,
      generated_at: DateTime.utc_now(),
      profile: :hybrid_gliner_urchade,
      model: %{
        id: "urchade/gliner_multi_pii-v1",
        revision: "1fcf13e85f4eef5394e1fcd406cf2ca9ea82351d",
        onnx_sha256: "da317b3dafb6ea26c19bc8725d3c969f788a4669e52e080cf5f56a4e057581b5"
      },
      provider: Map.merge(runtime.backend_metadata, provider_evidence),
      cold_lifecycle: %{
        fresh_os_process: true,
        assets_preprovisioned: true,
        network_downloads_allowed: false,
        runtime_preparation_ms: preparation_ms,
        first_inference_ms: first_inference_ms
      },
      settings: %{
        concurrencies: concurrencies,
        repetitions: 2,
        timeout_ms: 300_000,
        sustained_request_count: 200,
        sustained_concurrency: 4
      },
      datasets: dataset_reports,
      sustained_load: sustained,
      resilience: resilience,
      runtime_reuse: %{
        model_builds: 1,
        per_request_rebuild_detected: false
      },
      limitations: limitations(provider_evidence)
    }

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode_to_iodata!(report, pretty: true))
    IO.puts(output)
  end

  defp length_stratified(samples, count) do
    sorted = Enum.sort_by(samples, &{byte_size(&1.text), &1.id})
    last = length(sorted) - 1

    0..(count - 1)
    |> Enum.map(fn index ->
      position = round(index * last / (count - 1))
      Enum.at(sorted, position)
    end)
    |> Enum.uniq_by(& &1.id)
  end

  defp canonical_sha256(term) do
    term
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp provider_evidence(:cpu, _serving) do
    %{
      provider_verified: true,
      provider_verification: :only_cpu_provider_requested,
      gpu_only_proven: false
    }
  end

  defp provider_evidence(:coreml, serving) do
    case GLiNEROrtex.finish_profiling(serving) do
      {:ok, summary} ->
        summary
        |> Map.put(:provider_verified, summary.coreml_participated)
        |> Map.put(:provider_verification, summary.status)

      {:error, reason} ->
        %{
          provider_verified: false,
          provider_verification: :profile_failed,
          provider_verification_error: inspect(reason),
          gpu_only_proven: false
        }
    end
  end

  defp limitations(provider_evidence) do
    base = [
      :accuracy_gate_failed,
      :length_stratified_subset_not_full_operational_selection,
      :gpu_memory_unavailable_for_ortex
    ]

    cond do
      provider_evidence[:provider_verification] == :only_cpu_provider_requested ->
        base

      provider_evidence[:coreml_participated] ->
        [:coreml_participation_does_not_prove_gpu_only_execution | base]

      true ->
        [:coreml_provider_assignment_not_verified | base]
    end
  end
end

Obscura.Eval.GLiNERUrchadeOperational.run()
