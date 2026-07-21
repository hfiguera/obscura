defmodule Obscura.Recognizer.GLiNER.Inputs do
  @moduledoc """
  Builds GLiNER ONNX inputs from Obscura text.
  """

  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.TokenSplitter

  @ent_token "<<ENT>>"
  @sep_token "<<SEP>>"

  @type prepared :: %{
          input_text: String.t(),
          tokens: [TokenSplitter.token()],
          id_to_class: %{pos_integer() => String.t()},
          tensors: tuple(),
          word_token_indexes: [non_neg_integer()]
        }

  @doc """
  Builds the GLiNER prompt text.
  """
  @spec prompt_text([String.t()]) :: String.t()
  def prompt_text(labels) when is_list(labels) do
    prompt_text(labels, " ")
  end

  @doc false
  @spec prompt_text([String.t()], String.t()) :: String.t()
  def prompt_text(labels, joiner) when is_list(labels) and is_binary(joiner) do
    labels
    |> Enum.flat_map(&[@ent_token, &1])
    |> Kernel.++([@sep_token])
    |> Enum.join(joiner)
  end

  @doc """
  Builds inclusive span indexes and masks.
  """
  @spec span_indexes(non_neg_integer(), pos_integer()) :: {[[integer()]], [boolean()]}
  def span_indexes(text_length, max_width) when text_length >= 0 and max_width > 0 do
    for start <- 0..max(text_length - 1, 0), width <- 0..(max_width - 1), reduce: {[], []} do
      {indexes, masks} ->
        ending = start + width
        valid? = text_length > 0 and ending < text_length
        {[[start, ending] | indexes], [valid? | masks]}
    end
    |> then(fn {indexes, masks} -> {Enum.reverse(indexes), Enum.reverse(masks)} end)
  end

  @doc """
  Builds a GLiNER input from a loaded tokenizer.

  The Python GLiNER path uses `is_split_into_words=True`. The Elixir
  Tokenizers wrapper currently encodes strings only, so this function encodes
  `prompt <> Enum.join(split_tokens, " ")` and reconstructs the first-subword
  word mask from synthetic token offsets. The decoder still maps spans back
  through the original byte offsets.
  """
  @spec prepare(any(), String.t(), Config.t()) :: {:ok, prepared()} | {:error, term()}
  def prepare(tokenizer, text, %Config{} = config) when is_binary(text) do
    tokens = text |> TokenSplitter.split() |> limit_tokens(config.max_length)
    encoded_text = model_text(tokens)
    encoded_tokens = encoded_tokens(tokens)
    prompt = prompt_text(config.labels, config.prompt_joiner)
    input_text = prompt <> " " <> encoded_text
    text_offset = byte_size(prompt) + 1

    with {:ok, encoding} <- tokenizer_encode(tokenizer, input_text),
         ids <- encoding_values(encoding, :ids),
         attention_mask <- encoding_values(encoding, :attention_mask),
         offsets <- encoding_values(encoding, :offsets) do
      words_mask = words_mask(offsets, encoded_tokens, text_offset)
      tensors = tensors(ids, attention_mask, words_mask, length(tokens), config)

      {:ok,
       %{
         input_text: input_text,
         tokens: tokens,
         id_to_class: id_to_class(config.labels),
         tensors: tensors,
         word_token_indexes: word_token_indexes(words_mask)
       }}
    end
  end

  @doc false
  @spec limit_tokens([TokenSplitter.token()], pos_integer()) :: [TokenSplitter.token()]
  def limit_tokens(tokens, max_length)
      when is_list(tokens) and is_integer(max_length) and max_length > 0 do
    Enum.take(tokens, max_length)
  end

  @doc """
  Builds a 1-based id-to-label map matching GLiNER's class ids.
  """
  @spec id_to_class([String.t()]) :: %{pos_integer() => String.t()}
  def id_to_class(labels) do
    labels
    |> Enum.with_index(1)
    |> Map.new(fn {label, index} -> {index, label} end)
  end

  defp tensors(ids, attention_mask, words_mask, text_length, %Config{span_mode: :token_level}) do
    {
      Nx.tensor([ids], type: {:s, 64}),
      Nx.tensor([attention_mask], type: {:s, 64}),
      Nx.tensor([words_mask], type: {:s, 64}),
      Nx.tensor([[text_length]], type: {:s, 64})
    }
  end

  defp tensors(ids, attention_mask, words_mask, text_length, %Config{} = config) do
    {span_idx, span_mask} = span_indexes(text_length, config.max_width)

    {
      Nx.tensor([ids], type: {:s, 64}),
      Nx.tensor([attention_mask], type: {:s, 64}),
      Nx.tensor([words_mask], type: {:s, 64}),
      Nx.tensor([[text_length]], type: {:s, 64}),
      Nx.tensor([span_idx], type: {:s, 64}),
      Nx.tensor([span_mask], type: {:u, 8})
    }
  end

  @doc """
  Builds the text passed to the model from GLiNER split tokens.
  """
  @spec model_text([TokenSplitter.token()]) :: String.t()
  def model_text(tokens) when is_list(tokens) do
    Enum.map_join(tokens, " ", & &1.text)
  end

  @doc """
  Reconstructs GLiNER words_mask from tokenizer byte offsets.
  """
  @spec words_mask([{integer(), integer()}], [TokenSplitter.token()], non_neg_integer()) :: [
          integer()
        ]
  def words_mask(offsets, tokens, text_offset) do
    {mask, _seen} =
      Enum.map_reduce(offsets, MapSet.new(), fn {start, ending}, seen ->
        token_index = token_index_for_offset(tokens, start - text_offset, ending - text_offset)

        cond do
          is_nil(token_index) ->
            {0, seen}

          MapSet.member?(seen, token_index) ->
            {0, seen}

          true ->
            {token_index + 1, MapSet.put(seen, token_index)}
        end
      end)

    mask
  end

  defp token_index_for_offset(_tokens, _start, ending) when ending < 0, do: nil
  defp token_index_for_offset([], _start, 0), do: nil
  defp token_index_for_offset(_tokens, _start, 0), do: 0

  defp token_index_for_offset(tokens, start, ending) do
    Enum.find_index(tokens, fn token -> offsets_overlap?(start, ending, token) end) ||
      Enum.find_index(tokens, fn token -> token.start == ending end)
  end

  defp offsets_overlap?(start, ending, token) do
    start < token.end and ending > token.start
  end

  defp word_token_indexes(words_mask) do
    words_mask
    |> Enum.with_index()
    |> Enum.filter(fn {word_index, _token_index} -> word_index > 0 end)
    |> Enum.map(fn {_word_index, token_index} -> token_index end)
  end

  defp encoded_tokens(tokens) do
    tokens
    |> Enum.map_reduce(0, fn token, offset ->
      byte_length = byte_size(token.text)
      encoded_token = %{token | start: offset, end: offset + byte_length}
      {encoded_token, offset + byte_length + 1}
    end)
    |> elem(0)
  end

  defp tokenizer_encode(tokenizer, input_text) do
    Tokenizers.Tokenizer.encode(tokenizer, input_text)
  rescue
    error -> {:error, {:tokenizer_encode_failed, error.__struct__}}
  end

  defp encoding_values(encoding, :ids) do
    Tokenizers.Encoding.get_ids(encoding)
  end

  defp encoding_values(encoding, :attention_mask) do
    Tokenizers.Encoding.get_attention_mask(encoding)
  end

  defp encoding_values(encoding, :offsets) do
    Tokenizers.Encoding.get_offsets(encoding)
  end
end
