defmodule Obscura.Eval.Report do
  @moduledoc """
  JSON and Markdown report generation for Phase 0 runs.
  """

  alias Obscura.Eval.EntityMapping
  alias Obscura.Eval.Profile
  alias Obscura.Eval.RuntimeMetadata

  @doc """
  Builds a normalized report map.
  """
  @spec build(keyword()) :: map()
  def build(opts) do
    profile = Keyword.get(opts, :profile, :regex_only)
    metrics = Keyword.fetch!(opts, :metrics)
    dataset = Keyword.fetch!(opts, :dataset)
    adapter = Keyword.get(opts, :adapter, "unknown")
    source_commit = Keyword.get(opts, :git_sha, git_sha())

    %{
      run_id: Keyword.get(opts, :run_id, "phase_0_smoke"),
      phase: Keyword.get(opts, :phase, "phase_0"),
      timestamp: Keyword.get_lazy(opts, :timestamp, &current_timestamp/0),
      git_sha: source_commit,
      source: %{
        source_commit: source_commit,
        dirty_worktree: Keyword.get_lazy(opts, :dirty_worktree, &dirty_worktree?/0)
      },
      dependencies: RuntimeMetadata.dependency_versions(),
      adapter: adapter,
      profile: Atom.to_string(profile),
      dataset: dataset,
      entity_mapping: %{
        version: "phase_0",
        supported_entities:
          profile |> Profile.supported_entities() |> Enum.map(&Atom.to_string/1),
        unsupported_entities:
          EntityMapping.rows()
          |> Enum.reject(&(&1.status == :phase_0_supported))
          |> Enum.map(&Atom.to_string(&1.obscura_entity))
          |> Enum.uniq()
          |> Enum.sort()
      },
      offset_mode:
        Keyword.get(opts, :offset_mode, %{
          input: "byte",
          internal: "byte",
          scoring: "byte",
          conversion: "validated"
        }),
      metrics:
        metrics
        |> Map.drop([:per_entity, :latency, :stage_latency, :examples])
        |> sanitize_value(),
      per_entity: stringify_entity_keys(Map.get(metrics, :per_entity, %{})),
      latency: Map.get(metrics, :latency, %{}),
      stage_latency: Map.get(metrics, :stage_latency, %{}),
      examples: metrics |> Map.get(:examples, %{}) |> sanitize_examples(),
      threshold_sweep: Keyword.get(opts, :threshold_sweep),
      skip_reason: Keyword.get(opts, :skip_reason),
      limitations: Keyword.get(opts, :limitations, [])
    }
  end

  defp current_timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp dirty_worktree? do
    case System.cmd("git", ["status", "--porcelain", "--untracked-files=no"],
           stderr_to_stdout: true
         ) do
      {"", 0} -> false
      {_output, 0} -> true
      _error -> true
    end
  end

  @doc """
  Writes JSON and Markdown report files for a report map.
  """
  @spec write_pair(map(), Path.t(), Path.t()) :: :ok | {:error, term()}
  def write_pair(report, json_path, markdown_path) do
    with :ok <- mkdir_parent(json_path),
         :ok <- mkdir_parent(markdown_path),
         :ok <- write_json(report, json_path) do
      write_markdown(report, markdown_path)
    end
  end

  @spec write_json(map(), Path.t()) :: :ok | {:error, term()}
  def write_json(report, path) do
    encoded = Jason.encode_to_iodata!(stringify(report), pretty: true)
    File.write(path, [encoded, ?\n])
  end

  @spec write_markdown(map(), Path.t()) :: :ok | {:error, term()}
  def write_markdown(report, path) do
    File.write(path, markdown(report))
  end

  @doc """
  Renders a short Markdown summary.
  """
  @spec markdown(map()) :: String.t()
  def markdown(report) do
    metrics = Map.fetch!(report, :metrics)
    dataset = Map.fetch!(report, :dataset)

    """
    # #{report.phase |> String.replace("_", " ") |> String.capitalize()} Evaluation Report

    - Run ID: #{report.run_id}
    - Adapter: #{report.adapter}
    - Profile: #{report.profile}
    - Dataset: #{dataset.name}
    - Samples: #{dataset.sample_count}

    ## Metrics

    ### Exact Span Metrics

    | Metric | Value |
    | --- | ---: |
    | Precision | #{format_metric(metrics.precision)} |
    | Recall | #{format_metric(metrics.recall)} |
    | F1 | #{format_metric(metrics.f1)} |
    | F2 | #{format_metric(metrics.f2)} |
    | True positives | #{metrics.true_positives} |
    | False positives | #{metrics.false_positives} |
    | False negatives | #{metrics.false_negatives} |
    | Offset mismatches | #{metrics.offset_mismatches} |
    | Wrong entity type | #{metrics.wrong_entity_type} |
    | Unsupported expected spans | #{metrics.unsupported_expected_spans} |

    #{template_split_markdown(Map.get(dataset, :template_split))}

    #{span_iou_markdown(metrics)}

    #{span_normalization_markdown(metrics)}

    #{error_bucket_markdown(metrics)}

    #{error_signature_markdown(Map.get(metrics, :error_signatures, %{}))}

    #{model_label_error_markdown(Map.get(metrics, :model_label_errors, %{}))}

    #{actionable_error_markdown(Map.get(metrics, :actionable_errors, %{}))}

    #{model_error_markdown(Map.get(metrics, :model_errors, []))}

    #{per_template_markdown(Map.get(metrics, :per_template, %{}))}

    #{threshold_sweep_markdown(Map.get(report, :threshold_sweep))}

    #{example_markdown(Map.get(report, :examples, %{}))}

    ## Limitations

    #{limitation_lines(report.limitations)}
    """
  end

  defp mkdir_parent(path), do: path |> Path.dirname() |> File.mkdir_p()

  defp stringify(%{} = map) do
    Map.new(map, fn {key, value} -> {string_key(key), stringify(value)} end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> stringify()
  defp stringify(nil), do: nil
  defp stringify(true), do: true
  defp stringify(false), do: false
  defp stringify(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp stringify(value), do: value

  defp stringify_entity_keys(map) do
    Map.new(map, fn {entity, value} -> {Atom.to_string(entity), value} end)
  end

  defp sanitize_examples(%{} = examples), do: sanitize_value(examples)

  defp sanitize_value(%{} = map) do
    Map.new(map, fn
      {key, _value} when key in [:value, "value", :text, "text"] -> {key, "[omitted]"}
      {key, value} -> {key, sanitize_value(value)}
    end)
  end

  defp sanitize_value(list) when is_list(list), do: Enum.map(list, &sanitize_value/1)

  defp sanitize_value(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> sanitize_value()

  defp sanitize_value(value), do: value

  defp string_key(key) when is_atom(key), do: Atom.to_string(key)
  defp string_key(key), do: key

  defp format_metric(nil), do: "n/a"
  defp format_metric(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 4)
  defp format_metric(value), do: to_string(value)

  defp span_iou_markdown(%{span_iou: span_iou}) do
    """
    ### IoU Span Metrics

    | Metric | Value |
    | --- | ---: |
    | IoU threshold | #{format_metric(span_iou.iou_threshold)} |
    | Precision | #{format_metric(span_iou.precision)} |
    | Recall | #{format_metric(span_iou.recall)} |
    | F1 | #{format_metric(span_iou.f1)} |
    | F2 | #{format_metric(span_iou.f2)} |
    | True positives | #{span_iou.true_positives} |
    | False positives | #{span_iou.false_positives} |
    | False negatives | #{span_iou.false_negatives} |
    | Wrong entity type | #{span_iou.wrong_entity_type} |
    """
  end

  defp span_iou_markdown(_metrics), do: ""

  defp span_normalization_markdown(%{span_normalization: normalization}) do
    span_iou = Map.get(normalization, :span_iou, %{})

    """
    ### Normalized Span Diagnostics

    | Metric | Value |
    | --- | ---: |
    | Mode | #{Map.get(normalization, :mode)} |
    | Expected adjacent merges | #{Map.get(normalization, :expected_merge_count, 0)} |
    | Predicted adjacent merges | #{Map.get(normalization, :predicted_merge_count, 0)} |
    | Normalized IoU precision | #{format_metric(Map.get(span_iou, :precision))} |
    | Normalized IoU recall | #{format_metric(Map.get(span_iou, :recall))} |
    | Normalized IoU F1 | #{format_metric(Map.get(span_iou, :f1))} |
    """
  end

  defp span_normalization_markdown(_metrics), do: ""

  defp template_split_markdown(nil), do: ""

  defp template_split_markdown(%{name: :all}), do: ""

  defp template_split_markdown(split) do
    """
    ### Template Split

    | Field | Value |
    | --- | ---: |
    | Split | #{Map.get(split, :name)} |
    | Strategy | #{Map.get(split, :strategy)} |
    | Train ratio | #{format_metric(Map.get(split, :train_ratio))} |
    | Total templates | #{Map.get(split, :template_count, 0)} |
    | Selected templates | #{Map.get(split, :selected_template_count, 0)} |
    | Heldout templates | #{Map.get(split, :heldout_template_count, 0)} |
    """
  end

  defp error_bucket_markdown(%{error_buckets: buckets} = metrics) do
    """
    ### Error Buckets

    #{bucket_table("False positives", Map.get(buckets, :false_positives, %{}))}
    #{bucket_table("False negatives", Map.get(buckets, :false_negatives, %{}))}
    #{bucket_table("Wrong entity type", Map.get(buckets, :wrong_entity_type, %{}))}
    #{wrong_entity_matrix_markdown(Map.get(metrics, :wrong_entity_matrix, %{}))}
    """
  end

  defp error_bucket_markdown(_metrics), do: ""

  defp error_signature_markdown(nil), do: ""
  defp error_signature_markdown(signatures) when map_size(signatures) == 0, do: ""

  defp error_signature_markdown(signatures) do
    """
    ### Top Sanitized Error Signatures

    #{signature_table("False positives", Map.get(signatures, :false_positives, []))}
    #{signature_table("False negatives", Map.get(signatures, :false_negatives, []))}
    """
  end

  defp model_label_error_markdown(nil), do: ""
  defp model_label_error_markdown(groups) when map_size(groups) == 0, do: ""

  defp model_label_error_markdown(groups) do
    """
    ### Model Label Error Analysis

    #{model_label_error_table("False positives by model label", Map.get(groups, :false_positives, %{}))}
    #{model_label_error_table("False negatives by expected entity", Map.get(groups, :false_negatives, %{}))}
    #{model_label_error_table("Offset mismatches by model label", Map.get(groups, :offset_mismatches, %{}))}
    #{model_label_error_table("Wrong entity type by model label", Map.get(groups, :wrong_entity_type, %{}))}
    """
  end

  defp model_label_error_table(title, groups) when map_size(groups) == 0,
    do: "#### #{title}\n\nNo entries.\n"

  defp model_label_error_table(title, groups) do
    rows =
      groups
      |> Enum.sort_by(fn {label, group} -> {-Map.get(group, :count, 0), to_string(label)} end)
      |> Enum.take(10)
      |> Enum.map_join("\n", fn {label, group} ->
        "| #{label} | #{Map.get(group, :count, 0)} | #{format_count_map(Map.get(group, :entities, %{}))} | #{format_count_map(Map.get(group, :templates, %{}))} |"
      end)

    """
    #### #{title}

    | Label | Count | Entities | Top templates |
    | --- | ---: | --- | --- |
    #{rows}
    """
  end

  defp actionable_error_markdown(nil), do: ""
  defp actionable_error_markdown(groups) when map_size(groups) == 0, do: ""

  defp actionable_error_markdown(groups) do
    """
    ### Actionable Error Rows

    Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

    #{actionable_error_table("Top false positives by model label", Map.get(groups, :top_false_positive_tokens_by_model_label, []))}
    #{actionable_error_table("Top false negatives by expected entity", Map.get(groups, :top_false_negative_tokens_by_expected_entity, []))}
    #{actionable_error_table("Location false positives by GPE/FAC/LOC model label", Map.get(groups, :location_false_positives_by_model_label, []))}
    #{actionable_error_table("Location false negatives by template/context", Map.get(groups, :location_false_negatives_by_template_context, []))}
    #{actionable_error_table("Organization false negatives by template/context", Map.get(groups, :organization_false_negatives_by_template_context, []))}
    #{actionable_error_table("Offset mismatch rows", Map.get(groups, :offset_mismatch_rows, []))}
    #{actionable_error_table("Wrong entity type rows", Map.get(groups, :wrong_entity_type_rows, []))}
    """
  end

  defp actionable_error_table(title, []), do: "#### #{title}\n\nNo entries.\n"

  defp actionable_error_table(title, rows) do
    rows =
      rows
      |> Enum.take(10)
      |> Enum.map_join("\n", fn row ->
        "| #{Map.get(row, :label)} | #{Map.get(row, :source_label, :none)} | #{Map.get(row, :entity)} | #{Map.get(row, :token_shape)} | #{Map.get(row, :score_bucket)} | #{Map.get(row, :context_state)} | #{Map.get(row, :boundary_state)} | #{format_list(Map.get(row, :sample_ids, []))} | #{format_list(Map.get(row, :template_ids, []))} | #{Map.get(row, :count, 0)} |"
      end)

    """
    #### #{title}

    | Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
    #{rows}
    """
  end

  defp model_error_markdown(nil), do: ""
  defp model_error_markdown([]), do: ""

  defp model_error_markdown(rows) do
    """
    ### Structured Model Error Rows

    Values are sanitized; rows include Presidio-Research-style error context for tuning.

    #{model_error_table(rows)}
    """
  end

  defp model_error_table(rows) do
    rows =
      rows
      |> Enum.take(20)
      |> Enum.map_join("\n", fn row ->
        "| #{format_value(Map.get(row, :error_type))} | #{format_value(Map.get(row, :annotation))} | #{format_value(Map.get(row, :prediction))} | #{format_value(Map.get(row, :entity))} | #{format_value(Map.get(row, :model_label))} | #{format_value(Map.get(row, :token_shape))} | #{format_value(Map.get(row, :score_bucket))} | #{format_value(Map.get(row, :context_state))} | #{format_value(Map.get(row, :boundary_state))} | #{format_value(Map.get(row, :parser_state))} | #{format_value(Map.get(row, :conflict_state))} | #{format_value(Map.get(row, :sample_id))} | #{format_value(Map.get(row, :template_id))} | #{format_metric(Map.get(row, :iou))} | #{format_value(Map.get(row, :explanation))} |"
      end)

    """
    | Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
    #{rows}
    """
  end

  defp signature_table(title, []), do: "#### #{title}\n\nNo entries.\n"

  defp signature_table(title, rows) do
    rows =
      rows
      |> Enum.take(10)
      |> Enum.map_join("\n", fn row ->
        "| #{Map.get(row, :entity)} | #{Map.get(row, :source_entity)} | #{Map.get(row, :recognizer)} | #{Map.get(row, :model_label)} | #{Map.get(row, :template_id)} | #{Map.get(row, :length_bucket)} | #{Map.get(row, :likely_cause)} | #{Map.get(row, :count, 0)} |"
      end)

    """
    #### #{title}

    | Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
    | --- | --- | --- | --- | --- | --- | --- | ---: |
    #{rows}
    """
  end

  defp per_template_markdown(nil), do: ""
  defp per_template_markdown(per_template) when map_size(per_template) == 0, do: ""

  defp per_template_markdown(per_template) do
    rows =
      per_template
      |> Enum.sort_by(fn {template_id, metrics} ->
        {metric_sort_value(Map.get(metrics, :f1)), metric_sort_value(Map.get(metrics, :recall)),
         to_string(template_id)}
      end)
      |> Enum.take(15)
      |> Enum.map_join("\n", fn {template_id, metrics} ->
        "| #{template_id} | #{Map.get(metrics, :sample_count, Map.get(metrics, :total_samples, 0))} | #{format_metric(Map.get(metrics, :precision))} | #{format_metric(Map.get(metrics, :recall))} | #{format_metric(Map.get(metrics, :f1))} | #{format_metric(Map.get(metrics, :f2))} | #{Map.get(metrics, :true_positives, 0)} | #{Map.get(metrics, :false_positives, 0)} | #{Map.get(metrics, :false_negatives, 0)} |"
      end)

    """
    ### Worst Per-Template Metrics

    | Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
    | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    #{rows}
    """
  end

  defp threshold_sweep_markdown(nil), do: ""

  defp threshold_sweep_markdown(%{mode: :policy, rows: rows, best: best} = sweep)
       when is_list(rows) do
    """
    ### Policy Sweep

    Selection objective: #{Map.get(sweep, :selection_objective, :global_f1_under_fp_cap)}.

    Best row: #{Map.get(best, :policy_name)}, F1 #{format_metric(Map.get(best, :f1))}, recall #{format_metric(Map.get(best, :recall))}, precision #{format_metric(Map.get(best, :precision))}.

    #{policy_rows_markdown(rows)}
    """
  end

  defp threshold_sweep_markdown(%{rows: rows, best: best}) when is_list(rows) do
    """
    ### Threshold Sweep

    Best row: threshold #{format_metric(Map.get(best, :score_threshold))}, F1 #{format_metric(Map.get(best, :f1))}, recall #{format_metric(Map.get(best, :recall))}, precision #{format_metric(Map.get(best, :precision))}.

    #{threshold_rows_markdown(rows)}
    """
  end

  defp threshold_sweep_markdown(_sweep), do: ""

  defp policy_rows_markdown(rows) do
    rows =
      rows
      |> Enum.map_join("\n", fn row ->
        "| #{Map.get(row, :policy_name)} | #{format_list(Map.get(row, :model_postprocessors, []))} | #{model_chunking(row)} | #{Map.get(row, :boundary_normalization, :none)} | #{format_metric(Map.get(row, :precision))} | #{format_metric(Map.get(row, :recall))} | #{format_metric(Map.get(row, :f1))} | #{format_metric(Map.get(row, :f2))} | #{Map.get(row, :true_positives, 0)} | #{Map.get(row, :false_positives, 0)} | #{Map.get(row, :false_negatives, 0)} | #{nested_count(row, :location, :false_positives)} | #{nested_count(row, :location, :false_negatives)} | #{format_metric(nested_metric(row, :location, :f1))} | #{nested_count(row, :organization, :false_positives)} | #{nested_count(row, :organization, :false_negatives)} | #{format_metric(nested_metric(row, :organization, :f1))} | #{model_label_fp(row, "GPE")} | #{model_label_fp(row, "FAC")} | #{model_label_fp(row, "LOC")} | #{model_label_fp(row, "ORG")} | #{model_label_fp(row, "PERSON")} | #{format_metric(nested_metric(row, :delta_from_baseline, [:global, :f1]))} | #{nested_count(row, :delta_from_baseline, [:location, :false_negatives])} | #{nested_count(row, :delta_from_baseline, [:organization, :false_negatives])} |"
      end)

    """
    | Policy | Postprocessors | Chunking | Boundary | Precision | Recall | F1 | F2 | TP | FP | FN | Loc FP | Loc FN | Loc F1 | Org FP | Org FN | Org F1 | GPE FP | FAC FP | LOC FP | ORG FP | PERSON FP | dF1 | dLoc FN | dOrg FN |
    | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    #{rows}
    """
  end

  defp model_chunking(row) do
    case Map.get(row, :model_chunking, :none) do
      :none ->
        "none"

      "none" ->
        "none"

      mode ->
        "#{mode}:#{Map.get(row, :model_chunk_size, 400)}/#{Map.get(row, :model_chunk_overlap, 40)}"
    end
  end

  defp nested_metric(row, key, path) when is_atom(path) do
    row
    |> Map.get(key, %{})
    |> Map.get(path)
  end

  defp nested_metric(row, key, path) when is_list(path) do
    get_in(row, [key | path])
  end

  defp nested_count(row, key, path) when is_atom(path),
    do: nested_metric(row, key, path) || 0

  defp nested_count(row, key, path) when is_list(path), do: nested_metric(row, key, path) || 0

  defp model_label_fp(row, label) do
    row
    |> Map.get(:model_label_false_positives, %{})
    |> Map.get(label, 0)
  end

  defp threshold_rows_markdown(rows) do
    rows =
      rows
      |> Enum.map_join("\n", fn row ->
        "| #{format_metric(Map.get(row, :score_threshold))} | #{format_thresholds(Map.get(row, :per_entity_thresholds, %{}))} | #{format_metric(Map.get(row, :precision))} | #{format_metric(Map.get(row, :recall))} | #{format_metric(Map.get(row, :f1))} | #{format_metric(Map.get(row, :f2))} | #{Map.get(row, :true_positives, 0)} | #{Map.get(row, :false_positives, 0)} | #{Map.get(row, :false_negatives, 0)} | #{Map.get(row, :offset_mismatches, 0)} | #{Map.get(row, :wrong_entity_type, 0)} | #{Map.get(row, :unsupported_expected_spans, 0)} |"
      end)

    """
    | Threshold | Per-entity thresholds | Precision | Recall | F1 | F2 | TP | FP | FN | Offsets | Wrong | Unsupported |
    | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    #{rows}
    """
  end

  defp format_thresholds(thresholds) when map_size(thresholds) == 0, do: "n/a"

  defp format_thresholds(thresholds) do
    thresholds
    |> Enum.sort_by(fn {entity, _threshold} -> to_string(entity) end)
    |> Enum.map_join(", ", fn {entity, threshold} -> "#{entity}=#{format_metric(threshold)}" end)
  end

  defp metric_sort_value(nil), do: 2.0
  defp metric_sort_value(value), do: value

  defp bucket_table(title, buckets) when map_size(buckets) == 0 do
    """
    #### #{title}

    No entries.
    """
  end

  defp bucket_table(title, buckets) do
    rows =
      buckets
      |> Enum.sort_by(fn {entity, bucket} -> {-Map.get(bucket, :count, 0), to_string(entity)} end)
      |> Enum.take(10)
      |> Enum.map_join("\n", fn {entity, bucket} ->
        "| #{entity} | #{Map.get(bucket, :count, 0)} | #{format_causes(bucket)} |"
      end)

    """
    #### #{title}

    | Entity | Count | Likely causes |
    | --- | ---: | --- |
    #{rows}
    """
  end

  defp wrong_entity_matrix_markdown(matrix) when map_size(matrix) == 0 do
    """
    #### Wrong Entity Matrix

    No entries.
    """
  end

  defp wrong_entity_matrix_markdown(matrix) do
    rows =
      matrix
      |> Enum.flat_map(fn {expected, predictions} ->
        Enum.map(predictions, fn {predicted, count} ->
          {expected, predicted, count}
        end)
      end)
      |> Enum.sort_by(fn {expected, predicted, count} ->
        {-count, to_string(expected), to_string(predicted)}
      end)
      |> Enum.take(10)
      |> Enum.map_join("\n", fn {expected, predicted, count} ->
        "| #{expected} | #{predicted} | #{count} |"
      end)

    """
    #### Wrong Entity Matrix

    | Expected | Predicted | Count |
    | --- | --- | ---: |
    #{rows}
    """
  end

  defp format_causes(bucket) do
    bucket
    |> Map.get(:likely_causes, %{})
    |> Enum.sort_by(fn {cause, count} -> {-count, to_string(cause)} end)
    |> Enum.take(3)
    |> Enum.map_join(", ", fn {cause, count} -> "#{cause}: #{count}" end)
    |> case do
      "" -> "n/a"
      value -> value
    end
  end

  defp format_count_map(map) when map_size(map) == 0, do: "n/a"

  defp format_count_map(map) do
    map
    |> Enum.sort_by(fn {key, count} -> {-count, to_string(key)} end)
    |> Enum.take(5)
    |> Enum.map_join(", ", fn {key, count} -> "#{key}: #{count}" end)
  end

  defp format_list([]), do: "n/a"
  defp format_list(values), do: Enum.map_join(values, ", ", &to_string/1)

  defp format_value(nil), do: "n/a"
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> format_value()

  defp format_value(values) when is_list(values) do
    values
    |> Enum.map_join("/", &format_value/1)
  end

  defp format_value(%{} = map), do: inspect(map)

  defp format_value(value) when is_binary(value) do
    value
    |> String.replace("|", "\\|")
    |> String.replace("\n", " ")
  end

  defp format_value(value), do: to_string(value)

  defp example_markdown(nil), do: ""
  defp example_markdown(examples) when map_size(examples) == 0, do: ""

  defp example_markdown(examples) do
    """
    ### Example Errors

    #{example_table("False positives", Map.get(examples, :false_positives, []))}
    #{example_table("False negatives", Map.get(examples, :false_negatives, []))}
    #{example_table("Offset mismatches", Map.get(examples, :offset_mismatches, []))}
    #{example_table("Wrong entity type", Map.get(examples, :wrong_entity_type, []))}
    """
  end

  defp example_table(title, []), do: "#### #{title}\n\nNo examples.\n"

  defp example_table(title, examples) do
    rows =
      examples
      |> Enum.take(5)
      |> Enum.map_join("\n", fn example ->
        "| #{example_entity(example)} | #{example_start(example)} | #{example_end(example)} | #{example_recognizer(example)} | #{example_source_entity(example)} |"
      end)

    """
    #### #{title}

    | Entity | Start | End | Recognizer | Source entity |
    | --- | ---: | ---: | --- | --- |
    #{rows}
    """
  end

  defp example_entity([expected, predicted]),
    do: "#{Map.get(expected, :entity)}/#{Map.get(predicted, :entity)}"

  defp example_entity(example), do: Map.get(example, :entity, "n/a")

  defp example_start([expected, predicted]),
    do:
      "#{Map.get(expected, :byte_start, Map.get(expected, :start))}/#{Map.get(predicted, :byte_start, Map.get(predicted, :start))}"

  defp example_start(example), do: Map.get(example, :byte_start, Map.get(example, :start, "n/a"))

  defp example_end([expected, predicted]),
    do:
      "#{Map.get(expected, :byte_end, Map.get(expected, :end))}/#{Map.get(predicted, :byte_end, Map.get(predicted, :end))}"

  defp example_end(example), do: Map.get(example, :byte_end, Map.get(example, :end, "n/a"))

  defp example_recognizer([_expected, predicted]), do: Map.get(predicted, :recognizer, "n/a")
  defp example_recognizer(example), do: Map.get(example, :recognizer, "n/a")

  defp example_source_entity([expected, predicted]),
    do: "#{Map.get(expected, :source_entity, "n/a")}/#{Map.get(predicted, :source_entity, "n/a")}"

  defp example_source_entity(example), do: Map.get(example, :source_entity, "n/a")

  defp limitation_lines([]), do: "- None recorded.\n"

  defp limitation_lines(limitations) do
    limitations
    |> Enum.map_join("\n", &"- #{&1}")
    |> Kernel.<>("\n")
  end

  defp git_sha do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _other -> "unknown"
    end
  rescue
    _error -> "unknown"
  end
end
