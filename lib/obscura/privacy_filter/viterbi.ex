defmodule Obscura.PrivacyFilter.Viterbi do
  @moduledoc """
  BIOES-constrained Viterbi decoder for privacy-filter token labels.
  """

  alias Obscura.PrivacyFilter.LabelInfo

  @neg_inf -1.0e9
  @bias_keys [
    :transition_bias_background_stay,
    :transition_bias_background_to_start,
    :transition_bias_inside_to_continue,
    :transition_bias_inside_to_end,
    :transition_bias_end_to_background,
    :transition_bias_end_to_start
  ]

  @enforce_keys [
    :label_info,
    :biases,
    :labels,
    :start_scores,
    :end_scores,
    :transition_candidates
  ]
  defstruct [:label_info, :biases, :labels, :start_scores, :end_scores, :transition_candidates]

  @type t :: %__MODULE__{}

  @spec new(LabelInfo.t(), keyword() | map()) :: t()
  def new(%LabelInfo{} = label_info, opts \\ []) do
    biases =
      @bias_keys
      |> Map.new(fn key -> {key, get_bias(opts, key)} end)

    class_count = map_size(label_info.token_to_span_label)
    labels = Enum.to_list(0..(class_count - 1))

    %__MODULE__{
      label_info: label_info,
      biases: biases,
      labels: labels,
      start_scores: Enum.map(labels, &start_score(label_info, &1)),
      end_scores: Enum.map(labels, &end_score(label_info, &1)),
      transition_candidates: transition_candidates(label_info, biases, labels)
    }
  end

  @spec zero_biases() :: map()
  def zero_biases, do: Map.new(@bias_keys, &{&1, 0.0})

  @spec decode(t(), [[number()]]) :: [non_neg_integer()]
  def decode(%__MODULE__{}, []), do: []
  def decode(%__MODULE__{} = decoder, [first | rest]), do: do_decode(decoder, first, rest)

  @spec valid_transition?(LabelInfo.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def valid_transition?(%LabelInfo{} = label_info, previous, next) do
    transition_allowed?(label_info, previous, next)
  end

  defp do_decode(decoder, first, rest) do
    class_count = length(first)
    labels = labels(decoder, class_count)
    start_scores = scores_for_class_count(decoder.start_scores, class_count)
    end_scores = scores_for_class_count(decoder.end_scores, class_count)
    transition_candidates = candidates_for_class_count(decoder, class_count)

    scores = zip_add(first, start_scores)

    {scores, backpointers} =
      Enum.reduce(rest, {scores, []}, &decode_step(&1, &2, labels, transition_candidates))

    final_scores = zip_add(scores, end_scores)

    if Enum.any?(final_scores, &finite?/1) do
      {_score, last_label} = max_with_index(final_scores)
      backtrack(last_label, Enum.reverse(backpointers))
    else
      Enum.map(token_logprobs(decoder, first, rest), fn row ->
        row |> max_with_index() |> elem(1)
      end)
    end
  end

  defp decode_step(emissions, {previous_scores, paths}, labels, transition_candidates) do
    previous_scores = List.to_tuple(previous_scores)
    emissions = List.to_tuple(emissions)

    {next_scores, next_paths} =
      labels
      |> Enum.map(&best_next_score(&1, transition_candidates, previous_scores, emissions))
      |> Enum.unzip()

    {next_scores, [List.to_tuple(next_paths) | paths]}
  end

  defp best_next_score(next, transition_candidates, previous_scores, emissions) do
    {best_score, best_previous} =
      transition_candidates
      |> elem(next)
      |> best_candidate(previous_scores)

    {best_score + elem(emissions, next), best_previous}
  end

  defp token_logprobs(_decoder, first, rest), do: [first | rest]

  defp backtrack(last_label, backpointers) do
    backpointers
    |> Enum.reverse()
    |> Enum.reduce([last_label], fn paths, [current | _] = acc ->
      [elem(paths, current) | acc]
    end)
  end

  defp labels(%__MODULE__{labels: labels}, class_count) when length(labels) == class_count,
    do: labels

  defp labels(_decoder, class_count), do: Enum.to_list(0..(class_count - 1))

  defp scores_for_class_count(scores, class_count) when length(scores) == class_count, do: scores

  defp scores_for_class_count(_scores, class_count), do: List.duplicate(0.0, class_count)

  defp candidates_for_class_count(%__MODULE__{} = decoder, class_count)
       when tuple_size(decoder.transition_candidates) == class_count do
    decoder.transition_candidates
  end

  defp candidates_for_class_count(%__MODULE__{} = decoder, class_count) do
    labels = Enum.to_list(0..(class_count - 1))
    transition_candidates(decoder.label_info, decoder.biases, labels)
  end

  defp transition_candidates(%LabelInfo{} = label_info, biases, labels) do
    labels
    |> Enum.map(&transition_candidates_for_next(label_info, biases, labels, &1))
    |> List.to_tuple()
  end

  defp transition_candidates_for_next(label_info, biases, labels, next) do
    labels
    |> Enum.reduce([], fn previous, acc ->
      if transition_allowed?(label_info, previous, next),
        do: [{previous, transition_bias(label_info, biases, previous, next)} | acc],
        else: acc
    end)
    |> Enum.reverse()
  end

  defp best_candidate([], _previous_scores), do: {@neg_inf, 0}

  defp best_candidate([{previous, bias} | rest], previous_scores) do
    Enum.reduce(rest, {elem(previous_scores, previous) + bias, previous}, fn {candidate, bias},
                                                                             {best, best_label} ->
      score = elem(previous_scores, candidate) + bias

      if score > best do
        {score, candidate}
      else
        {best, best_label}
      end
    end)
  end

  defp start_score(label_info, label) do
    tag = Map.get(label_info.token_boundary_tags, label)

    if tag in ["B", "S"] or label == label_info.background_token_label do
      0.0
    else
      @neg_inf
    end
  end

  defp end_score(label_info, label) do
    tag = Map.get(label_info.token_boundary_tags, label)

    if tag in ["E", "S"] or label == label_info.background_token_label do
      0.0
    else
      @neg_inf
    end
  end

  defp transition_allowed?(label_info, previous, next) do
    context = transition_context(label_info, previous, next)

    cond do
      invalid_next?(context) ->
        false

      invalid_previous?(context) ->
        can_start?(context)

      context.previous_background? ->
        can_start?(context)

      context.previous_tag in ["E", "S"] ->
        can_start?(context)

      context.previous_tag in ["B", "I"] ->
        can_continue?(context)

      true ->
        false
    end
  end

  defp transition_context(label_info, previous, next) do
    previous_span = Map.get(label_info.token_to_span_label, previous)
    next_span = Map.get(label_info.token_to_span_label, next)

    %{
      previous_tag: Map.get(label_info.token_boundary_tags, previous),
      next_tag: Map.get(label_info.token_boundary_tags, next),
      previous_span: previous_span,
      next_span: next_span,
      previous_background?:
        previous == label_info.background_token_label or
          previous_span == label_info.background_span_label,
      next_background?:
        next == label_info.background_token_label or next_span == label_info.background_span_label
    }
  end

  defp invalid_next?(context),
    do: is_nil(context.next_span) or (is_nil(context.next_tag) and not context.next_background?)

  defp invalid_previous?(context),
    do:
      is_nil(context.previous_span) or
        (is_nil(context.previous_tag) and not context.previous_background?)

  defp can_start?(context), do: context.next_background? or context.next_tag in ["B", "S"]

  defp can_continue?(context),
    do: context.previous_span == context.next_span and context.next_tag in ["I", "E"]

  defp transition_bias(label_info, biases, previous, next) do
    context = transition_context(label_info, previous, next)

    cond do
      background_stay?(context) ->
        biases.transition_bias_background_stay

      background_to_start?(context) ->
        biases.transition_bias_background_to_start

      inside_continue?(context) ->
        biases.transition_bias_inside_to_continue

      inside_end?(context) ->
        biases.transition_bias_inside_to_end

      end_to_background?(context) ->
        biases.transition_bias_end_to_background

      end_to_start?(context) ->
        biases.transition_bias_end_to_start

      true ->
        0.0
    end
  end

  defp background_stay?(context),
    do: context.previous_background? and context.next_background?

  defp background_to_start?(context),
    do: context.previous_background? and context.next_tag in ["B", "S"]

  defp inside_continue?(context), do: inside_transition?(context, "I")
  defp inside_end?(context), do: inside_transition?(context, "E")

  defp inside_transition?(context, next_tag),
    do:
      context.previous_tag in ["B", "I"] and context.next_tag == next_tag and
        context.previous_span == context.next_span

  defp end_to_background?(context),
    do: context.previous_tag in ["E", "S"] and context.next_background?

  defp end_to_start?(context),
    do: context.previous_tag in ["E", "S"] and context.next_tag in ["B", "S"]

  defp get_bias(opts, key) when is_list(opts), do: opts |> Keyword.get(key, 0.0) |> Kernel.*(1.0)
  defp get_bias(opts, key) when is_map(opts), do: opts |> Map.get(key, 0.0) |> Kernel.*(1.0)

  defp zip_add(left, right), do: Enum.zip_with(left, right, &(&1 + &2))

  defp max_with_index(values) do
    values
    |> Enum.with_index()
    |> Enum.max_by(fn {value, _index} -> value end)
  end

  defp finite?(value), do: value > @neg_inf / 2
end
