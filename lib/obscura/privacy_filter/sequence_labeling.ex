defmodule Obscura.PrivacyFilter.SequenceLabeling do
  @moduledoc """
  Windowing and aggregation helpers for privacy-filter token classification.
  """

  defmodule TokenizedExample do
    @moduledoc "A tokenized privacy-filter example before windowing."
    @enforce_keys [:tokens, :labels, :example_id, :text]
    defstruct [:tokens, :labels, :example_id, :text]

    @type t :: %__MODULE__{
            tokens: tuple(),
            labels: tuple(),
            example_id: String.t(),
            text: String.t()
          }
  end

  defmodule Window do
    @moduledoc "A fixed-size privacy-filter token window."
    @enforce_keys [:example_id, :tokens, :labels, :offsets, :token_example_ids, :mask]
    defstruct [:example_id, :tokens, :labels, :offsets, :token_example_ids, :mask]

    @type t :: %__MODULE__{
            example_id: String.t(),
            tokens: tuple(),
            labels: tuple(),
            offsets: tuple(),
            token_example_ids: tuple(),
            mask: tuple()
          }
  end

  defmodule Aggregation do
    @moduledoc "Accumulated token predictions across overlapping windows."
    defstruct logprob_logsumexp: [], counts: [], labels: [], token_ids: [], length: 0

    @type t :: %__MODULE__{
            logprob_logsumexp: [float() | nil],
            counts: [non_neg_integer()],
            labels: [integer() | nil],
            token_ids: [integer() | nil],
            length: non_neg_integer()
          }
  end

  alias __MODULE__.Aggregation
  alias __MODULE__.TokenizedExample
  alias __MODULE__.Window

  @spec example_to_windows(TokenizedExample.t(), pos_integer(), keyword()) ::
          {:ok, [Window.t()]} | {:error, term()}
  def example_to_windows(example, window_size, opts \\ [])

  def example_to_windows(%TokenizedExample{} = example, window_size, opts)
      when is_integer(window_size) and window_size > 0 do
    tokens = Tuple.to_list(example.tokens)
    labels = Tuple.to_list(example.labels)

    if length(tokens) != length(labels) do
      {:error, :mismatched_token_and_label_lengths}
    else
      {:ok, do_windows(example, tokens, labels, window_size, opts)}
    end
  end

  def example_to_windows(_example, _window_size, _opts), do: {:error, :invalid_window_size}

  @spec example_to_bucketed_windows(TokenizedExample.t(), [pos_integer()], keyword()) ::
          {:ok, [Window.t()]} | {:error, term()}
  def example_to_bucketed_windows(example, buckets, opts \\ [])

  def example_to_bucketed_windows(%TokenizedExample{} = example, buckets, opts) do
    with :ok <- validate_buckets(buckets),
         {:ok, pad_token_id} <- Keyword.fetch(opts, :pad_token_id) do
      tokens = Tuple.to_list(example.tokens)
      labels = Tuple.to_list(example.labels)

      if length(tokens) == length(labels) do
        {:ok, do_bucketed_windows(example, tokens, labels, buckets, pad_token_id, opts)}
      else
        {:error, :mismatched_token_and_label_lengths}
      end
    else
      :error -> {:error, :missing_bucket_pad_token_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def example_to_bucketed_windows(_example, _buckets, _opts),
    do: {:error, :invalid_sequence_length_buckets}

  @spec new_aggregation() :: Aggregation.t()
  def new_aggregation, do: %Aggregation{}

  @spec record_token_id(Aggregation.t(), non_neg_integer(), integer(), String.t()) ::
          {:ok, Aggregation.t()} | {:error, term()}
  def record_token_id(%Aggregation{} = aggregation, index, token_id, _example_id) do
    aggregation = ensure_capacity(aggregation, index)
    existing = Enum.at(aggregation.token_ids, index)

    cond do
      is_nil(existing) ->
        {:ok, %{aggregation | token_ids: List.replace_at(aggregation.token_ids, index, token_id)}}

      existing == token_id ->
        {:ok, aggregation}

      true ->
        {:error, {:conflicting_token_id, index}}
    end
  end

  @spec ensure_capacity(Aggregation.t(), non_neg_integer()) :: Aggregation.t()
  def ensure_capacity(%Aggregation{} = aggregation, index) do
    needed = index + 1 - length(aggregation.logprob_logsumexp)

    if needed <= 0 do
      aggregation
    else
      %{
        aggregation
        | logprob_logsumexp: aggregation.logprob_logsumexp ++ List.duplicate(nil, needed),
          counts: aggregation.counts ++ List.duplicate(0, needed),
          labels: aggregation.labels ++ List.duplicate(nil, needed),
          token_ids: aggregation.token_ids ++ List.duplicate(nil, needed)
      }
    end
  end

  @spec logaddexp(float(), float()) :: float()
  def logaddexp(left, right) when is_number(left) and is_number(right) do
    max_value = max(left, right)
    max_value + :math.log(:math.exp(left - max_value) + :math.exp(right - max_value))
  end

  defp do_windows(example, [], _labels, _window_size, _opts) do
    [
      %Window{
        example_id: example.example_id,
        tokens: {},
        labels: {},
        offsets: {},
        token_example_ids: {},
        mask: {}
      }
    ]
  end

  defp do_windows(example, tokens, labels, window_size, opts) do
    tokens
    |> Enum.chunk_every(window_size)
    |> Enum.with_index()
    |> Enum.map(fn {window_tokens, window_index} ->
      start = window_index * window_size
      window_labels = Enum.slice(labels, start, length(window_tokens))
      offsets = Enum.to_list(start..(start + length(window_tokens) - 1))

      {padded_tokens, padded_labels, padded_offsets, mask} =
        maybe_pad_window(window_tokens, window_labels, offsets, window_size, opts)

      build_window(example, padded_tokens, padded_labels, padded_offsets, mask)
    end)
  end

  defp do_bucketed_windows(example, [], _labels, _buckets, _pad_token_id, _opts) do
    [
      %Window{
        example_id: example.example_id,
        tokens: {},
        labels: {},
        offsets: {},
        token_example_ids: {},
        mask: {}
      }
    ]
  end

  defp do_bucketed_windows(example, tokens, labels, buckets, pad_token_id, opts) do
    maximum = List.last(buckets)

    tokens
    |> Enum.chunk_every(maximum)
    |> Enum.with_index()
    |> Enum.map(fn {window_tokens, window_index} ->
      start = window_index * maximum
      actual_length = length(window_tokens)
      bucket = Enum.find(buckets, &(&1 >= actual_length))
      window_labels = Enum.slice(labels, start, actual_length)
      offsets = Enum.to_list(start..(start + actual_length - 1))

      {padded_tokens, padded_labels, padded_offsets, mask} =
        pad_window(
          window_tokens,
          window_labels,
          offsets,
          bucket,
          pad_token_id,
          Keyword.get(opts, :pad_label, 0)
        )

      build_window(example, padded_tokens, padded_labels, padded_offsets, mask)
    end)
  end

  defp build_window(example, tokens, labels, offsets, mask) do
    %Window{
      example_id: example.example_id,
      tokens: List.to_tuple(tokens),
      labels: List.to_tuple(labels),
      offsets: List.to_tuple(offsets),
      token_example_ids: token_example_ids(example.example_id, mask) |> List.to_tuple(),
      mask: List.to_tuple(mask)
    }
  end

  defp maybe_pad_window(window_tokens, window_labels, offsets, window_size, opts) do
    case Keyword.fetch(opts, :pad_token_id) do
      {:ok, pad_token_id} ->
        pad_window(
          window_tokens,
          window_labels,
          offsets,
          window_size,
          pad_token_id,
          Keyword.get(opts, :pad_label, 0)
        )

      :error ->
        {window_tokens, window_labels, offsets, List.duplicate(1, length(window_tokens))}
    end
  end

  defp pad_window(window_tokens, window_labels, offsets, target_length, pad_token_id, pad_label) do
    pad_count = max(target_length - length(window_tokens), 0)

    {
      window_tokens ++ List.duplicate(pad_token_id, pad_count),
      window_labels ++ List.duplicate(pad_label, pad_count),
      offsets ++ List.duplicate(nil, pad_count),
      List.duplicate(1, length(window_tokens)) ++ List.duplicate(0, pad_count)
    }
  end

  defp validate_buckets(buckets) when is_list(buckets) and buckets != [] do
    valid? =
      Enum.all?(buckets, &(is_integer(&1) and &1 > 0)) and
        buckets == Enum.sort(Enum.uniq(buckets))

    if valid?, do: :ok, else: {:error, :invalid_sequence_length_buckets}
  end

  defp validate_buckets(_buckets), do: {:error, :invalid_sequence_length_buckets}

  defp token_example_ids(example_id, mask) do
    Enum.map(mask, fn
      1 -> example_id
      true -> example_id
      _pad -> nil
    end)
  end
end

defimpl Inspect, for: Obscura.PrivacyFilter.SequenceLabeling.TokenizedExample do
  import Inspect.Algebra

  def inspect(example, opts) do
    safe = %{example_id: :redacted, text: :redacted, token_count: tuple_size(example.tokens)}
    concat(["#Obscura.PrivacyFilter.TokenizedExample<", to_doc(safe, opts), ">"])
  end
end

defimpl Inspect, for: Obscura.PrivacyFilter.SequenceLabeling.Window do
  import Inspect.Algebra

  def inspect(window, opts) do
    safe = %{example_id: :redacted, token_count: tuple_size(window.tokens)}
    concat(["#Obscura.PrivacyFilter.Window<", to_doc(safe, opts), ">"])
  end
end

defimpl Inspect, for: Obscura.PrivacyFilter.SequenceLabeling.Aggregation do
  import Inspect.Algebra

  def inspect(aggregation, opts) do
    safe = %{length: aggregation.length}
    concat(["#Obscura.PrivacyFilter.Aggregation<", to_doc(safe, opts), ">"])
  end
end
