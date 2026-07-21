defmodule Obscura.Eval.ComparisonProtocol do
  @moduledoc """
  Builds and verifies privacy-safe inputs for authoritative external comparisons.

  Python adapters emit predictions only. This module reloads the benchmark
  dataset and applies `Obscura.Eval.Metrics`, ensuring every compared system is
  scored by one implementation.
  """

  alias Obscura.Eval.Metrics
  alias Obscura.Eval.PresidioResearchLoader

  @default_protocol Path.expand("eval/presidio_adapter/authoritative_protocol.json")

  @spec prepare(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def prepare(dataset, opts \\ []) when is_atom(dataset) do
    protocol_path = Keyword.get(opts, :protocol_path, @default_protocol)

    with {:ok, protocol} <- load_protocol(protocol_path),
         {:ok, selection} <- selection_for(protocol, dataset),
         {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: :regex_only,
             invalid_span: :drop_sample,
             template_split: selection.split,
             template_train_ratio: selection.train_ratio
           ) do
      sample_ids = Enum.map(loaded.samples, & &1.id)

      {:ok,
       %{
         "schema_version" => 1,
         "protocol_id" => protocol["id"],
         "protocol_path" => relative_path(protocol_path),
         "protocol_sha256" => sha256_file(protocol_path),
         "dataset" => %{
           "name" => loaded.name,
           "source" => loaded.source,
           "version" => loaded.version,
           "sha256" => loaded.sha256,
           "sample_count" => length(sample_ids),
           "ordered_sample_ids" => sample_ids,
           "sample_ids_sha256" => canonical_sha256(sample_ids),
           "template_split" => stringify(loaded.template_split)
         },
         "entity_policy" => %{
           "entities" => protocol["entities"],
           "source_entity_mapping" => protocol["source_entity_mapping"],
           "sha256" =>
             canonical_sha256(%{
               "entities" => protocol["entities"],
               "source_entity_mapping" => protocol["source_entity_mapping"]
             })
         },
         "scoring" =>
           Map.put(protocol["scoring"], "sha256", canonical_sha256(protocol["scoring"]))
       }}
    end
  end

  @spec write_selection(atom(), Path.t(), keyword()) :: :ok | {:error, term()}
  def write_selection(dataset, path, opts \\ []) do
    with {:ok, selection} <- prepare(dataset, opts),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, Jason.encode!(selection, pretty: true) <> "\n")
    end
  end

  @spec score_external(Path.t(), Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def score_external(selection_path, predictions_path, opts \\ []) do
    with {:ok, selection} <- read_json(selection_path),
         :ok <- validate_selection(selection, selection_path),
         {:ok, dataset} <- dataset_atom(get_in(selection, ["dataset", "name"])),
         {:ok, loaded} <- load_selected_dataset(dataset, selection),
         {:ok, rows} <- read_jsonl(predictions_path),
         :ok <- validate_ordered_rows(rows, selection),
         {:ok, results} <- build_results(rows, loaded.samples, selection),
         metrics <-
           Metrics.score_results(results, :regex_only,
             supported_entities: entity_atoms(selection),
             iou_threshold: get_in(selection, ["scoring", "iou_threshold"])
           ),
         {:ok, reference} <- load_reference(Keyword.fetch!(opts, :reference_report)),
         :ok <- validate_reference(reference, selection, predictions_path) do
      {:ok,
       build_report(
         selection,
         reference,
         metrics |> public_metrics() |> stringify(),
         selection_path,
         predictions_path,
         opts
       )}
    end
  end

  @spec write_external_report(Path.t(), Path.t(), Path.t(), keyword()) ::
          {:ok, %{json: Path.t(), markdown: Path.t(), report: map()}} | {:error, term()}
  def write_external_report(selection_path, predictions_path, out_dir, opts) do
    with {:ok, report} <- score_external(selection_path, predictions_path, opts),
         :ok <- File.mkdir_p(out_dir) do
      run_id = report["run_id"]
      json_path = Path.join(out_dir, run_id <> ".json")
      markdown_path = Path.join(out_dir, run_id <> ".md")

      with :ok <- File.write(json_path, Jason.encode!(report, pretty: true) <> "\n"),
           :ok <- File.write(markdown_path, markdown(report)) do
        {:ok, %{json: json_path, markdown: markdown_path, report: report}}
      end
    end
  end

  @spec annotate_obscura_report(Path.t(), Path.t(), Path.t()) ::
          {:ok, %{json: Path.t(), markdown: Path.t()}} | {:error, term()}
  def annotate_obscura_report(selection_path, report_path, out_path) do
    markdown_path = Path.rootname(report_path) <> ".md"
    out_markdown_path = Path.rootname(out_path) <> ".md"

    with {:ok, selection} <- read_json(selection_path),
         :ok <- validate_selection(selection, selection_path),
         {:ok, report} <- read_json(report_path),
         :ok <- validate_obscura_report(report, selection),
         {:ok, markdown} <- File.read(markdown_path),
         :ok <- File.mkdir_p(Path.dirname(out_path)) do
      annotated =
        report
        |> Map.put("status", "complete")
        |> Map.put("external_baseline", false)
        |> Map.put("gold_derived", false)
        |> Map.put_new("runtime_backend", %{
          "actual_backend" => "beam",
          "actual_device" => "cpu",
          "backend_proven" => true,
          "fallback_occurred" => false
        })
        |> Map.put(
          "comparison_protocol",
          comparison_protocol(selection, selection_path)
        )
        |> put_in(["dataset", "sha256"], get_in(selection, ["dataset", "sha256"]))
        |> put_in(
          ["dataset", "sample_ids_sha256"],
          get_in(selection, ["dataset", "sample_ids_sha256"])
        )

      with :ok <- File.write(out_path, Jason.encode!(annotated, pretty: true) <> "\n"),
           :ok <- File.write(out_markdown_path, String.trim_trailing(markdown) <> "\n") do
        {:ok, %{json: out_path, markdown: out_markdown_path}}
      end
    end
  end

  @spec canonical_sha256(term()) :: String.t()
  def canonical_sha256(value) do
    value
    |> canonical()
    |> Jason.encode!()
    |> sha256_binary()
  end

  defp load_protocol(path) do
    with {:ok, protocol} <- read_json(path),
         :ok <- validate_protocol(protocol) do
      {:ok, protocol}
    end
  end

  defp validate_protocol(%{
         "schema_version" => 1,
         "id" => id,
         "entities" => entities,
         "source_entity_mapping" => mapping,
         "scoring" => scoring,
         "selection" => selection
       })
       when is_binary(id) and is_list(entities) and is_map(mapping) and is_map(scoring) and
              is_map(selection) do
    validate_checks([
      {entities != [], :empty_comparison_entity_policy},
      {entities == Enum.uniq(entities), :duplicate_comparison_entities},
      {not Enum.any?(mapping, fn {_source, target} -> target not in entities end),
       :mapping_target_outside_comparison_policy},
      {scoring["offset_unit"] == "utf8_byte", :unsupported_comparison_offset_unit},
      {is_number(scoring["iou_threshold"]), :missing_comparison_iou_threshold}
    ])
  end

  defp validate_protocol(_protocol), do: {:error, :invalid_comparison_protocol}

  defp selection_for(protocol, dataset) do
    case get_in(protocol, ["selection", Atom.to_string(dataset)]) do
      %{"split" => split, "template_train_ratio" => ratio} ->
        with {:ok, split} <- split_atom(split) do
          {:ok, %{split: split, train_ratio: ratio}}
        end

      _other ->
        {:error, {:dataset_not_in_comparison_protocol, dataset}}
    end
  end

  defp validate_selection(
         %{
           "schema_version" => 1,
           "protocol_path" => protocol_path,
           "protocol_sha256" => protocol_sha,
           "dataset" => dataset,
           "entity_policy" => entity_policy,
           "scoring" => scoring
         },
         selection_path
       ) do
    expanded_protocol = Path.expand(protocol_path)
    ids = dataset["ordered_sample_ids"]

    validate_checks([
      {File.regular?(expanded_protocol), {:comparison_protocol_missing, expanded_protocol}},
      {file_hash_matches?(expanded_protocol, protocol_sha), :comparison_protocol_hash_mismatch},
      {dataset["sample_count"] == length(ids || []), :comparison_sample_count_mismatch},
      {ids == Enum.uniq(ids || []), :duplicate_comparison_sample_ids},
      {dataset["sample_ids_sha256"] == canonical_sha256(ids),
       :comparison_sample_id_fingerprint_mismatch},
      {entity_policy["sha256"] ==
         canonical_sha256(Map.take(entity_policy, ["entities", "source_entity_mapping"])),
       :comparison_entity_policy_fingerprint_mismatch},
      {scoring["sha256"] == canonical_sha256(Map.delete(scoring, "sha256")),
       :comparison_scoring_fingerprint_mismatch},
      {File.regular?(selection_path), {:comparison_selection_missing, selection_path}}
    ])
  end

  defp validate_selection(_selection, _path), do: {:error, :invalid_comparison_selection}

  defp load_selected_dataset(dataset, selection) do
    split = get_in(selection, ["dataset", "template_split", "name"])
    ratio = get_in(selection, ["dataset", "template_split", "train_ratio"]) || 0.7

    with {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: :regex_only,
             invalid_span: :drop_sample,
             template_split: split_atom!(split),
             template_train_ratio: ratio
           ),
         :ok <- validate_loaded_dataset(loaded, selection) do
      {:ok, loaded}
    end
  end

  defp validate_loaded_dataset(loaded, selection) do
    expected_ids = get_in(selection, ["dataset", "ordered_sample_ids"])
    actual_ids = Enum.map(loaded.samples, & &1.id)

    cond do
      loaded.sha256 != get_in(selection, ["dataset", "sha256"]) ->
        {:error, :comparison_dataset_fingerprint_mismatch}

      actual_ids != expected_ids ->
        {:error, :comparison_ordered_sample_ids_mismatch}

      true ->
        :ok
    end
  end

  defp validate_ordered_rows(rows, selection) do
    expected = get_in(selection, ["dataset", "ordered_sample_ids"])
    actual = Enum.map(rows, & &1["sample_id"])

    cond do
      actual != Enum.uniq(actual) -> {:error, :duplicate_prediction_sample_ids}
      actual != expected -> {:error, :prediction_ordered_sample_ids_mismatch}
      true -> :ok
    end
  end

  defp build_results(rows, samples, selection) do
    allowed = MapSet.new(get_in(selection, ["entity_policy", "entities"]))

    rows
    |> Enum.zip(samples)
    |> Enum.reduce_while({:ok, []}, fn {row, sample}, {:ok, results} ->
      with {:ok, predicted} <- normalize_predictions(row["predictions"], sample.text, allowed),
           latency when is_number(latency) and latency >= 0 <- row["latency_ms"] do
        result = %{
          sample: sample,
          expected: sample.spans,
          predicted: predicted,
          latency_ms: latency
        }

        {:cont, {:ok, [result | results]}}
      else
        _other -> {:halt, {:error, {:invalid_prediction_row, row["sample_id"]}}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp normalize_predictions(predictions, text, allowed) when is_list(predictions) do
    Enum.reduce_while(predictions, {:ok, []}, fn prediction, {:ok, normalized} ->
      entity = prediction["entity"]
      start = prediction["byte_start"]
      finish = prediction["byte_end"]

      if MapSet.member?(allowed, entity) and valid_span?(text, start, finish) and
           prediction["value"] in [nil, "[omitted]", "[redacted]"] do
        span = %{
          entity: String.to_existing_atom(entity),
          byte_start: start,
          byte_end: finish,
          score: prediction["score"],
          source_entity: prediction["source_entity"],
          metadata: %{}
        }

        {:cont, {:ok, [span | normalized]}}
      else
        {:halt, {:error, :invalid_prediction}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  rescue
    ArgumentError -> {:error, :unknown_prediction_entity}
  end

  defp normalize_predictions(_predictions, _text, _allowed),
    do: {:error, :invalid_predictions}

  defp valid_span?(text, start, finish)
       when is_integer(start) and is_integer(finish) and start >= 0 and start < finish do
    finish <= byte_size(text)
  end

  defp valid_span?(_text, _start, _finish), do: false

  defp load_reference(path), do: read_json(path)

  defp validate_reference(reference, selection, predictions_path) do
    fingerprints = reference["fingerprints"] || %{}

    validate_checks([
      {reference["status"] == "complete", :incomplete_external_reference},
      {reference["adapter"] == "Presidio.AnalyzerEngine", :unexpected_external_adapter},
      {reference["gold_derived"] == false, :gold_derived_external_reference},
      {reference["predictions_sha256"] == sha256_file(predictions_path),
       :external_prediction_hash_mismatch},
      {fingerprints["dataset_sha256"] == get_in(selection, ["dataset", "sha256"]),
       :external_dataset_fingerprint_mismatch},
      {fingerprints["sample_ids_sha256"] ==
         get_in(selection, ["dataset", "sample_ids_sha256"]),
       :external_sample_id_fingerprint_mismatch},
      {fingerprints["entity_policy_sha256"] ==
         get_in(selection, ["entity_policy", "sha256"]),
       :external_entity_policy_fingerprint_mismatch},
      {fingerprints["scoring_sha256"] == get_in(selection, ["scoring", "sha256"]),
       :external_scoring_fingerprint_mismatch}
    ])
  end

  defp validate_obscura_report(report, selection) do
    dataset = report["dataset"] || %{}
    expected_dataset = selection["dataset"]
    expected_entities = get_in(selection, ["entity_policy", "entities"])

    validate_checks([
      {report["skip_reason"] in [nil, false], :skipped_obscura_comparison_report},
      {report["profile"] != "nlp", :gold_derived_obscura_comparison_report},
      {dataset["name"] == expected_dataset["name"], :obscura_dataset_name_mismatch},
      {dataset["sample_ids"] == expected_dataset["ordered_sample_ids"],
       :obscura_ordered_sample_ids_mismatch},
      {dataset["sample_count"] == expected_dataset["sample_count"],
       :obscura_sample_count_mismatch},
      {dataset["requested_entities"] == expected_entities, :obscura_entity_policy_mismatch},
      {is_map(report["metrics"]) and is_map(report["latency"]),
       :incomplete_obscura_comparison_report}
    ])
  end

  defp build_report(selection, reference, metrics, selection_path, predictions_path, opts) do
    latency = metrics["latency"]
    sample_count = get_in(selection, ["dataset", "sample_count"])

    elapsed_ms =
      Enum.reduce(read_jsonl!(predictions_path), 0, fn row, total ->
        total + row["latency_ms"]
      end)

    %{
      "run_id" => Keyword.fetch!(opts, :run_id),
      "phase" => "authoritative_presidio_comparison",
      "status" => "complete",
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "git_sha" => git_sha(),
      "adapter" => reference["adapter"],
      "profile" => "presidio_spacy_en_core_web_lg",
      "external_baseline" => true,
      "gold_derived" => false,
      "model" => reference["model"],
      "dependencies" => reference["dependencies"],
      "environment" => reference["environment"],
      "command" => reference["command"],
      "dataset" =>
        selection["dataset"]
        |> Map.put("requested_entities", get_in(selection, ["entity_policy", "entities"])),
      "comparison_protocol" => comparison_protocol(selection, selection_path),
      "entity_mapping" => selection["entity_policy"],
      "offset_mode" => %{
        "input" => "character",
        "internal" => "byte",
        "scoring" => "byte",
        "conversion" => "validated"
      },
      "metrics" => Map.drop(metrics, ["latency", "per_entity", "examples"]),
      "per_entity" => metrics["per_entity"],
      "latency" =>
        latency
        |> Map.put("median_ms", latency["p50_ms"])
        |> Map.put("throughput_samples_per_second", throughput(sample_count, elapsed_ms)),
      "runtime_backend" => reference["runtime_backend"],
      "limitations" => reference["limitations"],
      "artifacts" => %{
        "predictions_sha256" => sha256_file(predictions_path),
        "reference_report_sha256" => sha256_file(Keyword.fetch!(opts, :reference_report))
      }
    }
  end

  defp public_metrics(metrics) do
    metric_fields = [
      :precision,
      :recall,
      :f1,
      :f2,
      :true_positives,
      :false_positives,
      :false_negatives,
      :wrong_entity_type,
      :offset_mismatches,
      :unsupported_expected_spans,
      :total_expected_spans,
      :total_supported_expected_spans,
      :total_predicted_spans,
      :total_samples,
      :latency,
      :per_entity
    ]

    metrics
    |> Map.take(metric_fields)
    |> Map.put(:span_iou, Map.drop(metrics.span_iou, [:examples]))
  end

  defp comparison_protocol(selection, selection_path) do
    %{
      "id" => selection["protocol_id"],
      "selection_sha256" => sha256_file(selection_path),
      "protocol_sha256" => selection["protocol_sha256"],
      "sample_ids_sha256" => get_in(selection, ["dataset", "sample_ids_sha256"]),
      "entity_policy_sha256" => get_in(selection, ["entity_policy", "sha256"]),
      "scoring_sha256" => get_in(selection, ["scoring", "sha256"])
    }
  end

  defp markdown(report) do
    metrics = report["metrics"]
    latency = report["latency"]
    protocol = report["comparison_protocol"]

    """
    # Authoritative Presidio External Baseline

    - Run ID: #{report["run_id"]}
    - Dataset: #{get_in(report, ["dataset", "name"])}
    - Samples: #{get_in(report, ["dataset", "sample_count"])}
    - Protocol: #{protocol["id"]}
    - Sample ID fingerprint: `#{protocol["sample_ids_sha256"]}`
    - Entity policy fingerprint: `#{protocol["entity_policy_sha256"]}`
    - Scoring fingerprint: `#{protocol["scoring_sha256"]}`

    ## Accuracy

    | Metric | Value |
    | --- | ---: |
    | Precision | #{format_metric(metrics["precision"])} |
    | Recall | #{format_metric(metrics["recall"])} |
    | F1 | #{format_metric(metrics["f1"])} |
    | F2 | #{format_metric(metrics["f2"])} |
    | True positives | #{metrics["true_positives"]} |
    | False positives | #{metrics["false_positives"]} |
    | False negatives | #{metrics["false_negatives"]} |
    | Wrong entity type | #{metrics["wrong_entity_type"]} |
    | Offset mismatches | #{metrics["offset_mismatches"]} |
    | Unsupported expected spans | #{metrics["unsupported_expected_spans"]} |
    | IoU F1 | #{format_metric(get_in(metrics, ["span_iou", "f1"]))} |

    ## Latency

    | Metric | Value |
    | --- | ---: |
    | Mean | #{format_ms(latency["mean_ms"])} |
    | Median | #{format_ms(latency["median_ms"])} |
    | P95 | #{format_ms(latency["p95_ms"])} |
    | Throughput | #{format_metric(latency["throughput_samples_per_second"])} samples/s |

    ## Limitations

    #{Enum.map_join(report["limitations"], "\n", &"- #{&1}")}
    """
  end

  defp entity_atoms(selection) do
    selection
    |> get_in(["entity_policy", "entities"])
    |> Enum.map(&String.to_existing_atom/1)
  end

  defp dataset_atom(name) when is_binary(name) do
    case Enum.find(PresidioResearchLoader.known_datasets(), &(Atom.to_string(&1) == name)) do
      nil -> {:error, {:unknown_comparison_dataset, name}}
      dataset -> {:ok, dataset}
    end
  end

  defp split_atom("all"), do: {:ok, :all}
  defp split_atom("template_train"), do: {:ok, :template_train}
  defp split_atom("template_heldout"), do: {:ok, :template_heldout}
  defp split_atom(other), do: {:error, {:unknown_comparison_split, other}}

  defp split_atom!(split) do
    {:ok, atom} = split_atom(split)
    atom
  end

  defp read_json(path) do
    case File.read(path) do
      {:ok, body} -> Jason.decode(body)
      error -> error
    end
  end

  defp read_jsonl(path) do
    with {:ok, body} <- File.read(path) do
      body
      |> String.split("\n", trim: true)
      |> Enum.reduce_while({:ok, []}, &decode_jsonl_line/2)
      |> case do
        {:ok, rows} -> {:ok, Enum.reverse(rows)}
        error -> error
      end
    end
  end

  defp decode_jsonl_line(line, {:ok, rows}) do
    case Jason.decode(line) do
      {:ok, row} -> {:cont, {:ok, [row | rows]}}
      {:error, reason} -> {:halt, {:error, {:invalid_prediction_jsonl, reason}}}
    end
  end

  defp validate_checks(checks) do
    Enum.find_value(checks, :ok, fn
      {true, _reason} -> false
      {false, reason} -> {:error, reason}
    end)
  end

  defp read_jsonl!(path) do
    {:ok, rows} = read_jsonl(path)
    rows
  end

  defp canonical(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, nested} -> {to_string(key), canonical(nested)} end)
  end

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value

  defp stringify(value) do
    value
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp relative_path(path), do: Path.relative_to(Path.expand(path), File.cwd!())

  defp sha256_file(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp file_hash_matches?(path, expected) do
    File.regular?(path) and sha256_file(path) == expected
  end

  defp sha256_binary(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end

  defp git_sha do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _other -> "unknown"
    end
  end

  defp throughput(0, _elapsed), do: 0.0
  defp throughput(_count, elapsed_ms) when elapsed_ms == 0, do: 0.0
  defp throughput(count, elapsed_ms), do: count / (elapsed_ms / 1_000)

  defp format_metric(nil), do: "n/a"

  defp format_metric(value) when is_number(value),
    do: :erlang.float_to_binary(value / 1, decimals: 4)

  defp format_ms(value), do: "#{format_metric(value)}ms"
end
