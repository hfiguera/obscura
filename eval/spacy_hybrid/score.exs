defmodule Obscura.SpacyHybrid.ImportedNER do
  @moduledoc false
  @behaviour Obscura.Recognizer

  @impl true
  def name, do: :spacy_experiment

  @impl true
  def supported_entities, do: [:person, :location]

  @impl true
  def analyze(text, opts) do
    Obscura.Analyzer.ModelOutput.normalize(text, Keyword.fetch!(opts, :model_outputs),
      include_text: false,
      label_map: %{person: ["PERSON"], location: ["GPE", "LOC", "FAC"]},
      unknown_labels: :error
    )
  end
end

defmodule Obscura.SpacyHybrid.Score do
  @moduledoc false
  alias Obscura.Eval.{ComparisonProtocol, Metrics, Offset, PresidioResearchLoader}
  alias Obscura.SpacyHybrid.ImportedNER

  @metric_keys [
    :precision,
    :recall,
    :f1,
    :f2,
    :true_positives,
    :false_positives,
    :false_negatives,
    :offset_mismatches,
    :wrong_entity_type,
    :total_supported_expected_spans,
    :total_predicted_spans,
    :total_samples,
    :unsupported_expected_spans,
    :span_iou,
    :per_entity,
    :latency
  ]

  def main([manifest_path]) do
    experiment = read_json(manifest_path)

    datasets =
      Enum.map(
        experiment["datasets"],
        &score_dataset(&1, experiment, Path.dirname(manifest_path))
      )

    result =
      experiment
      |> Map.put("datasets", datasets)
      |> Map.put("inference_manifest_sha256", sha256_file(manifest_path))
      |> Map.update!(
        "code_sha256",
        &Map.put(&1, "eval/spacy_hybrid/score.exs", sha256_file(__ENV__.file))
      )
      |> Map.put("elixir", System.version())
      |> Map.put("otp_release", to_string(:erlang.system_info(:otp_release)))
      |> Map.put("schedulers", :erlang.system_info(:schedulers_online))
      |> Map.put("scoring_code_sha256", sha256_file(__ENV__.file))
      |> Map.put("analyzer_contract", %{
        "fast" => "deterministic_plus with normal default conflict resolution",
        "fast_reference" =>
          "deterministic_plus with conflict_strategy none, matching the historical fixture adapter",
        "hybrid" =>
          "deterministic_plus plus imported model outputs with normal default conflict resolution"
      })

    File.write!(
      Path.join(Path.dirname(manifest_path), "results.json"),
      Jason.encode!(result, pretty: true) <> "\n"
    )
  end

  def score_dataset(entry, experiment, out_dir) do
    dataset =
      Enum.find(PresidioResearchLoader.known_datasets(), &(to_string(&1) == entry["name"]))

    true = not is_nil(dataset)
    selection = read_json(entry["selection_path"])
    true = sha256_file(entry["selection_path"]) == entry["selection_sha256"]
    {:ok, prepared} = ComparisonProtocol.prepare(dataset)
    true = prepared == selection
    split = get_in(selection, ["dataset", "template_split", "name"]) |> String.to_existing_atom()

    {:ok, loaded} =
      PresidioResearchLoader.load(
        dataset: dataset,
        profile: :regex_only,
        invalid_span: :drop_sample,
        template_split: split,
        template_train_ratio: 0.7
      )

    ids = Enum.map(loaded.samples, & &1.id)
    true = ids == selection["dataset"]["ordered_sample_ids"]
    true = loaded.sha256 == selection["dataset"]["sha256"]
    entities = Enum.map(selection["entity_policy"]["entities"], &String.to_existing_atom/1)
    options = [profile: :deterministic_plus, entities: entities, include_text: false]

    runs =
      Enum.flat_map(1..experiment["repetitions"], fn repetition ->
        warmup = Enum.take(loaded.samples, experiment["warmup_samples_per_mode"])
        Enum.each(warmup, &analyze_sample(&1, nil, options))
        fast_results = Enum.map(loaded.samples, &analyze_sample(&1, nil, options))
        base = summarize(fast_results, "fast", repetition, entities, out_dir, dataset)
        reference_options = Keyword.put(options, :conflict_strategy, :none)
        Enum.each(warmup, &analyze_sample(&1, nil, reference_options))

        reference =
          loaded.samples
          |> Enum.map(&analyze_sample(&1, nil, reference_options))
          |> summarize("fast_reference", repetition, entities, out_dir, dataset)

        hybrids =
          entry["runs"]
          |> Enum.filter(&(&1["repetition"] == repetition))
          |> Enum.map(fn run ->
            true = sha256_file(run["path"]) == run["sha256"]
            artifact = read_json(run["path"])
            validate_artifact!(artifact, entry, run, ids)
            pairs = Enum.zip(loaded.samples, artifact["rows"])

            Enum.each(pairs, fn {sample, row} ->
              validate_predictions!(sample.text, row["predictions"], entities)
            end)

            if run["mode"] != "presidio" do
              Enum.each(Enum.take(pairs, length(warmup)), fn {sample, row} ->
                analyze_sample(sample, row, options)
              end)
            end

            results =
              Enum.map(pairs, fn {sample, row} ->
                if run["mode"] == "presidio",
                  do: external_sample(sample, row),
                  else: analyze_sample(sample, row, options)
              end)

            profile = if run["mode"] == "presidio", do: "presidio", else: "hybrid_" <> run["mode"]
            summarize(results, profile, repetition, entities, out_dir, dataset)
          end)

        [base, reference | hybrids]
      end)

    fingerprints =
      runs
      |> Enum.group_by(& &1.profile)
      |> Map.new(fn {profile, repetitions} ->
        identical =
          repetitions |> Enum.map(& &1.output_fingerprint_sha256) |> Enum.uniq() |> length() == 1

        true = identical
        metric_repetitions = Enum.map(repetitions, &Map.delete(&1.metrics, :latency))
        true = length(Enum.uniq(metric_repetitions)) == 1

        {profile,
         %{
           identical_predictions: identical,
           identical_accuracy: true,
           repetitions: length(repetitions)
         }}
      end)

    IO.puts(
      Jason.encode!(%{phase: "scoring", dataset: dataset, repetitions_verified: fingerprints})
    )

    %{
      name: dataset,
      selection: selection,
      selection_sha256: entry["selection_sha256"],
      runs: runs,
      repetition_checks: fingerprints
    }
  end

  def validate_artifact!(artifact, entry, run, ids) do
    true = artifact["dataset"] == entry["name"]
    true = artifact["mode"] == run["mode"]
    true = artifact["repetition"] == run["repetition"]
    true = artifact["selection_sha256"] == entry["selection_sha256"]
    true = Enum.map(artifact["rows"], & &1["sample_id"]) == ids
  end

  def validate_predictions!(text, predictions, entities) do
    Enum.each(predictions, fn prediction ->
      true = prediction["entity"] in Enum.map(entities, &to_string/1)

      true =
        is_number(prediction["score"]) and prediction["score"] >= 0 and prediction["score"] <= 1

      span =
        Map.new(
          [:byte_start, :byte_end, :char_start, :char_end],
          &{&1, prediction[to_string(&1)]}
        )

      :ok = Offset.validate_span(text, span)
      {:ok, _} = Offset.byte_to_char(text, span.byte_start)
      {:ok, _} = Offset.byte_to_char(text, span.byte_end)
    end)
  end

  def analyze_sample(sample, row, options) do
    outputs =
      if row do
        Enum.map(row["predictions"], fn p ->
          %{
            label: p["label"],
            start: p["byte_start"],
            end: p["byte_end"],
            score: p["score"],
            offset_unit: :byte
          }
        end)
      end

    opts =
      if row,
        do: Keyword.put(options, :recognizers, [{ImportedNER, model_outputs: outputs}]),
        else: options

    started = System.monotonic_time()
    {:ok, predicted} = Obscura.analyze(sample.text, opts)

    obscura_ms =
      System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond) / 1000

    python_ms = if row, do: row["processing_ms"], else: 0.0

    %{
      sample: sample,
      expected: sample.spans,
      predicted: predicted,
      latency_ms: obscura_ms + python_ms,
      obscura_ms: obscura_ms,
      python_ms: python_ms
    }
  end

  defp external_sample(sample, row) do
    predicted =
      Enum.map(row["predictions"], fn p ->
        %{
          entity: String.to_existing_atom(p["entity"]),
          byte_start: p["byte_start"],
          byte_end: p["byte_end"],
          score: p["score"]
        }
      end)

    %{
      sample: sample,
      expected: sample.spans,
      predicted: predicted,
      latency_ms: row["inference_ms"],
      python_ms: row["inference_ms"],
      obscura_ms: 0.0
    }
  end

  defp summarize(results, profile, repetition, entities, out_dir, dataset) do
    metrics =
      Metrics.score_results(results, :regex_only,
        supported_entities: entities,
        iou_threshold: 0.9
      )

    predictions =
      Enum.map(results, fn result ->
        %{
          sample_id: result.sample.id,
          predictions:
            Enum.map(result.predicted, &Map.take(&1, [:entity, :byte_start, :byte_end, :score]))
        }
      end)

    path = Path.join(out_dir, "#{dataset}__#{profile}__r#{repetition}__scored_predictions.json")
    File.write!(path, Jason.encode!(predictions) <> "\n")

    exact_predictions =
      Enum.map(predictions, fn row ->
        %{
          sample_id: row.sample_id,
          predictions: Enum.map(row.predictions, &Map.delete(&1, :score))
        }
      end)

    # Conventional strict counts include wrong-type/boundary errors as both a
    # missed gold span and an extra prediction. Keep these alongside the shared
    # evaluator's historical ratios, which separate those error categories.
    strict = %{
      true_positives: metrics.true_positives,
      false_positives: metrics.total_predicted_spans - metrics.true_positives,
      false_negatives: metrics.total_supported_expected_spans - metrics.true_positives
    }

    %{
      profile: profile,
      repetition: repetition,
      metrics:
        metrics
        |> Map.take(@metric_keys)
        |> Map.update!(:span_iou, &Map.delete(&1, :examples)),
      strict_exact: Map.merge(strict, Metrics.ratios(strict)),
      output_fingerprint_sha256: ComparisonProtocol.canonical_sha256(exact_predictions),
      predictions_path: path,
      predictions_sha256: sha256_file(path),
      python_processing_mean_ms: mean(results, :python_ms),
      obscura_analysis_mean_ms: mean(results, :obscura_ms)
    }
  end

  defp mean(results, key), do: Enum.sum(Enum.map(results, &Map.fetch!(&1, key))) / length(results)
  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp sha256_file(path),
    do: path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
