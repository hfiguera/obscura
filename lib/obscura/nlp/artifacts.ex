defmodule Obscura.NLP.Artifacts do
  @moduledoc """
  Dependency-light NLP artifacts for analyzer scoring.

  Presidio runs NLP once and passes token, lemma, keyword, and offset artifacts
  through the analyzer. Obscura keeps the default implementation deterministic
  and dependency-free while exposing the same kind of data to context scoring
  and future recognizers.
  """

  @enforce_keys [:text, :tokens, :token_offsets, :normalized_tokens, :lemmas, :keywords]
  defstruct [
    :text,
    :tokens,
    :token_offsets,
    :normalized_tokens,
    :lemmas,
    :keywords,
    model_outputs: [],
    model_outputs_ready: false
  ]

  @type token_offset :: %{byte_start: non_neg_integer(), byte_end: non_neg_integer()}
  @type t :: %__MODULE__{
          text: String.t(),
          tokens: [String.t()],
          token_offsets: [token_offset()],
          normalized_tokens: [String.t()],
          lemmas: [String.t()],
          keywords: [String.t()],
          model_outputs: [map()],
          model_outputs_ready: boolean()
        }

  @token_regex ~r/[\p{L}\p{N}_]+(?:['-][\p{L}\p{N}_]+)*/u

  @stopwords MapSet.new(~w[
    a an and are as at be but by for from has have i in is it its my of on or our
    the this to was were will with you your
  ])

  @doc """
  Builds deterministic token artifacts from raw text.
  """
  @spec build(String.t()) :: t()
  def build(text) when is_binary(text) do
    matches = Regex.scan(@token_regex, text, return: :index)

    tokens_with_offsets =
      Enum.map(matches, fn [{start, byte_length} | _captures] ->
        token = binary_part(text, start, byte_length)
        {token, %{byte_start: start, byte_end: start + byte_length}}
      end)

    tokens = Enum.map(tokens_with_offsets, &elem(&1, 0))
    offsets = Enum.map(tokens_with_offsets, &elem(&1, 1))
    normalized = Enum.map(tokens, &normalize_token/1)

    %__MODULE__{
      text: text,
      tokens: tokens,
      token_offsets: offsets,
      normalized_tokens: normalized,
      lemmas: normalized,
      keywords: keywords(normalized),
      model_outputs: [],
      model_outputs_ready: false
    }
  end

  @doc """
  Attaches precomputed model outputs to artifacts.

  This mirrors Presidio's pattern where a model/NLP engine can run once and
  downstream recognizers consume the resulting artifacts instead of invoking
  model serving independently.
  """
  @spec put_model_outputs(t(), [map()]) :: {:ok, t()} | {:error, term()}
  def put_model_outputs(%__MODULE__{} = artifacts, outputs) when is_list(outputs) do
    if Enum.all?(outputs, &is_map/1) do
      {:ok, %{artifacts | model_outputs: outputs, model_outputs_ready: true}}
    else
      {:error, :invalid_model_outputs}
    end
  end

  def put_model_outputs(%__MODULE__{}, _outputs), do: {:error, :invalid_model_outputs}

  @doc """
  Normalizes a token for whole-word context matching.
  """
  @spec normalize_token(String.t()) :: String.t()
  def normalize_token(token) when is_binary(token) do
    token
    |> String.downcase()
    |> String.trim()
    |> String.trim_leading("_")
    |> String.trim_trailing("_")
  end

  @doc """
  Returns token indexes around a byte span.
  """
  @spec surrounding_token_indexes(t(), non_neg_integer(), non_neg_integer(), keyword()) :: [
          non_neg_integer()
        ]
  def surrounding_token_indexes(%__MODULE__{} = artifacts, start, end_offset, opts \\ []) do
    prefix_count = Keyword.get(opts, :prefix_count, 5)
    suffix_count = Keyword.get(opts, :suffix_count, 5)

    indexed_offsets = Enum.with_index(artifacts.token_offsets)

    before_indexes =
      indexed_offsets
      |> Enum.filter(fn {offset, _index} -> offset.byte_end <= start end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.take(-prefix_count)

    after_indexes =
      indexed_offsets
      |> Enum.filter(fn {offset, _index} -> offset.byte_start >= end_offset end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.take(suffix_count)

    before_indexes ++ after_indexes
  end

  @doc """
  Returns normalized surrounding token text around a byte span.
  """
  @spec surrounding_terms(t(), non_neg_integer(), non_neg_integer(), keyword()) :: [String.t()]
  def surrounding_terms(%__MODULE__{} = artifacts, start, end_offset, opts \\ []) do
    artifacts
    |> surrounding_token_indexes(start, end_offset, opts)
    |> Enum.map(&Enum.at(artifacts.normalized_tokens, &1))
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp keywords(normalized_tokens) do
    normalized_tokens
    |> Enum.reject(&(&1 == "" or MapSet.member?(@stopwords, &1)))
    |> Enum.uniq()
  end
end

defimpl Inspect, for: Obscura.NLP.Artifacts do
  import Inspect.Algebra

  def inspect(artifacts, opts) do
    safe = %{
      keyword_count: length(artifacts.keywords),
      model_output_count: length(artifacts.model_outputs),
      model_outputs_ready: artifacts.model_outputs_ready,
      text: :redacted,
      text_bytes: byte_size(artifacts.text),
      token_count: length(artifacts.tokens)
    }

    concat(["#Obscura.NLP.Artifacts<", to_doc(safe, opts), ">"])
  end
end
