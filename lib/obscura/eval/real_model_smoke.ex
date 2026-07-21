defmodule Obscura.Eval.RealModelSmoke do
  @moduledoc """
  Opt-in real-model smoke report generation.
  """

  alias Obscura.Eval.Metrics
  alias Obscura.Eval.PresidioResearchLoader
  alias Obscura.Eval.Profile
  alias Obscura.Eval.Report
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.Backend
  alias Obscura.Recognizer.NER.ModelRegistry
  alias Obscura.Recognizer.NER.ModelSpec
  alias Obscura.Recognizer.NER.RealModelSmoke
  alias Obscura.Recognizer.NER.Serving
  alias Obscura.Telemetry

  @doc """
  Runs the single-sample model smoke and writes a report.
  """
  @spec write_smoke_report(keyword()) :: :ok | {:error, term()}
  def write_smoke_report(opts \\ []) do
    report =
      case RealModelSmoke.run(opts) do
        {:ok, result} -> smoke_report(result, opts)
        {:error, reason} -> skipped_smoke_report(reason, opts)
      end

    Report.write_pair(
      report,
      "eval/reports/#{report.run_id}.json",
      "eval/reports/#{report.run_id}.md"
    )
  end

  @doc """
  Runs Presidio-Research real NER smoke when the model can be built.
  """
  @spec write_presidio_report(keyword()) :: :ok | {:error, term()}
  def write_presidio_report(opts \\ []) do
    start = System.monotonic_time()

    report =
      with {:ok, serving} <- Serving.build(opts),
           {:ok, dataset} <- PresidioResearchLoader.load(profile: :real_ner),
           samples <-
             PresidioResearchLoader.smoke_subset(
               dataset.samples,
               :real_ner,
               Keyword.get(opts, :limit, 25)
             ),
           {:ok, results} <- run_samples(samples, serving, opts),
           metrics <- Metrics.score_results(results, :real_ner) do
        emit(start, :ok, opts, length(samples), results)
        presidio_report(dataset, samples, metrics, serving)
      else
        {:error, reason} ->
          emit(start, :error, opts, 0, [])
          skipped_presidio_report(reason, opts)
      end

    Report.write_pair(
      report,
      "eval/reports/#{report.run_id}.json",
      "eval/reports/#{report.run_id}.md"
    )
  end

  defp run_samples(samples, serving, opts) do
    samples
    |> Enum.reduce_while({:ok, []}, fn sample, {:ok, acc} ->
      start = System.monotonic_time()

      case Obscura.analyze(sample.text,
             entities: Profile.supported_entities(:real_ner),
             recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
             recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 30_000),
             include_text: false
           ) do
        {:ok, predicted} ->
          result = %{
            sample: sample,
            expected: sample.spans,
            predicted: Enum.map(predicted, &to_span/1),
            latency_ms: elapsed_ms(start)
          }

          {:cont, {:ok, [result | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:sample_analysis_failed, sample.id, reason}}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_span(result) do
    %{
      entity: result.entity,
      byte_start: result.byte_start,
      byte_end: result.byte_end,
      source_entity: result.source_entity,
      metadata: Map.drop(result.metadata, [:text, :value, :phrase])
    }
  end

  defp smoke_report(result, opts) do
    report(
      run_id: "phase_4_5_#{model_alias(opts)}_smoke",
      dataset: %{
        name: "phase_4_5_single_sample",
        source: "local",
        version: "phase_4_5",
        sample_count: 1,
        smoke: true
      },
      metrics:
        Metrics.score([], [], :real_ner,
          total_samples: 1,
          latency_ms: [result.latency_ms]
        ),
      model: result.model,
      limitations: [
        "Real local model smoke ran without storing raw input text or detected values in this report.",
        "Successful inference proves integration only, not production accuracy.",
        "Model assets may have been downloaded by the explicit opt-in command."
      ],
      opts: opts
    )
  end

  defp skipped_smoke_report(_reason, opts) do
    report(
      run_id: "phase_4_5_#{model_alias(opts)}_smoke",
      dataset: %{
        name: "phase_4_5_single_sample",
        source: "local",
        version: "phase_4_5",
        sample_count: 0,
        smoke: true,
        status: "skipped"
      },
      metrics: Metrics.score([], [], :real_ner, total_samples: 0, latency_ms: []),
      model: safe_model_metadata(opts),
      limitations: [
        "Real local model smoke was skipped because its runtime requirements were unavailable.",
        "Run OBSCURA_REAL_MODEL=1 mix obscura.ner.smoke --model #{model_alias(opts)} after optional model dependencies/assets are available."
      ],
      opts: opts
    )
  end

  defp presidio_report(dataset, samples, metrics, serving) do
    model_alias = serving.model_spec.id |> to_string()

    report(
      run_id: "phase_4_5_presidio_research_real_ner_#{model_alias}_smoke",
      dataset: %{
        name: dataset.name,
        source: dataset.source,
        version: dataset.version,
        sample_count: length(samples),
        full_sample_count: dataset.sample_count,
        smoke: true
      },
      metrics: metrics,
      model: ModelSpec.metadata(serving.model_spec),
      limitations: [
        "Report compares real #{ModelSpec.hf_id(serving.model_spec.model)} only for person, organization, and location.",
        "Regex-only and Phase 4 fake NER reports remain separate baselines.",
        "Exact-span scoring is strict and may penalize tokenizer span differences."
      ],
      opts: []
    )
  end

  defp skipped_presidio_report(_reason, opts) do
    report(
      run_id: "phase_4_5_presidio_research_real_ner_#{model_alias(opts)}_smoke",
      dataset: %{
        name: "synth_dataset_v2",
        source: "eval/datasets/presidio_research",
        version: "presidio-research-snapshot",
        sample_count: 0,
        smoke: true,
        status: "skipped"
      },
      metrics: Metrics.score([], [], :real_ner, total_samples: 0, latency_ms: []),
      model: safe_model_metadata(opts),
      limitations: [
        "Presidio-Research real NER smoke was skipped because its runtime requirements were unavailable.",
        "Run the opt-in real-model smoke after optional dependencies and model assets are available."
      ],
      opts: opts
    )
  end

  defp report(opts) do
    report =
      Report.build(
        run_id: Keyword.fetch!(opts, :run_id),
        phase: "phase_4_5",
        adapter: "Obscura.Eval.RealModelSmoke",
        profile: :real_ner,
        dataset: Keyword.fetch!(opts, :dataset),
        offset_mode: %{input: "byte", internal: "byte", scoring: "byte", conversion: "validated"},
        metrics: Keyword.fetch!(opts, :metrics),
        limitations: Keyword.fetch!(opts, :limitations)
      )

    report
    |> Map.put(:model, Keyword.fetch!(opts, :model))
    |> Map.put(:runtime_backend, Backend.metadata(Keyword.fetch!(opts, :opts)))
    |> Map.put(:model_assets, %{
      local_or_downloaded: "unknown",
      opt_in_command: true,
      caches_committed: false
    })
  end

  defp safe_model_metadata(opts) do
    model = Keyword.get(opts, :model, :dslim_bert_base_ner)

    case ModelRegistry.metadata(model) do
      {:ok, metadata} -> metadata
      {:error, _reason} -> %{model_alias: model}
    end
  end

  defp model_alias(opts) do
    opts
    |> Keyword.get(:model, :dslim_bert_base_ner)
    |> to_string()
  end

  defp emit(start, status, opts, input_count, results) do
    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :eval, :real_model, :stop],
      %{duration: System.monotonic_time() - start},
      %{
        status: status,
        profile: :real_ner,
        model_alias: Keyword.get(opts, :model, :dslim_bert_base_ner),
        input_count: input_count,
        result_count: results |> Enum.flat_map(& &1.predicted) |> length()
      }
    )
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end
end
