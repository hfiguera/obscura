defmodule Obscura.Eval.Metrics do
  @moduledoc """
  Exact-span metrics for Phase 0 fixture and benchmark reports.
  """

  alias Obscura.Eval.Profile

  @empty_examples %{
    false_positives: [],
    false_negatives: [],
    offset_mismatches: [],
    wrong_entity_type: [],
    unsupported: []
  }

  @doc """
  Scores expected spans against predicted spans for a profile.
  """
  @spec score([map()], [map()], atom(), keyword()) :: map()
  def score(expected, predicted, profile, opts \\ [])
      when is_list(expected) and is_list(predicted) and is_atom(profile) do
    latency_ms = Keyword.get(opts, :latency_ms, [])
    split = split_spans(expected, profile, Keyword.get(opts, :supported_entities))
    supported_expected = split.supported
    unsupported_expected = split.unsupported

    {true_positives, remaining_expected, remaining_predicted} =
      match_exact(supported_expected, predicted, [])

    {offset_mismatches, remaining_expected, remaining_predicted} =
      match_offset_mismatch(remaining_expected, remaining_predicted, [])

    {wrong_entity_type, remaining_expected, remaining_predicted} =
      match_wrong_entity(remaining_expected, remaining_predicted, [])

    false_negatives = remaining_expected
    false_positives = remaining_predicted

    per_entity = per_entity_metrics(supported_expected, predicted)

    counts = %{
      true_positives: length(true_positives),
      false_positives: length(false_positives),
      false_negatives: length(false_negatives),
      offset_mismatches: length(offset_mismatches),
      wrong_entity_type: length(wrong_entity_type),
      unsupported_expected_spans: length(unsupported_expected),
      total_expected_spans: length(expected),
      total_supported_expected_spans: length(supported_expected),
      total_predicted_spans: length(predicted),
      total_samples: Keyword.get(opts, :total_samples, 1)
    }

    counts
    |> Map.merge(ratios(counts))
    |> Map.put(:span_iou, score_iou(supported_expected, predicted, opts))
    |> Map.put(:span_normalization, span_normalization(supported_expected, predicted, opts))
    |> Map.put(:per_entity, per_entity)
    |> Map.put(:latency, latency_summary(latency_ms))
    |> Map.put(
      :error_buckets,
      error_buckets(
        false_positives,
        false_negatives,
        offset_mismatches,
        wrong_entity_type,
        unsupported_expected
      )
    )
    |> Map.put(:wrong_entity_matrix, wrong_entity_matrix(wrong_entity_type))
    |> Map.put(
      :error_signatures,
      error_signatures(false_positives, false_negatives)
    )
    |> Map.put(
      :model_label_errors,
      model_label_errors(false_positives, false_negatives, offset_mismatches, wrong_entity_type)
    )
    |> Map.put(
      :actionable_errors,
      actionable_errors(false_positives, false_negatives, offset_mismatches, wrong_entity_type)
    )
    |> Map.put(
      :model_errors,
      model_errors(false_positives, false_negatives, offset_mismatches, wrong_entity_type)
    )
    |> Map.put(
      :examples,
      examples(
        false_positives,
        false_negatives,
        offset_mismatches,
        wrong_entity_type,
        unsupported_expected
      )
    )
  end

  @doc """
  Scores runner result maps that include `:expected`, `:predicted`, and `:latency_ms`.
  """
  @spec score_results([map()], atom(), keyword()) :: map()
  def score_results(results, profile, opts \\ []) when is_list(results) and is_atom(profile) do
    latency = Enum.map(results, & &1.latency_ms)
    stage_latency = results |> Enum.map(&Map.get(&1, :stage_latency_ms)) |> Enum.reject(&is_nil/1)

    scores =
      Enum.map(results, fn result ->
        score(
          result.expected,
          result.predicted,
          profile,
          Keyword.put(opts, :sample_text, sample_text(result))
        )
      end)

    scores
    |> aggregate_scores(length(results), latency, stage_latency)
    |> Map.put(:per_template, per_template_metrics(results, profile, opts))
  end

  defp split_spans(expected, profile, nil), do: Profile.split_spans(expected, profile)

  defp split_spans(expected, _profile, supported_entities) when is_list(supported_entities) do
    supported_entities = MapSet.new(supported_entities)

    Enum.reduce(expected, %{supported: [], unsupported: []}, fn span, acc ->
      if span |> Map.fetch!(:entity) |> then(&MapSet.member?(supported_entities, &1)) do
        %{acc | supported: [span | acc.supported]}
      else
        %{acc | unsupported: [span | acc.unsupported]}
      end
    end)
    |> then(fn acc ->
      %{supported: Enum.reverse(acc.supported), unsupported: Enum.reverse(acc.unsupported)}
    end)
  end

  @doc """
  Returns precision, recall, F1, and F2 for count maps.
  """
  @spec ratios(map()) :: map()
  def ratios(counts) when is_map(counts) do
    tp = Map.get(counts, :true_positives, 0)
    fp = Map.get(counts, :false_positives, 0)
    fn_count = Map.get(counts, :false_negatives, 0)

    precision = divide(tp, tp + fp)
    recall = divide(tp, tp + fn_count)

    %{
      precision: precision,
      recall: recall,
      f1: f_score(precision, recall, 1),
      f2: f_score(precision, recall, 2)
    }
  end

  @doc """
  Calculates byte-based intersection-over-union for two spans.
  """
  @spec iou(map(), map()) :: float()
  def iou(expected, predicted) do
    expected_start = Map.fetch!(expected, :byte_start)
    expected_end = Map.fetch!(expected, :byte_end)
    predicted_start = Map.fetch!(predicted, :byte_start)
    predicted_end = Map.fetch!(predicted, :byte_end)

    intersection = max(0, min(expected_end, predicted_end) - max(expected_start, predicted_start))
    union = max(expected_end, predicted_end) - min(expected_start, predicted_start)

    if union == 0, do: 0.0, else: intersection / union
  end

  defp match_exact(expected, predicted, matched) do
    Enum.reduce(expected, {matched, [], predicted}, fn expected_span,
                                                       {matched_acc, expected_acc, predicted_acc} ->
      case Enum.find_index(predicted_acc, &exact_match?(expected_span, &1)) do
        nil ->
          {matched_acc, [expected_span | expected_acc], predicted_acc}

        index ->
          {prediction, new_predicted_acc} = List.pop_at(predicted_acc, index)
          {[{expected_span, prediction} | matched_acc], expected_acc, new_predicted_acc}
      end
    end)
    |> then(fn {matched_acc, expected_acc, predicted_acc} ->
      {Enum.reverse(matched_acc), Enum.reverse(expected_acc), predicted_acc}
    end)
  end

  defp match_wrong_entity(expected, predicted, matched) do
    Enum.reduce(expected, {matched, [], predicted}, fn expected_span,
                                                       {matched_acc, expected_acc, predicted_acc} ->
      case Enum.find_index(predicted_acc, &wrong_entity_match?(expected_span, &1)) do
        nil ->
          {matched_acc, [expected_span | expected_acc], predicted_acc}

        index ->
          {prediction, new_predicted_acc} = List.pop_at(predicted_acc, index)
          {[{expected_span, prediction} | matched_acc], expected_acc, new_predicted_acc}
      end
    end)
    |> then(fn {matched_acc, expected_acc, predicted_acc} ->
      {Enum.reverse(matched_acc), Enum.reverse(expected_acc), predicted_acc}
    end)
  end

  defp match_offset_mismatch(expected, predicted, matched) do
    Enum.reduce(expected, {matched, [], predicted}, fn expected_span,
                                                       {matched_acc, expected_acc, predicted_acc} ->
      case Enum.find_index(predicted_acc, &offset_mismatch?(&1, expected_span)) do
        nil ->
          {matched_acc, [expected_span | expected_acc], predicted_acc}

        index ->
          {prediction, new_predicted_acc} = List.pop_at(predicted_acc, index)
          {[{expected_span, prediction} | matched_acc], expected_acc, new_predicted_acc}
      end
    end)
    |> then(fn {matched_acc, expected_acc, predicted_acc} ->
      {Enum.reverse(matched_acc), Enum.reverse(expected_acc), predicted_acc}
    end)
  end

  defp exact_match?(expected, predicted) do
    Map.get(expected, :entity) == Map.get(predicted, :entity) and
      Map.get(expected, :byte_start) == Map.get(predicted, :byte_start) and
      Map.get(expected, :byte_end) == Map.get(predicted, :byte_end)
  end

  defp wrong_entity_match?(expected, predicted) do
    Map.get(expected, :entity) != Map.get(predicted, :entity) and iou(expected, predicted) > 0.0
  end

  defp offset_mismatch?(predicted, expected) do
    Map.get(expected, :entity) == Map.get(predicted, :entity) and
      iou(expected, predicted) > 0.0 and
      not exact_match?(expected, predicted)
  end

  defp score_iou(expected, predicted, opts) do
    threshold = Keyword.get(opts, :iou_threshold, 0.9)

    {matches, wrong_entities, false_negatives, used_predictions} =
      Enum.reduce(expected, {[], [], [], MapSet.new()}, fn expected_span,
                                                           {matches_acc, wrong_acc, fn_acc,
                                                            used_acc} ->
        score_iou_span(
          expected_span,
          predicted,
          threshold,
          {matches_acc, wrong_acc, fn_acc, used_acc}
        )
      end)

    false_positives =
      Enum.reject(predicted, fn prediction ->
        MapSet.member?(used_predictions, prediction_key(prediction))
      end)

    counts = %{
      iou_threshold: threshold,
      true_positives: length(matches),
      false_positives: length(false_positives),
      false_negatives: length(false_negatives),
      wrong_entity_type: length(wrong_entities),
      total_supported_expected_spans: length(expected),
      total_predicted_spans: length(predicted),
      examples: %{
        false_positives: Enum.take(false_positives, 10),
        false_negatives: Enum.take(false_negatives, 10),
        wrong_entity_type: Enum.take(wrong_entities, 10)
      }
    }

    Map.merge(counts, ratios(counts))
  end

  defp span_normalization(expected, predicted, opts) do
    case Keyword.get(opts, :sample_text) do
      text when is_binary(text) and text != "" ->
        skip_words = Keyword.get(opts, :span_skip_words, default_span_skip_words())
        normalized_expected = merge_adjacent_spans(expected, text, skip_words)
        normalized_predicted = merge_adjacent_spans(predicted, text, skip_words)

        %{
          mode: :skip_word_adjacent,
          skip_words: skip_words,
          expected_merge_count: normalized_expected.merge_count,
          predicted_merge_count: normalized_predicted.merge_count,
          span_iou: score_iou(normalized_expected.spans, normalized_predicted.spans, opts)
        }

      _missing ->
        %{
          mode: :unavailable,
          reason: :missing_sample_text,
          expected_merge_count: 0,
          predicted_merge_count: 0,
          span_iou: score_iou(expected, predicted, opts)
        }
    end
  end

  defp default_span_skip_words, do: ~w[and at de del in la of the]

  defp merge_adjacent_spans(spans, text, skip_words) do
    sorted = Enum.sort_by(spans, &{Map.get(&1, :entity), Map.get(&1, :byte_start, 0)})

    {merged, merge_count} =
      Enum.reduce(sorted, {[], 0}, fn span, {acc, count} ->
        merge_adjacent_span(acc, count, span, text, skip_words)
      end)

    %{spans: Enum.reverse(merged), merge_count: merge_count}
  end

  defp merge_adjacent_span([previous | rest] = acc, count, span, text, skip_words) do
    if mergeable_adjacent_span?(previous, span, text, skip_words) do
      {[merge_spans(previous, span, text) | rest], count + 1}
    else
      {[span | acc], count}
    end
  end

  defp merge_adjacent_span([], count, span, _text, _skip_words), do: {[span], count}

  defp merge_spans(previous, span, text) do
    previous
    |> Map.put(:byte_end, Map.fetch!(span, :byte_end))
    |> Map.put(
      :text,
      merged_span_text(text, Map.fetch!(previous, :byte_start), Map.fetch!(span, :byte_end))
    )
  end

  defp mergeable_adjacent_span?(left, right, text, skip_words) do
    Map.get(left, :entity) == Map.get(right, :entity) and
      Map.fetch!(left, :byte_end) <= Map.fetch!(right, :byte_start) and
      skip_word_separator?(
        text,
        Map.fetch!(left, :byte_end),
        Map.fetch!(right, :byte_start),
        skip_words
      )
  end

  defp skip_word_separator?(text, start_byte, end_byte, skip_words) do
    separator =
      text
      |> binary_part(start_byte, end_byte - start_byte)
      |> String.downcase()
      |> String.trim()

    separator == "" or
      Regex.match?(~r/^[\s,.\-:;()]+$/u, separator) or
      separator
      |> String.split(~r/[\s,.\-:;()]+/u, trim: true)
      |> Enum.all?(&(&1 in skip_words))
  end

  defp merged_span_text(text, start_byte, end_byte),
    do: binary_part(text, start_byte, end_byte - start_byte)

  defp score_iou_span(expected_span, predicted, threshold, acc) do
    {matches_acc, wrong_acc, fn_acc, used_acc} = acc
    unused_predictions = unused_predictions(predicted, used_acc)

    expected_span
    |> best_iou_match(unused_predictions, true)
    |> case do
      {prediction, iou_score} when iou_score >= threshold ->
        {[{expected_span, prediction, iou_score} | matches_acc], wrong_acc, fn_acc,
         MapSet.put(used_acc, prediction_key(prediction))}

      _no_same_entity ->
        score_wrong_iou_span(expected_span, unused_predictions, threshold, acc)
    end
  end

  defp score_wrong_iou_span(expected_span, unused_predictions, threshold, acc) do
    {matches_acc, wrong_acc, fn_acc, used_acc} = acc

    expected_span
    |> best_iou_match(unused_predictions, false)
    |> case do
      {prediction, iou_score} when iou_score >= threshold ->
        {matches_acc, [{expected_span, prediction, iou_score} | wrong_acc], fn_acc,
         MapSet.put(used_acc, prediction_key(prediction))}

      _no_match ->
        {matches_acc, wrong_acc, [expected_span | fn_acc], used_acc}
    end
  end

  defp unused_predictions(predicted, used) do
    Enum.reject(predicted, &MapSet.member?(used, prediction_key(&1)))
  end

  defp best_iou_match(expected, predicted, same_entity?) do
    predicted
    |> Enum.filter(fn prediction ->
      same_entity? == (Map.get(expected, :entity) == Map.get(prediction, :entity))
    end)
    |> Enum.map(fn prediction -> {prediction, iou(expected, prediction)} end)
    |> Enum.max_by(fn {_prediction, iou_score} -> iou_score end, fn -> nil end)
  end

  defp prediction_key(prediction) do
    {Map.get(prediction, :entity), Map.get(prediction, :byte_start),
     Map.get(prediction, :byte_end)}
  end

  defp per_entity_metrics(expected, predicted) do
    entities =
      (Enum.map(expected, &Map.fetch!(&1, :entity)) ++
         Enum.map(predicted, &Map.fetch!(&1, :entity)))
      |> Enum.uniq()
      |> Enum.sort()

    Map.new(entities, fn entity ->
      expected_for_entity = Enum.filter(expected, &(Map.fetch!(&1, :entity) == entity))
      predicted_for_entity = Enum.filter(predicted, &(Map.fetch!(&1, :entity) == entity))
      metrics = score_entity(expected_for_entity, predicted_for_entity)
      {entity, metrics}
    end)
  end

  defp score_entity(expected, predicted) do
    {matches, remaining_expected, remaining_predicted} = match_exact(expected, predicted, [])

    {offset_mismatches, remaining_expected, remaining_predicted} =
      match_offset_mismatch(remaining_expected, remaining_predicted, [])

    counts = %{
      support_count: length(expected),
      prediction_count: length(predicted),
      true_positives: length(matches),
      false_positives: length(remaining_predicted),
      false_negatives: length(remaining_expected),
      offset_mismatches: length(offset_mismatches),
      wrong_entity_type: 0
    }

    Map.merge(counts, ratios(counts))
  end

  defp latency_summary([]), do: %{mean_ms: 0.0, p50_ms: 0.0, p95_ms: 0.0, max_ms: 0.0}

  defp latency_summary(values) do
    sorted = Enum.sort(values)

    {sum, count} =
      Enum.reduce(values, {0.0, 0}, fn value, {sum, count} -> {sum + value, count + 1} end)

    %{
      mean_ms: sum / count,
      p50_ms: percentile(sorted, 0.50),
      p95_ms: percentile(sorted, 0.95),
      max_ms: List.last(sorted)
    }
  end

  defp percentile(sorted, percentile) do
    index =
      ((length(sorted) - 1) * percentile)
      |> Float.ceil()
      |> trunc()

    Enum.at(sorted, index)
  end

  defp examples(
         false_positives,
         false_negatives,
         offset_mismatches,
         wrong_entity_type,
         unsupported
       ) do
    %{
      @empty_examples
      | false_positives: Enum.take(false_positives, 10),
        false_negatives: Enum.take(false_negatives, 10),
        offset_mismatches: Enum.take(offset_mismatches, 10),
        wrong_entity_type: Enum.take(wrong_entity_type, 10),
        unsupported: Enum.take(unsupported, 10)
    }
  end

  defp aggregate_scores(scores, total_samples, latency, stage_latency) do
    counts =
      Enum.reduce(scores, empty_counts(total_samples), fn score, acc ->
        %{
          acc
          | true_positives: acc.true_positives + score.true_positives,
            false_positives: acc.false_positives + score.false_positives,
            false_negatives: acc.false_negatives + score.false_negatives,
            offset_mismatches: acc.offset_mismatches + score.offset_mismatches,
            wrong_entity_type: acc.wrong_entity_type + score.wrong_entity_type,
            unsupported_expected_spans:
              acc.unsupported_expected_spans + score.unsupported_expected_spans,
            total_expected_spans: acc.total_expected_spans + score.total_expected_spans,
            total_supported_expected_spans:
              acc.total_supported_expected_spans + score.total_supported_expected_spans,
            total_predicted_spans: acc.total_predicted_spans + score.total_predicted_spans
        }
      end)

    counts
    |> Map.merge(ratios(counts))
    |> Map.put(:span_iou, aggregate_span_iou(scores))
    |> Map.put(:span_normalization, aggregate_span_normalization(scores))
    |> Map.put(:per_entity, aggregate_per_entity(scores))
    |> Map.put(:latency, latency_summary(latency))
    |> Map.put(:stage_latency, stage_latency_summary(stage_latency))
    |> Map.put(:error_buckets, aggregate_error_buckets(scores))
    |> Map.put(:wrong_entity_matrix, aggregate_wrong_entity_matrix(scores))
    |> Map.put(:error_signatures, aggregate_error_signatures(scores))
    |> Map.put(:model_label_errors, aggregate_model_label_errors(scores))
    |> Map.put(:actionable_errors, aggregate_actionable_errors(scores))
    |> Map.put(:model_errors, aggregate_model_errors(scores))
    |> Map.put(:examples, aggregate_examples(scores))
  end

  defp stage_latency_summary([]), do: %{}

  defp stage_latency_summary(rows) do
    rows
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Map.new(fn key ->
      values =
        rows
        |> Enum.map(&Map.get(&1, key))
        |> Enum.filter(&is_number/1)

      {key, latency_summary(values)}
    end)
  end

  defp empty_counts(total_samples) do
    %{
      true_positives: 0,
      false_positives: 0,
      false_negatives: 0,
      offset_mismatches: 0,
      wrong_entity_type: 0,
      unsupported_expected_spans: 0,
      total_expected_spans: 0,
      total_supported_expected_spans: 0,
      total_predicted_spans: 0,
      total_samples: total_samples
    }
  end

  defp aggregate_per_entity(scores) do
    scores
    |> Enum.flat_map(&Map.to_list(&1.per_entity))
    |> Enum.group_by(fn {entity, _metrics} -> entity end, fn {_entity, metrics} -> metrics end)
    |> Map.new(fn {entity, metrics} ->
      counts =
        Enum.reduce(metrics, empty_entity_counts(), fn metric, acc ->
          %{
            acc
            | support_count: acc.support_count + metric.support_count,
              prediction_count: acc.prediction_count + metric.prediction_count,
              true_positives: acc.true_positives + metric.true_positives,
              false_positives: acc.false_positives + metric.false_positives,
              false_negatives: acc.false_negatives + metric.false_negatives,
              offset_mismatches: acc.offset_mismatches + metric.offset_mismatches,
              wrong_entity_type: acc.wrong_entity_type + metric.wrong_entity_type
          }
        end)

      {entity, Map.merge(counts, ratios(counts))}
    end)
  end

  defp empty_entity_counts do
    %{
      support_count: 0,
      prediction_count: 0,
      true_positives: 0,
      false_positives: 0,
      false_negatives: 0,
      offset_mismatches: 0,
      wrong_entity_type: 0
    }
  end

  defp aggregate_examples(scores) do
    Map.new(@empty_examples, fn {key, _value} ->
      {key, scores |> Enum.flat_map(&Map.fetch!(&1.examples, key)) |> Enum.take(10)}
    end)
  end

  defp error_buckets(
         false_positives,
         false_negatives,
         offset_mismatches,
         wrong_entity_type,
         unsupported
       ) do
    %{
      false_positives: bucket_by_entity(false_positives, :false_positive),
      false_negatives: bucket_by_entity(false_negatives, :false_negative),
      offset_mismatches: bucket_pairs_by_entity(offset_mismatches, :offset_mismatch),
      wrong_entity_type: bucket_pairs_by_entity(wrong_entity_type, :wrong_entity_type),
      unsupported: bucket_by_entity(unsupported, :unsupported)
    }
  end

  defp bucket_by_entity(spans, error_type) do
    spans
    |> Enum.group_by(&Map.get(&1, :entity, :unknown))
    |> Map.new(fn {entity, entity_spans} ->
      {entity,
       %{
         count: length(entity_spans),
         likely_causes: likely_causes(entity_spans, error_type),
         examples: Enum.take(entity_spans, 5)
       }}
    end)
  end

  defp bucket_pairs_by_entity(pairs, error_type) do
    pairs
    |> Enum.group_by(fn {expected, _predicted} -> Map.get(expected, :entity, :unknown) end)
    |> Map.new(fn {entity, entity_pairs} ->
      {entity,
       %{
         count: length(entity_pairs),
         likely_causes: likely_causes(entity_pairs, error_type),
         examples: Enum.take(entity_pairs, 5)
       }}
    end)
  end

  defp likely_causes(items, error_type) do
    items
    |> Enum.map(&likely_cause(&1, error_type))
    |> Enum.frequencies()
  end

  defp likely_cause(span, :false_positive) when is_map(span) do
    metadata = Map.get(span, :metadata, %{}) || %{}
    entity = Map.get(span, :entity)

    cond do
      Map.has_key?(metadata, :model_label) and fragment_span?(span) ->
        :model_boundary_fragment

      Map.has_key?(metadata, :model_label) and entity in [:person, :location, :organization] ->
        :model_open_class_false_positive

      Map.has_key?(metadata, :model_label) ->
        :model_false_positive

      Map.get(span, :recognizer) in [:email, :phone, :url, :domain, :credit_card, :iban, :us_ssn] ->
        :structured_recognizer_false_positive

      true ->
        :false_positive
    end
  end

  defp likely_cause(span, :false_negative) when is_map(span) do
    case Map.get(span, :entity) do
      entity when entity in [:person, :location, :organization] -> :open_class_model_recall_gap
      :street_address -> :address_context_gap
      :date_time -> :date_time_pattern_gap
      :phone -> :phone_pattern_gap
      _entity -> :recognizer_recall_gap
    end
  end

  defp likely_cause({_expected, predicted}, :offset_mismatch) do
    metadata = Map.get(predicted, :metadata, %{}) || %{}

    if Map.has_key?(metadata, :model_label),
      do: :model_boundary_mismatch,
      else: :deterministic_boundary_mismatch
  end

  defp likely_cause({_expected, predicted}, :wrong_entity_type) do
    metadata = Map.get(predicted, :metadata, %{}) || %{}

    if Map.has_key?(metadata, :model_label),
      do: :model_label_confusion,
      else: :recognizer_label_confusion
  end

  defp likely_cause(_span, :unsupported), do: :profile_unsupported_entity

  defp fragment_span?(span) do
    byte_start = Map.get(span, :byte_start, Map.get(span, :start, 0))
    byte_end = Map.get(span, :byte_end, Map.get(span, :end, byte_start))

    byte_end - byte_start <= 2
  end

  defp error_signatures(false_positives, false_negatives) do
    %{
      false_positives: signature_rows(false_positives, :false_positive),
      false_negatives: signature_rows(false_negatives, :false_negative)
    }
  end

  defp model_label_errors(
         false_positives,
         false_negatives,
         offset_mismatches,
         wrong_entity_type
       ) do
    %{
      false_positives:
        spans_by_model_label(false_positives, [:entity, :recognizer, :template_id]),
      false_negatives: spans_by_entity(false_negatives),
      offset_mismatches:
        pairs_by_prediction_model_label(offset_mismatches, [:entity, :template_id]),
      wrong_entity_type:
        pairs_by_prediction_model_label(wrong_entity_type, [:entity, :template_id])
    }
  end

  defp actionable_errors(false_positives, false_negatives, offset_mismatches, wrong_entity_type) do
    %{
      top_false_positive_tokens_by_model_label:
        actionable_span_rows(false_positives, :model_label),
      top_false_negative_tokens_by_expected_entity:
        actionable_span_rows(false_negatives, :entity),
      location_false_positives_by_model_label:
        false_positives
        |> Enum.filter(&location_model_label_false_positive?/1)
        |> actionable_span_rows(:model_label),
      location_false_negatives_by_template_context:
        false_negatives
        |> Enum.filter(&(Map.get(&1, :entity) == :location))
        |> actionable_span_rows(:template_context),
      organization_false_negatives_by_template_context:
        false_negatives
        |> Enum.filter(&(Map.get(&1, :entity) == :organization))
        |> actionable_span_rows(:template_context),
      offset_mismatch_rows: actionable_pair_rows(offset_mismatches),
      wrong_entity_type_rows: actionable_pair_rows(wrong_entity_type)
    }
  end

  defp location_model_label_false_positive?(span) do
    Map.get(span, :entity) == :location and
      base_model_label(span_model_label(span)) in ["GPE", "LOC", "FAC"]
  end

  defp model_errors(false_positives, false_negatives, offset_mismatches, wrong_entity_type) do
    false_positive_errors(false_positives) ++
      false_negative_errors(false_negatives) ++
      offset_mismatch_errors(offset_mismatches) ++
      wrong_entity_errors(wrong_entity_type)
  end

  defp false_positive_errors(spans) do
    Enum.map(spans, fn span ->
      metadata = Map.get(span, :metadata, %{}) || %{}

      model_error_row(:FP,
        annotation: "O",
        prediction: Map.get(span, :entity, :unknown),
        span: span,
        metadata: metadata,
        explanation: "#{Map.get(span, :entity, :unknown)} falsely detected"
      )
    end)
  end

  defp false_negative_errors(spans) do
    Enum.map(spans, fn span ->
      metadata = Map.get(span, :metadata, %{}) || %{}

      model_error_row(:FN,
        annotation: Map.get(span, :entity, :unknown),
        prediction: "O",
        span: span,
        metadata: metadata,
        explanation: "#{Map.get(span, :entity, :unknown)} not detected"
      )
    end)
  end

  defp offset_mismatch_errors(pairs) do
    Enum.map(pairs, fn {expected, predicted} ->
      metadata = Map.get(predicted, :metadata, %{}) || %{}
      iou_score = iou(expected, predicted)

      model_error_row(:OffsetMismatch,
        annotation: Map.get(expected, :entity, :unknown),
        prediction: Map.get(predicted, :entity, :unknown),
        span: predicted,
        metadata: metadata,
        iou: iou_score,
        explanation: "same entity with low exact-span alignment; iou=#{format_iou(iou_score)}"
      )
    end)
  end

  defp wrong_entity_errors(pairs) do
    Enum.map(pairs, fn {expected, predicted} ->
      metadata = Map.get(predicted, :metadata, %{}) || %{}
      iou_score = iou(expected, predicted)

      model_error_row(:WrongEntity,
        annotation: Map.get(expected, :entity, :unknown),
        prediction: Map.get(predicted, :entity, :unknown),
        span: predicted,
        metadata: metadata,
        iou: iou_score,
        explanation:
          "#{Map.get(expected, :entity, :unknown)} detected as #{Map.get(predicted, :entity, :unknown)}; iou=#{format_iou(iou_score)}"
      )
    end)
  end

  defp model_error_row(error_type, opts) do
    span = Keyword.fetch!(opts, :span)
    metadata = Keyword.fetch!(opts, :metadata)

    %{
      error_type: error_type,
      annotation: Keyword.fetch!(opts, :annotation),
      prediction: Keyword.fetch!(opts, :prediction),
      entity: Map.get(span, :entity, :unknown),
      model_label: Map.get(metadata, :model_label, Map.get(span, :source_entity, :none)),
      recognizer: Map.get(span, :recognizer, Map.get(metadata, :recognizer, :unknown)),
      token_shape: token_shape(span),
      sample_id: Map.get(metadata, :sample_id),
      template_id: Map.get(metadata, :template_id),
      score_bucket: score_bucket(span),
      context_state: context_state(metadata),
      boundary_state: boundary_state(metadata),
      parser_state: parser_state(metadata),
      conflict_state: conflict_state(metadata),
      iou: Keyword.get(opts, :iou, 0.0),
      explanation: Keyword.fetch!(opts, :explanation)
    }
  end

  defp parser_state(metadata) do
    cond do
      Map.has_key?(metadata, :phone_parser_acceptance) ->
        {:accepted, Map.fetch!(metadata, :phone_parser_acceptance)}

      Map.get(metadata, :validation) in [:ex_phone_number, "ex_phone_number"] ->
        :parser_validated

      Map.has_key?(metadata, :validation) ->
        Map.fetch!(metadata, :validation)

      true ->
        "n/a"
    end
  end

  defp conflict_state(metadata) do
    if Map.has_key?(metadata, :conflict_policy) do
      {Map.get(metadata, :conflict_policy), Map.get(metadata, :conflict_reason)}
    else
      "n/a"
    end
  end

  defp format_iou(value), do: :erlang.float_to_binary(value, decimals: 2)

  defp actionable_span_rows(spans, grouping) do
    spans
    |> Enum.group_by(&actionable_span_key(&1, grouping))
    |> Enum.map(fn {key, grouped} -> actionable_span_row(key, grouped) end)
    |> Enum.sort_by(fn row -> {-row.count, to_string(row.label), to_string(row.token_shape)} end)
    |> Enum.take(15)
  end

  defp actionable_pair_rows(pairs) do
    pairs
    |> Enum.map(fn {_expected, predicted} -> predicted end)
    |> actionable_span_rows(:model_label)
  end

  defp actionable_span_key(span, :model_label) do
    metadata = Map.get(span, :metadata, %{}) || %{}

    %{
      label: Map.get(metadata, :model_label, Map.get(span, :source_entity, :none)),
      source_label: source_label(span),
      entity: Map.get(span, :entity, :unknown),
      token_shape: token_shape(span),
      score_bucket: score_bucket(span),
      context_state: context_state(metadata),
      boundary_state: boundary_state(metadata)
    }
  end

  defp actionable_span_key(span, :entity) do
    metadata = Map.get(span, :metadata, %{}) || %{}

    %{
      label: Map.get(span, :entity, :unknown),
      source_label: source_label(span),
      entity: Map.get(span, :entity, :unknown),
      token_shape: token_shape(span),
      score_bucket: score_bucket(span),
      context_state: context_state(metadata),
      boundary_state: boundary_state(metadata)
    }
  end

  defp actionable_span_key(span, :template_context) do
    metadata = Map.get(span, :metadata, %{}) || %{}

    %{
      label: Map.get(span, :entity, :unknown),
      source_label: source_label(span),
      entity: Map.get(span, :entity, :unknown),
      token_shape: token_shape(span),
      score_bucket: score_bucket(span),
      context_state: context_state(metadata),
      boundary_state: boundary_state(metadata),
      template_id: Map.get(metadata, :template_id, :unknown)
    }
  end

  defp actionable_span_row(key, spans) do
    metadata = Enum.map(spans, &(Map.get(&1, :metadata, %{}) || %{}))

    key
    |> Map.put(:count, length(spans))
    |> Map.put(:sample_ids, metadata |> Enum.map(&Map.get(&1, :sample_id)) |> compact_top())
    |> Map.put(:template_ids, metadata |> Enum.map(&Map.get(&1, :template_id)) |> compact_top())
  end

  defp source_label(span) do
    metadata = Map.get(span, :metadata, %{}) || %{}

    Map.get(span, :source_entity, Map.get(metadata, :model_label, :none))
  end

  defp token_shape(span) do
    value = span |> normalize_span_text_keys() |> text_value()

    if is_binary(value) do
      value
      |> String.graphemes()
      |> Enum.map_join(&grapheme_shape/1)
      |> String.slice(0, 32)
    else
      "omitted:#{length_bucket(span)}"
    end
  end

  defp normalize_span_text_keys(span) do
    span
    |> normalize_string_key(:text, "text")
    |> normalize_string_key(:value, "value")
  end

  defp normalize_string_key(map, atom_key, string_key) do
    if Map.has_key?(map, atom_key) do
      map
    else
      case Map.fetch(map, string_key) do
        {:ok, value} -> Map.put(map, atom_key, value)
        :error -> map
      end
    end
  end

  defp text_value(span), do: Map.get(span, :text) || Map.get(span, :value)

  defp grapheme_shape(grapheme) do
    cond do
      Regex.match?(~r/^\p{L}$/u, grapheme) -> "A"
      Regex.match?(~r/^\p{N}$/u, grapheme) -> "9"
      grapheme =~ ~r/^\s$/u -> " "
      true -> grapheme
    end
  end

  defp score_bucket(span) do
    score =
      span
      |> Map.get(:metadata, %{})
      |> Kernel.||(%{})
      |> Map.get(:model_original_score, Map.get(span, :score))

    cond do
      not is_number(score) -> "n/a"
      score < 0.7 -> "<0.70"
      score < 0.8 -> "0.70-0.79"
      score < 0.9 -> "0.80-0.89"
      score < 0.95 -> "0.90-0.94"
      true -> "0.95-1.00"
    end
  end

  defp context_state(metadata) do
    cond do
      Map.get(metadata, :context_matched) == true -> :matched
      Map.get(metadata, :negative_context_matched) == true -> :negative
      Map.get(metadata, :weak_context_matched) == true -> :weak_only
      Map.get(metadata, :requires_context) == true -> :missing_required
      true -> :not_required
    end
  end

  defp boundary_state(metadata) do
    cond do
      Map.get(metadata, :model_boundary_normalized) == true -> :normalized
      Map.get(metadata, :model_boundary_adjusted) == true -> :aligned
      Map.has_key?(metadata, :model_boundary_adjusted) -> :not_adjusted
      true -> "n/a"
    end
  end

  defp compact_top(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {value, count} -> {-count, to_string(value)} end)
    |> Enum.take(5)
    |> Enum.map(fn {value, _count} -> value end)
  end

  defp spans_by_model_label(spans, extra_keys) do
    spans
    |> Enum.filter(&model_labeled?/1)
    |> Enum.group_by(&span_model_label/1)
    |> Map.new(fn {model_label, grouped} ->
      {model_label, error_group(model_label, grouped, extra_keys)}
    end)
  end

  defp spans_by_entity(spans) do
    spans
    |> Enum.group_by(&Map.get(&1, :entity, :unknown))
    |> Map.new(fn {entity, grouped} ->
      {entity, error_group(entity, grouped, [:template_id])}
    end)
  end

  defp pairs_by_prediction_model_label(pairs, extra_keys) do
    pairs
    |> Enum.filter(fn {_expected, predicted} -> model_labeled?(predicted) end)
    |> Enum.group_by(fn {_expected, predicted} -> span_model_label(predicted) end)
    |> Map.new(fn {model_label, grouped} ->
      prediction_spans = Enum.map(grouped, fn {_expected, predicted} -> predicted end)
      {model_label, error_group(model_label, prediction_spans, extra_keys)}
    end)
  end

  defp error_group(label, spans, extra_keys) do
    %{
      label: label,
      count: length(spans),
      entities:
        spans
        |> Enum.map(&Map.get(&1, :entity, :unknown))
        |> Enum.frequencies(),
      templates:
        spans
        |> Enum.map(&(Map.get(&1, :metadata, %{}) || %{}))
        |> Enum.map(&Map.get(&1, :template_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {template_id, count} -> {-count, to_string(template_id)} end)
        |> Enum.take(5)
        |> Map.new(),
      examples:
        spans
        |> Enum.map(&Map.take(&1, [:entity, :source_entity, :recognizer, :metadata]))
        |> Enum.take(5)
    }
    |> Map.merge(extra_group_fields(spans, extra_keys))
  end

  defp extra_group_fields(spans, extra_keys) do
    extra_keys
    |> Enum.reject(&(&1 in [:template_id]))
    |> Map.new(fn key ->
      {key,
       spans
       |> Enum.map(&Map.get(&1, key, :unknown))
       |> Enum.frequencies()}
    end)
  end

  defp model_labeled?(span), do: span_model_label(span) != :none

  defp span_model_label(span) do
    span
    |> Map.get(:metadata, %{})
    |> Kernel.||(%{})
    |> Map.get(:model_label, :none)
  end

  defp base_model_label(label) when is_binary(label),
    do: String.replace(label, ~r/^(B|I|E|S)-/, "")

  defp base_model_label(label), do: label

  defp signature_rows(spans, error_type) do
    spans
    |> Enum.group_by(&signature_key(&1, error_type))
    |> Enum.map(fn {key, grouped_spans} -> signature_row(key, grouped_spans) end)
    |> Enum.sort_by(fn row ->
      {-row.count, to_string(row.entity), to_string(row.source_entity),
       to_string(row.likely_cause)}
    end)
    |> Enum.take(10)
  end

  defp signature_key(span, error_type) do
    metadata = Map.get(span, :metadata, %{}) || %{}

    %{
      entity: Map.get(span, :entity, :unknown),
      source_entity: Map.get(span, :source_entity, :unknown),
      recognizer: Map.get(span, :recognizer, Map.get(metadata, :recognizer, :unknown)),
      model_label: Map.get(metadata, :model_label, :none),
      template_id: Map.get(metadata, :template_id, :unknown),
      length_bucket: length_bucket(span),
      likely_cause: likely_cause(span, error_type)
    }
  end

  defp signature_row(key, spans) do
    metadata = Enum.map(spans, &(Map.get(&1, :metadata, %{}) || %{}))

    key
    |> Map.put(:count, length(spans))
    |> Map.put(
      :sample_ids,
      metadata
      |> Enum.map(&Map.get(&1, :sample_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(5)
    )
    |> Map.put(
      :template_ids,
      metadata
      |> Enum.map(&Map.get(&1, :template_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(5)
    )
  end

  defp length_bucket(span) do
    start = Map.get(span, :byte_start, Map.get(span, :start, 0))
    finish = Map.get(span, :byte_end, Map.get(span, :end, start))
    span_length = max(finish - start, 0)

    cond do
      span_length <= 2 -> "0-2"
      span_length <= 5 -> "3-5"
      span_length <= 10 -> "6-10"
      span_length <= 20 -> "11-20"
      true -> "21+"
    end
  end

  defp aggregate_error_buckets(scores) do
    scores
    |> Enum.map(&Map.fetch!(&1, :error_buckets))
    |> Enum.reduce(empty_error_buckets(), &merge_error_buckets/2)
  end

  defp aggregate_error_signatures(scores) do
    scores
    |> Enum.map(&Map.get(&1, :error_signatures, %{false_positives: [], false_negatives: []}))
    |> Enum.reduce(%{false_positives: [], false_negatives: []}, fn signatures, acc ->
      %{
        false_positives:
          merge_signature_rows(acc.false_positives, Map.get(signatures, :false_positives, [])),
        false_negatives:
          merge_signature_rows(acc.false_negatives, Map.get(signatures, :false_negatives, []))
      }
    end)
  end

  defp aggregate_model_label_errors(scores) do
    scores
    |> Enum.map(&Map.get(&1, :model_label_errors, empty_model_label_errors()))
    |> Enum.reduce(empty_model_label_errors(), &merge_model_label_errors/2)
  end

  defp aggregate_actionable_errors(scores) do
    scores
    |> Enum.map(&Map.get(&1, :actionable_errors, empty_actionable_errors()))
    |> Enum.reduce(empty_actionable_errors(), &merge_actionable_errors/2)
  end

  defp aggregate_model_errors(scores) do
    scores
    |> Enum.flat_map(&Map.get(&1, :model_errors, []))
    |> Enum.sort_by(fn row ->
      {to_string(Map.get(row, :error_type)), to_string(Map.get(row, :entity)),
       to_string(Map.get(row, :model_label)), Map.get(row, :sample_id) || 0}
    end)
    |> Enum.take(100)
  end

  defp empty_actionable_errors do
    %{
      top_false_positive_tokens_by_model_label: [],
      top_false_negative_tokens_by_expected_entity: [],
      location_false_positives_by_model_label: [],
      location_false_negatives_by_template_context: [],
      organization_false_negatives_by_template_context: [],
      offset_mismatch_rows: [],
      wrong_entity_type_rows: []
    }
  end

  defp merge_actionable_errors(right, left) do
    Map.new(empty_actionable_errors(), fn {key, _empty} ->
      {key, merge_actionable_rows(Map.get(left, key, []), Map.get(right, key, []))}
    end)
  end

  defp merge_actionable_rows(left, right) do
    (left ++ right)
    |> Enum.group_by(
      &Map.take(&1, [
        :label,
        :source_label,
        :entity,
        :token_shape,
        :score_bucket,
        :context_state,
        :boundary_state,
        :template_id
      ])
    )
    |> Enum.map(fn {_key, rows} ->
      merge_report_rows(rows)
    end)
    |> Enum.sort_by(fn row ->
      {-row.count, to_string(row.label), to_string(row.source_label), to_string(row.token_shape)}
    end)
    |> Enum.take(15)
  end

  defp empty_model_label_errors do
    %{
      false_positives: %{},
      false_negatives: %{},
      offset_mismatches: %{},
      wrong_entity_type: %{}
    }
  end

  defp merge_model_label_errors(right, left) do
    Map.new(empty_model_label_errors(), fn {error_type, _empty} ->
      {error_type,
       merge_error_groups(Map.get(left, error_type, %{}), Map.get(right, error_type, %{}))}
    end)
  end

  defp merge_error_groups(left, right) do
    (map_keys(left) ++ map_keys(right))
    |> Enum.uniq()
    |> Map.new(fn label ->
      {label, merge_error_group(Map.get(left, label), Map.get(right, label), label)}
    end)
  end

  defp merge_error_group(nil, group, _label), do: group
  defp merge_error_group(group, nil, _label), do: group

  defp merge_error_group(left, right, label) do
    %{
      label: label,
      count: Map.get(left, :count, 0) + Map.get(right, :count, 0),
      entities: merge_count_maps(Map.get(left, :entities, %{}), Map.get(right, :entities, %{})),
      templates:
        merge_count_maps(Map.get(left, :templates, %{}), Map.get(right, :templates, %{}))
        |> Enum.sort_by(fn {template_id, count} -> {-count, to_string(template_id)} end)
        |> Enum.take(5)
        |> Map.new(),
      examples: Enum.take(Map.get(left, :examples, []) ++ Map.get(right, :examples, []), 5)
    }
    |> maybe_merge_count_field(:entity, left, right)
    |> maybe_merge_count_field(:recognizer, left, right)
  end

  defp maybe_merge_count_field(group, key, left, right) do
    if Map.has_key?(left, key) or Map.has_key?(right, key) do
      Map.put(group, key, merge_count_maps(Map.get(left, key, %{}), Map.get(right, key, %{})))
    else
      group
    end
  end

  defp merge_count_maps(left, right) do
    Map.merge(left, right, fn _key, left_count, right_count -> left_count + right_count end)
  end

  defp merge_signature_rows(left, right) do
    (left ++ right)
    |> Enum.group_by(&signature_row_key/1)
    |> Enum.map(fn {_key, rows} -> merge_signature_group(rows) end)
    |> Enum.sort_by(fn row ->
      {-row.count, to_string(row.entity), to_string(row.source_entity),
       to_string(row.likely_cause)}
    end)
    |> Enum.take(10)
  end

  defp signature_row_key(row) do
    Map.take(row, [
      :entity,
      :source_entity,
      :recognizer,
      :model_label,
      :template_id,
      :length_bucket,
      :likely_cause
    ])
  end

  defp merge_signature_group(rows) do
    merge_report_rows(rows)
  end

  defp merge_report_rows(rows) do
    rows
    |> hd()
    |> Map.drop([:count, :sample_ids, :template_ids])
    |> Map.put(:count, Enum.reduce(rows, 0, &(&1.count + &2)))
    |> Map.put(
      :sample_ids,
      rows |> Enum.flat_map(&Map.get(&1, :sample_ids, [])) |> Enum.uniq() |> Enum.take(5)
    )
    |> Map.put(
      :template_ids,
      rows |> Enum.flat_map(&Map.get(&1, :template_ids, [])) |> Enum.uniq() |> Enum.take(5)
    )
  end

  defp wrong_entity_matrix(pairs) do
    pairs
    |> Enum.map(fn {expected, predicted} ->
      {Map.get(expected, :entity, :unknown), Map.get(predicted, :entity, :unknown)}
    end)
    |> Enum.frequencies()
    |> Enum.reduce(%{}, fn {{expected_entity, predicted_entity}, count}, matrix ->
      Map.update(matrix, expected_entity, %{predicted_entity => count}, fn predictions ->
        Map.put(predictions, predicted_entity, count)
      end)
    end)
  end

  defp aggregate_wrong_entity_matrix(scores) do
    Enum.reduce(scores, %{}, fn score, acc ->
      merge_wrong_entity_matrix(acc, Map.get(score, :wrong_entity_matrix, %{}))
    end)
  end

  defp merge_wrong_entity_matrix(left, right) do
    Enum.reduce(right, left, fn {expected_entity, predictions}, matrix ->
      Map.update(matrix, expected_entity, predictions, &merge_prediction_counts(&1, predictions))
    end)
  end

  defp merge_prediction_counts(existing, predictions) do
    Map.merge(existing, predictions, fn _predicted_entity, left_count, right_count ->
      left_count + right_count
    end)
  end

  defp empty_error_buckets do
    %{
      false_positives: %{},
      false_negatives: %{},
      offset_mismatches: %{},
      wrong_entity_type: %{},
      unsupported: %{}
    }
  end

  defp merge_error_buckets(right, left) do
    Map.new(empty_error_buckets(), fn {error_type, _empty} ->
      {error_type,
       merge_entity_buckets(Map.get(left, error_type, %{}), Map.get(right, error_type, %{}))}
    end)
  end

  defp merge_entity_buckets(left, right) do
    (map_keys(left) ++ map_keys(right))
    |> Enum.uniq()
    |> Map.new(fn entity ->
      left_bucket = Map.get(left, entity, %{count: 0, examples: []})
      right_bucket = Map.get(right, entity, %{count: 0, examples: []})

      {entity,
       %{
         count: left_bucket.count + right_bucket.count,
         likely_causes:
           merge_likely_causes(
             Map.get(left_bucket, :likely_causes, %{}),
             Map.get(right_bucket, :likely_causes, %{})
           ),
         examples: Enum.take(left_bucket.examples ++ right_bucket.examples, 5)
       }}
    end)
  end

  defp map_keys(map), do: Enum.map(map, fn {key, _value} -> key end)

  defp merge_likely_causes(left, right) do
    Map.merge(left, right, fn _cause, left_count, right_count -> left_count + right_count end)
  end

  defp aggregate_span_iou([]), do: score_iou([], [], [])

  defp aggregate_span_iou(scores) do
    counts = aggregate_iou_counts(scores)

    counts
    |> Map.merge(ratios(counts))
    |> Map.put(
      :iou_threshold,
      scores |> hd() |> Map.fetch!(:span_iou) |> Map.fetch!(:iou_threshold)
    )
  end

  defp aggregate_span_normalization([]) do
    %{
      mode: :unavailable,
      expected_merge_count: 0,
      predicted_merge_count: 0,
      span_iou: score_iou([], [], [])
    }
  end

  defp aggregate_span_normalization(scores) do
    normalized_scores = Enum.map(scores, &Map.fetch!(&1, :span_normalization))

    counts = aggregate_iou_counts(normalized_scores)

    %{
      mode: :skip_word_adjacent,
      expected_merge_count:
        Enum.reduce(normalized_scores, 0, &(&2 + Map.get(&1, :expected_merge_count, 0))),
      predicted_merge_count:
        Enum.reduce(normalized_scores, 0, &(&2 + Map.get(&1, :predicted_merge_count, 0))),
      span_iou:
        counts
        |> Map.merge(ratios(counts))
        |> Map.put(
          :iou_threshold,
          normalized_scores |> hd() |> Map.fetch!(:span_iou) |> Map.fetch!(:iou_threshold)
        )
    }
  end

  defp aggregate_iou_counts(scores) do
    Enum.reduce(scores, empty_iou_counts(), fn score, acc ->
      iou_score = Map.fetch!(score, :span_iou)

      %{
        acc
        | true_positives: acc.true_positives + iou_score.true_positives,
          false_positives: acc.false_positives + iou_score.false_positives,
          false_negatives: acc.false_negatives + iou_score.false_negatives,
          wrong_entity_type: acc.wrong_entity_type + iou_score.wrong_entity_type,
          total_supported_expected_spans:
            acc.total_supported_expected_spans + iou_score.total_supported_expected_spans,
          total_predicted_spans: acc.total_predicted_spans + iou_score.total_predicted_spans,
          examples: merge_iou_examples(acc.examples, iou_score.examples)
      }
    end)
  end

  defp empty_iou_counts do
    %{
      true_positives: 0,
      false_positives: 0,
      false_negatives: 0,
      wrong_entity_type: 0,
      total_supported_expected_spans: 0,
      total_predicted_spans: 0,
      examples: %{false_positives: [], false_negatives: [], wrong_entity_type: []}
    }
  end

  defp merge_iou_examples(left, right) do
    %{
      false_positives: Enum.take(left.false_positives ++ right.false_positives, 10),
      false_negatives: Enum.take(left.false_negatives ++ right.false_negatives, 10),
      wrong_entity_type: Enum.take(left.wrong_entity_type ++ right.wrong_entity_type, 10)
    }
  end

  defp per_template_metrics(results, profile, opts) do
    results
    |> Enum.group_by(fn result ->
      result |> Map.get(:sample, %{}) |> Map.get(:template_id, :unknown)
    end)
    |> Map.new(fn {template_id, template_results} ->
      latency = Enum.map(template_results, & &1.latency_ms)

      stage_latency =
        template_results
        |> Enum.map(&Map.get(&1, :stage_latency_ms))
        |> Enum.reject(&is_nil/1)

      metrics =
        template_results
        |> Enum.map(fn result ->
          score(
            result.expected,
            result.predicted,
            profile,
            Keyword.put(opts, :sample_text, sample_text(result))
          )
        end)
        |> aggregate_scores(length(template_results), latency, stage_latency)
        |> Map.drop([:per_template, :examples, :error_buckets, :error_signatures])

      {template_id, Map.put(metrics, :sample_count, length(template_results))}
    end)
  end

  defp sample_text(result) do
    result
    |> Map.get(:sample, %{})
    |> Map.get(:text)
  end

  defp divide(_numerator, 0), do: nil
  defp divide(numerator, denominator), do: numerator / denominator

  defp f_score(precision, recall, beta) do
    cond do
      is_nil(precision) or is_nil(recall) ->
        nil

      precision == 0.0 and recall == 0.0 ->
        0.0

      true ->
        beta_squared = beta * beta
        denominator = beta_squared * precision + recall

        if denominator == 0.0 do
          0.0
        else
          (1 + beta_squared) * precision * recall / denominator
        end
    end
  end
end
