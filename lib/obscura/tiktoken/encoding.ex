defmodule Obscura.Tiktoken.Encoding do
  @moduledoc """
  A tiktoken-compatible byte-pair encoding.
  """

  alias Obscura.Tiktoken.BPE

  @enforce_keys [
    :name,
    :pat_str,
    :pattern,
    :mergeable_ranks,
    :decoder,
    :special_tokens,
    :special_token_values,
    :special_tokens_decoder,
    :sorted_token_bytes,
    :max_token_value
  ]
  defstruct [
    :name,
    :pat_str,
    :pattern,
    :mergeable_ranks,
    :decoder,
    :special_tokens,
    :special_token_values,
    :special_tokens_decoder,
    :sorted_token_bytes,
    :explicit_n_vocab,
    :max_token_value,
    :eot_token
  ]

  @type special_selector :: :all | [String.t()] | MapSet.t(String.t())

  @type t :: %__MODULE__{
          name: String.t(),
          pat_str: String.t(),
          pattern: Regex.t(),
          mergeable_ranks: %{binary() => non_neg_integer()},
          decoder: %{non_neg_integer() => binary()},
          special_tokens: %{String.t() => non_neg_integer()},
          special_token_values: MapSet.t(non_neg_integer()),
          special_tokens_decoder: %{non_neg_integer() => binary()},
          sorted_token_bytes: [binary()],
          explicit_n_vocab: non_neg_integer() | nil,
          max_token_value: non_neg_integer(),
          eot_token: non_neg_integer() | nil
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) do
    with {:ok, name} <- fetch_string(attrs, :name),
         {:ok, pat_str} <- fetch_string(attrs, :pat_str),
         {:ok, pattern} <- compile_pattern(pat_str),
         {:ok, mergeable_ranks} <- fetch_map(attrs, :mergeable_ranks),
         {:ok, special_tokens} <- fetch_map(attrs, :special_tokens),
         {:ok, explicit_n_vocab} <- fetch_optional_integer(attrs, :explicit_n_vocab),
         decoder <- invert_map(mergeable_ranks),
         special_tokens_decoder <- invert_special_tokens(special_tokens),
         {:ok, max_token_value} <- max_token_value(mergeable_ranks, special_tokens),
         :ok <-
           validate_explicit_vocab(
             explicit_n_vocab,
             mergeable_ranks,
             special_tokens,
             max_token_value
           ) do
      {:ok,
       %__MODULE__{
         name: name,
         pat_str: pat_str,
         pattern: pattern,
         mergeable_ranks: mergeable_ranks,
         decoder: decoder,
         special_tokens: special_tokens,
         special_token_values: special_tokens |> Map.values() |> MapSet.new(),
         special_tokens_decoder: special_tokens_decoder,
         sorted_token_bytes: mergeable_ranks |> Map.keys() |> Enum.sort(),
         explicit_n_vocab: explicit_n_vocab,
         max_token_value: max_token_value,
         eot_token: Map.get(special_tokens, "<|endoftext|>")
       }}
    end
  end

  @spec encode(t(), String.t(), keyword()) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def encode(%__MODULE__{} = encoding, text, opts \\ []) when is_binary(text) do
    allowed_special = special_set(Keyword.get(opts, :allowed_special, MapSet.new()), encoding)
    disallowed_special = disallowed_special_set(opts, encoding, allowed_special)

    with :ok <- reject_disallowed_special(text, disallowed_special),
         {:ok, {tokens, _last_piece_token_len}} <-
           encode_with_last_piece(encoding, text, allowed_special) do
      {:ok, tokens}
    end
  end

  @spec encode!(t(), String.t(), keyword()) :: [non_neg_integer()]
  def encode!(%__MODULE__{} = encoding, text, opts \\ []) do
    case encode(encoding, text, opts) do
      {:ok, tokens} -> tokens
      {:error, _reason} -> raise ArgumentError, "failed to encode text"
    end
  end

  @spec encode_ordinary(t(), String.t()) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def encode_ordinary(%__MODULE__{} = encoding, text) when is_binary(text) do
    encode_segment(encoding, text)
  end

  @spec encode_ordinary!(t(), String.t()) :: [non_neg_integer()]
  def encode_ordinary!(%__MODULE__{} = encoding, text) do
    case encode_ordinary(encoding, text) do
      {:ok, tokens} ->
        tokens

      {:error, _reason} ->
        raise ArgumentError, "failed to ordinary-encode text"
    end
  end

  @spec encode_single_token(t(), String.t() | binary()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def encode_single_token(%__MODULE__{} = encoding, text_or_bytes)
      when is_binary(text_or_bytes) do
    cond do
      Map.has_key?(encoding.mergeable_ranks, text_or_bytes) ->
        {:ok, Map.fetch!(encoding.mergeable_ranks, text_or_bytes)}

      Map.has_key?(encoding.special_tokens, text_or_bytes) ->
        {:ok, Map.fetch!(encoding.special_tokens, text_or_bytes)}

      true ->
        {:error, :unknown_token_bytes}
    end
  end

  @spec encode_single_piece(t(), String.t() | binary()) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def encode_single_piece(%__MODULE__{} = encoding, text_or_bytes)
      when is_binary(text_or_bytes) do
    BPE.encode_piece(text_or_bytes, encoding.mergeable_ranks)
  end

  @spec decode_bytes(t(), [non_neg_integer()]) :: {:ok, binary()} | {:error, term()}
  def decode_bytes(%__MODULE__{} = encoding, tokens) when is_list(tokens) do
    case decode_token_parts(encoding, tokens) do
      {:ok, parts} -> {:ok, IO.iodata_to_binary(parts)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec decode_bytes!(t(), [non_neg_integer()]) :: binary()
  def decode_bytes!(%__MODULE__{} = encoding, tokens) do
    case decode_bytes(encoding, tokens) do
      {:ok, bytes} -> bytes
      {:error, _reason} -> raise ArgumentError, "failed to decode tokens"
    end
  end

  @spec decode(t(), [non_neg_integer()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def decode(%__MODULE__{} = encoding, tokens, opts \\ []) do
    errors = Keyword.get(opts, :errors, :replace)

    with {:ok, bytes} <- decode_bytes(encoding, tokens) do
      case errors do
        :replace -> {:ok, String.replace_invalid(bytes)}
        :strict -> strict_decode(bytes)
        _other -> {:error, :unsupported_decode_errors}
      end
    end
  end

  @spec decode!(t(), [non_neg_integer()], keyword()) :: String.t()
  def decode!(%__MODULE__{} = encoding, tokens, opts \\ []) do
    case decode(encoding, tokens, opts) do
      {:ok, text} -> text
      {:error, _reason} -> raise ArgumentError, "failed to decode tokens"
    end
  end

  @spec decode_single_token_bytes(t(), non_neg_integer()) :: {:ok, binary()} | {:error, term()}
  def decode_single_token_bytes(%__MODULE__{} = encoding, token) when is_integer(token) do
    cond do
      Map.has_key?(encoding.decoder, token) ->
        {:ok, Map.fetch!(encoding.decoder, token)}

      Map.has_key?(encoding.special_tokens_decoder, token) ->
        {:ok, Map.fetch!(encoding.special_tokens_decoder, token)}

      true ->
        {:error, {:unknown_token, token}}
    end
  end

  @spec decode_tokens_bytes(t(), [non_neg_integer()]) :: {:ok, [binary()]} | {:error, term()}
  def decode_tokens_bytes(%__MODULE__{} = encoding, tokens) when is_list(tokens) do
    decode_token_parts(encoding, tokens)
  end

  defp decode_token_parts(encoding, tokens) do
    tokens
    |> Enum.reduce_while({:ok, []}, fn token, {:ok, parts} ->
      case decode_single_token_bytes(encoding, token) do
        {:ok, bytes} -> {:cont, {:ok, [bytes | parts]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec decode_with_offsets(t(), [non_neg_integer()]) ::
          {:ok, {String.t(), [non_neg_integer()]}} | {:error, term()}
  def decode_with_offsets(%__MODULE__{} = encoding, tokens) when is_list(tokens) do
    with {:ok, token_bytes} <- decode_tokens_bytes(encoding, tokens),
         {:ok, text} <- token_bytes |> IO.iodata_to_binary() |> strict_decode() do
      {offsets, _text_len} =
        Enum.map_reduce(token_bytes, 0, fn token, text_len ->
          offset = max(0, text_len - continuation_byte?(token))

          next_len =
            text_len + Enum.count(:binary.bin_to_list(token), &(not utf8_continuation_byte?(&1)))

          {offset, next_len}
        end)

      {:ok, {text, offsets}}
    end
  end

  @spec token_byte_values(t()) :: [binary()]
  def token_byte_values(%__MODULE__{} = encoding), do: encoding.sorted_token_bytes

  @spec special_token?(t(), non_neg_integer()) :: boolean()
  def special_token?(%__MODULE__{} = encoding, token),
    do: MapSet.member?(encoding.special_token_values, token)

  @spec n_vocab(t()) :: non_neg_integer()
  def n_vocab(%__MODULE__{} = encoding), do: encoding.max_token_value + 1

  defp encode_with_last_piece(%__MODULE__{} = encoding, text, allowed_special) do
    do_encode(encoding, text, allowed_special, 0, [], 0)
  end

  defp do_encode(encoding, text, allowed_special, start, acc, last_piece_token_len) do
    if start >= byte_size(text) do
      {:ok, {Enum.reverse(acc), last_piece_token_len}}
    else
      encode_next_piece(encoding, text, allowed_special, start, acc)
    end
  end

  defp encode_next_piece(encoding, text, allowed_special, start, acc) do
    case next_allowed_special(text, allowed_special, start) do
      nil -> encode_final_piece(encoding, text, start, acc)
      special -> encode_special_piece(encoding, text, allowed_special, start, acc, special)
    end
  end

  defp encode_final_piece(encoding, text, start, acc) do
    with {:ok, tokens} <-
           encode_segment(encoding, binary_part(text, start, byte_size(text) - start)) do
      {:ok, {Enum.reverse(acc, tokens), length(tokens)}}
    end
  end

  defp encode_special_piece(
         encoding,
         text,
         allowed_special,
         start,
         acc,
         {special_start, special_end, token}
       ) do
    segment = binary_part(text, start, special_start - start)

    with {:ok, segment_tokens} <- encode_segment(encoding, segment) do
      do_encode(
        encoding,
        text,
        allowed_special,
        special_end,
        [token | Enum.reverse(segment_tokens, acc)],
        0
      )
    end
  end

  defp encode_segment(_encoding, ""), do: {:ok, []}

  defp encode_segment(%__MODULE__{} = encoding, text) do
    tokens =
      encoding.pattern
      |> Regex.scan(text)
      |> Enum.map(&List.first/1)
      |> Enum.flat_map(fn piece ->
        case Map.fetch(encoding.mergeable_ranks, piece) do
          {:ok, token} -> [token]
          :error -> BPE.encode_piece!(piece, encoding.mergeable_ranks)
        end
      end)

    {:ok, tokens}
  rescue
    error -> {:error, {:encode_failed, error.__struct__}}
  end

  defp next_allowed_special(_text, allowed_special, _start) when map_size(allowed_special) == 0 do
    nil
  end

  defp next_allowed_special(text, allowed_special, start) do
    allowed_special
    |> Enum.reduce(nil, fn {special, token}, best ->
      suffix = binary_part(text, start, byte_size(text) - start)

      case :binary.match(suffix, special) do
        {relative_start, length} ->
          candidate = {start + relative_start, start + relative_start + length, token}
          choose_earlier_special(best, candidate)

        :nomatch ->
          best
      end
    end)
  end

  defp choose_earlier_special(nil, candidate), do: candidate

  defp choose_earlier_special(
         {best_start, best_end, _best_token} = best,
         {start, ending, _token} = candidate
       ) do
    cond do
      start < best_start -> candidate
      start == best_start and ending > best_end -> candidate
      true -> best
    end
  end

  defp reject_disallowed_special(_text, disallowed_special)
       when map_size(disallowed_special) == 0, do: :ok

  defp reject_disallowed_special(text, disallowed_special) do
    case Enum.find(disallowed_special, fn {special, _token} ->
           :binary.match(text, special) != :nomatch
         end) do
      nil -> :ok
      {special, _token} -> {:error, {:disallowed_special_token, special}}
    end
  end

  defp disallowed_special_set(opts, encoding, allowed_special) do
    case Keyword.get(opts, :disallowed_special, :all) do
      :all -> Map.drop(encoding.special_tokens, Map.keys(allowed_special))
      values -> special_set(values, encoding)
    end
  end

  defp special_set(:all, encoding), do: encoding.special_tokens

  defp special_set(values, encoding) when is_list(values) do
    values
    |> MapSet.new()
    |> special_set(encoding)
  end

  defp special_set(%MapSet{} = values, encoding) do
    encoding.special_tokens
    |> Enum.filter(fn {special, _token} -> MapSet.member?(values, special) end)
    |> Map.new()
  end

  defp special_set(_other, _encoding) do
    raise ArgumentError, "invalid special token selector"
  end

  defp compile_pattern(pattern) do
    case Regex.compile(pattern, "u") do
      {:ok, regex} -> {:ok, regex}
      {:error, reason} -> {:error, {:regex_compile_failed, pattern, reason}}
    end
  end

  defp fetch_string(attrs, key) do
    case Keyword.fetch(attrs, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_encoding_field, key, value}}
      :error -> {:error, {:missing_encoding_field, key}}
    end
  end

  defp fetch_map(attrs, key) do
    case Keyword.fetch(attrs, key) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_encoding_field, key, value}}
      :error -> {:error, {:missing_encoding_field, key}}
    end
  end

  defp fetch_optional_integer(attrs, key) do
    case Keyword.fetch(attrs, key) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} when is_integer(value) and value > 0 -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_encoding_field, key, value}}
      :error -> {:ok, nil}
    end
  end

  defp invert_map(map), do: Map.new(map, fn {key, value} -> {value, key} end)
  defp invert_special_tokens(map), do: Map.new(map, fn {key, value} -> {value, key} end)

  defp max_token_value(mergeable_ranks, special_tokens) do
    values = Map.values(mergeable_ranks) ++ Map.values(special_tokens)

    if values == [] do
      {:error, :empty_encoding}
    else
      {:ok, Enum.max(values)}
    end
  end

  defp validate_explicit_vocab(nil, _mergeable_ranks, _special_tokens, _max_token_value), do: :ok

  defp validate_explicit_vocab(explicit_n_vocab, mergeable_ranks, special_tokens, max_token_value) do
    cond do
      map_size(mergeable_ranks) + map_size(special_tokens) != explicit_n_vocab ->
        {:error, {:explicit_vocab_size_mismatch, explicit_n_vocab}}

      max_token_value != explicit_n_vocab - 1 ->
        {:error, {:explicit_vocab_max_token_mismatch, explicit_n_vocab, max_token_value}}

      true ->
        :ok
    end
  end

  defp strict_decode(bytes) do
    if String.valid?(bytes), do: {:ok, bytes}, else: {:error, :invalid_utf8}
  end

  defp continuation_byte?(<<first, _rest::binary>>) do
    if utf8_continuation_byte?(first), do: 1, else: 0
  end

  defp continuation_byte?(<<>>), do: 0

  defp utf8_continuation_byte?(byte), do: byte >= 0x80 and byte < 0xC0
end
