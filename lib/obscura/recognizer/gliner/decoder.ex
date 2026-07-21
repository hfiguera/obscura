defmodule Obscura.Recognizer.GLiNER.Decoder do
  @moduledoc """
  Decodes GLiNER span logits into byte-offset spans.
  """

  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.LabelMap

  @type decoded_span :: %{
          entity: atom(),
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          text: String.t(),
          score: float(),
          source_entity: String.t(),
          metadata: map()
        }

  @doc """
  Decodes a single GLiNER model output tensor.
  """
  @spec decode(Nx.Tensor.t(), map(), Config.t(), String.t()) ::
          {:ok, [decoded_span()]} | {:error, term()}
  def decode(logits, prepared, %Config{} = config, text) do
    decode_shape(logits, Nx.shape(logits), prepared, config, text)
  end

  defp decode_shape(logits, shape, prepared, %Config{span_mode: :token_level} = config, text) do
    case shape do
      {1, text_length, class_count, 3} ->
        logits
        |> Nx.to_flat_list()
        |> token_candidates(text_length, class_count, prepared, config, text)
        |> greedy(config)
        |> then(&{:ok, &1})

      {3, 1, text_length, class_count} ->
        logits
        |> Nx.transpose(axes: [1, 2, 3, 0])
        |> Nx.to_flat_list()
        |> token_candidates(text_length, class_count, prepared, config, text)
        |> greedy(config)
        |> then(&{:ok, &1})

      other ->
        {:error, {:unsupported_gliner_token_logits_shape, other}}
    end
  end

  defp decode_shape(logits, _shape, prepared, %Config{} = config, text) do
    case Nx.shape(logits) do
      {1, text_length, max_width, class_count} ->
        logits
        |> Nx.to_flat_list()
        |> candidates(text_length, max_width, class_count, prepared, config, text)
        |> greedy(config)
        |> then(&{:ok, &1})

      other ->
        {:error, {:unsupported_gliner_logits_shape, other}}
    end
  end

  defp token_candidates(values, text_length, class_count, prepared, config, text) do
    scores =
      for position <- 0..(text_length - 1),
          class_index <- 0..(class_count - 1),
          into: %{} do
        base = (position * class_count + class_index) * 3

        {{position, class_index},
         %{
           start: sigmoid(Enum.at(values, base)),
           ending: sigmoid(Enum.at(values, base + 1)),
           inside: sigmoid(Enum.at(values, base + 2))
         }}
      end

    for start <- 0..(text_length - 1),
        ending <- start..(text_length - 1),
        class_index <- 0..(class_count - 1),
        start < length(prepared.tokens),
        ending < length(prepared.tokens),
        reduce: [] do
      acc ->
        label = Map.get(prepared.id_to_class, class_index + 1)
        threshold = threshold_for(label, config)

        with true <- is_binary(label),
             {:ok, score} <- token_score(scores, start, ending, class_index, threshold),
             span when not is_nil(span) <-
               build_token_span(start, ending, label, score, threshold, prepared, config, text) do
          [span | acc]
        else
          _other -> acc
        end
    end
    |> Enum.reverse()
  end

  defp token_score(scores, start, ending, class_index, threshold) do
    with %{start: start_score} <- Map.get(scores, {start, class_index}),
         true <- start_score > threshold,
         %{ending: end_score} <- Map.get(scores, {ending, class_index}),
         true <- end_score > threshold do
      inside_scores =
        start..ending
        |> Enum.map(fn position -> Map.fetch!(scores, {position, class_index}).inside end)

      if Enum.all?(inside_scores, &(&1 >= threshold)) do
        {:ok, Enum.min([start_score, end_score | inside_scores])}
      else
        :error
      end
    else
      _other -> :error
    end
  end

  defp build_token_span(start, ending, label, score, threshold, prepared, config, text) do
    with entity when not is_nil(entity) <- LabelMap.to_entity(config.label_profile, label),
         start_token when not is_nil(start_token) <- Enum.at(prepared.tokens, start),
         end_token when not is_nil(end_token) <- Enum.at(prepared.tokens, ending),
         true <- start_token.start < end_token.end do
      %{
        entity: entity,
        byte_start: start_token.start,
        byte_end: end_token.end,
        text: binary_part(text, start_token.start, end_token.end - start_token.start),
        score: score,
        source_entity: label,
        metadata: %{
          source: :gliner_ortex,
          adapter: "Obscura.Recognizer.GLiNER.Ortex",
          label_profile: config.label_profile,
          model_label: label,
          threshold: threshold,
          word_start: start,
          word_end: ending,
          overlap_strategy: :greedy,
          span_mode: :token_level,
          tokenization_mode: :offset_reconstructed_words_mask
        }
      }
    else
      _other -> nil
    end
  end

  defp candidates(values, text_length, max_width, class_count, prepared, config, text) do
    for start <- 0..(text_length - 1),
        width <- 0..(max_width - 1),
        start + width < length(prepared.tokens),
        class_index <- 0..(class_count - 1),
        reduce: [] do
      acc ->
        flat_index = (start * max_width + width) * class_count + class_index
        score = sigmoid(Enum.at(values, flat_index))
        label = Map.get(prepared.id_to_class, class_index + 1)

        maybe_add_candidate(acc, start, width, label, score, prepared, config, text)
    end
    |> Enum.reverse()
  end

  defp maybe_add_candidate(acc, start, width, label, score, prepared, config, text) do
    threshold = threshold_for(label, config)

    cond do
      not is_binary(label) ->
        acc

      score <= threshold ->
        acc

      span = build_span(start, width, label, score, threshold, prepared, config, text) ->
        [span | acc]

      true ->
        acc
    end
  end

  defp build_span(start, width, label, score, threshold, prepared, config, text) do
    ending = start + width

    with entity when not is_nil(entity) <- LabelMap.to_entity(config.label_profile, label),
         start_token when not is_nil(start_token) <- Enum.at(prepared.tokens, start),
         end_token when not is_nil(end_token) <- Enum.at(prepared.tokens, ending),
         true <- start_token.start < end_token.end do
      %{
        entity: entity,
        byte_start: start_token.start,
        byte_end: end_token.end,
        text: binary_part(text, start_token.start, end_token.end - start_token.start),
        score: score,
        source_entity: label,
        metadata: %{
          source: :gliner_ortex,
          adapter: "Obscura.Recognizer.GLiNER.Ortex",
          label_profile: config.label_profile,
          model_label: label,
          threshold: threshold,
          word_start: start,
          word_end: ending,
          overlap_strategy: :greedy,
          tokenization_mode: :offset_reconstructed_words_mask
        }
      }
    else
      _other -> nil
    end
  end

  defp greedy(candidates, %Config{flat_ner: false}), do: candidates

  defp greedy(candidates, %Config{multi_label: multi_label}) do
    candidates
    |> Enum.sort_by(&{-&1.score, &1.byte_start})
    |> Enum.reduce([], fn candidate, kept ->
      if overlap?(candidate, kept, multi_label) do
        kept
      else
        [candidate | kept]
      end
    end)
    |> Enum.reverse()
    |> Enum.sort_by(&{&1.byte_start, &1.byte_end, &1.entity})
  end

  defp overlap?(candidate, kept, true = _multi_label) do
    Enum.any?(kept, fn span ->
      span.entity == candidate.entity and spans_overlap?(candidate, span)
    end)
  end

  defp overlap?(candidate, kept, false = _multi_label) do
    Enum.any?(kept, &spans_overlap?(candidate, &1))
  end

  defp spans_overlap?(left, right) do
    left.byte_start < right.byte_end and right.byte_start < left.byte_end
  end

  defp threshold_for(label, %Config{} = config) do
    Map.get(config.per_label_thresholds, label, config.threshold)
  end

  defp sigmoid(value), do: 1.0 / (1.0 + :math.exp(-value))
end
