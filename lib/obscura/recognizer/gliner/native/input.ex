defmodule Obscura.Recognizer.GLiNER.Native.Input do
  @moduledoc false

  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.Inputs

  @position_buckets 256
  @max_relative_positions 512

  @type shape_bucket :: {pos_integer(), pos_integer()}

  @spec build(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(prepared, %Config{} = config, opts \\ []) do
    with {:ok, prompt_indexes} <- prompt_indexes(prepared, config) do
      native_tensors(prepared, prompt_indexes, opts)
    end
  end

  @spec relative_positions(pos_integer()) :: Nx.Tensor.t()
  def relative_positions(length) when is_integer(length) and length > 0 do
    values =
      for query <- 0..(length - 1), key <- 0..(length - 1) do
        bucket_position(query - key)
      end

    values
    |> Nx.tensor(type: {:s, 64})
    |> Nx.reshape({1, length, length})
  end

  defp prompt_indexes(prepared, %Config{class_token_index: index} = config)
       when is_integer(index) do
    input_ids = prepared.tensors |> elem(0) |> Nx.to_flat_list()

    indexes =
      input_ids
      |> Enum.with_index()
      |> Enum.filter(fn {token_id, _position} -> token_id == index end)
      |> Enum.map(fn {_token_id, position} ->
        if config.embed_ent_token, do: position, else: position + 1
      end)

    if length(indexes) == length(config.labels) do
      {:ok, indexes}
    else
      {:error,
       {:gliner_native_prompt_count_mismatch,
        %{expected: length(config.labels), actual: length(indexes)}}}
    end
  end

  defp prompt_indexes(_prepared, _config), do: {:error, :missing_gliner_class_token_index}

  defp native_tensors(prepared, prompt_indexes, opts) do
    {input_ids, attention_mask, _words_mask, _text_lengths, span_idx, span_mask} =
      prepared.tensors

    word_indexes = prepared.word_token_indexes
    token_length = Nx.axis_size(input_ids, 1)
    word_length = length(word_indexes)

    if word_indexes == [] do
      {:error, :gliner_native_empty_text}
    else
      case target_shape(token_length, word_length, Keyword.get(opts, :shape_buckets, false)) do
        {:ok, {target_tokens, target_words}} ->
          {span_idx, span_mask} =
            padded_spans(span_idx, span_mask, word_length, target_words, config_max_width(opts))

          {:ok,
           %{
             "input_ids" => pad_axis(input_ids, target_tokens, 0),
             "attention_mask" => pad_axis(attention_mask, target_tokens, 0),
             "relative_pos" => relative_positions(target_tokens),
             "prompt_token_indexes" => Nx.tensor([prompt_indexes], type: {:s, 64}),
             "word_token_indexes" =>
               Nx.tensor([pad_list(word_indexes, target_words, 0)], type: {:s, 64}),
             "word_mask" =>
               Nx.tensor(
                 [
                   List.duplicate(1, word_length) ++ List.duplicate(0, target_words - word_length)
                 ],
                 type: {:u, 8}
               ),
             "span_idx" => span_idx,
             "span_mask" => span_mask
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp target_shape(token_length, word_length, false), do: {:ok, {token_length, word_length}}

  defp target_shape(token_length, word_length, buckets) when is_list(buckets) do
    case Enum.find(buckets, fn {tokens, words} ->
           tokens >= token_length and words >= word_length
         end) do
      nil -> {:error, {:gliner_native_input_too_large, {token_length, word_length}, buckets}}
      bucket -> {:ok, bucket}
    end
  end

  defp target_shape(_token_length, _word_length, value),
    do: {:error, {:invalid_gliner_native_shape_buckets, value}}

  defp padded_spans(span_idx, span_mask, word_length, word_length, _max_width),
    do: {span_idx, span_mask}

  defp padded_spans(_span_idx, _span_mask, word_length, target_words, max_width) do
    {indexes, masks} = Inputs.span_indexes(target_words, max_width)

    masks =
      masks
      |> Enum.with_index()
      |> Enum.map(fn {valid?, index} ->
        start = div(index, max_width)
        width = rem(index, max_width)
        valid? and start + width < word_length
      end)

    {
      Nx.tensor([indexes], type: {:s, 64}),
      Nx.tensor([masks], type: {:u, 8})
    }
  end

  defp pad_axis(tensor, target, value) do
    current = Nx.axis_size(tensor, 1)
    Nx.pad(tensor, value, [{0, 0, 0}, {0, target - current, 0}])
  end

  defp pad_list(values, target, value),
    do: values ++ List.duplicate(value, target - length(values))

  defp config_max_width(opts), do: Keyword.fetch!(opts, :max_width)

  defp bucket_position(position) when position >= -128 and position <= 128, do: position

  defp bucket_position(position) do
    middle = div(@position_buckets, 2)
    sign = if position < 0, do: -1, else: 1

    logarithmic =
      Float.ceil(
        :math.log(abs(position) / middle) /
          :math.log((@max_relative_positions - 1) / middle) * (middle - 1)
      ) + middle

    trunc(logarithmic) * sign
  end
end
