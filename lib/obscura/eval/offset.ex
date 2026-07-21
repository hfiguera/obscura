defmodule Obscura.Eval.Offset do
  @moduledoc """
  Byte and character offset helpers for fixtures and evaluation datasets.
  """

  @type span :: %{
          optional(:byte_start) => non_neg_integer(),
          optional(:byte_end) => non_neg_integer(),
          optional(:char_start) => non_neg_integer() | nil,
          optional(:char_end) => non_neg_integer() | nil,
          optional(:value) => String.t() | nil
        }

  @doc """
  Converts an exclusive byte offset to a character offset.
  """
  @spec byte_to_char(String.t(), non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def byte_to_char(text, byte_offset) when is_binary(text) and is_integer(byte_offset) do
    cond do
      byte_offset < 0 ->
        {:error, {:invalid_byte_offset, byte_offset}}

      byte_offset > byte_size(text) ->
        {:error, {:invalid_byte_offset, byte_offset}}

      true ->
        prefix = binary_part(text, 0, byte_offset)
        rest = binary_part(text, byte_offset, byte_size(text) - byte_offset)

        if String.valid?(prefix) and String.valid?(rest) do
          {:ok, codepoint_length(prefix)}
        else
          {:error, {:byte_offset_not_on_boundary, byte_offset}}
        end
    end
  end

  @doc """
  Converts an exclusive character offset to a byte offset.
  """
  @spec char_to_byte(String.t(), non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def char_to_byte(text, char_offset) when is_binary(text) and is_integer(char_offset) do
    cond do
      char_offset < 0 ->
        {:error, {:invalid_char_offset, char_offset}}

      char_offset > codepoint_length(text) ->
        {:error, {:invalid_char_offset, char_offset}}

      true ->
        prefix =
          text
          |> String.codepoints()
          |> Enum.take(char_offset)
          |> Enum.join()

        {:ok, byte_size(prefix)}
    end
  end

  @doc """
  Slices text by byte offsets.
  """
  @spec slice_bytes(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def slice_bytes(text, byte_start, byte_end)
      when is_binary(text) and is_integer(byte_start) and is_integer(byte_end) do
    if byte_start < 0 or byte_end < 0 or byte_start > byte_end or byte_end > byte_size(text) do
      {:error, {:invalid_byte_range, byte_start, byte_end}}
    else
      prefix_bytes = byte_start
      value_bytes = byte_end - byte_start

      <<_prefix::binary-size(^prefix_bytes), value::binary-size(^value_bytes), _rest::binary>> =
        text

      {:ok, value}
    end
  rescue
    MatchError -> {:error, {:byte_range_not_on_boundary, byte_start, byte_end}}
  end

  @doc """
  Validates offsets and expected value for a fixture span.
  """
  @spec validate_span(String.t(), span()) :: :ok | {:error, term()}
  def validate_span(text, span) when is_binary(text) and is_map(span) do
    with {:ok, byte_start} <- fetch_integer(span, :byte_start),
         {:ok, byte_end} <- fetch_integer(span, :byte_end),
         :ok <- validate_byte_range(text, byte_start, byte_end),
         :ok <- validate_value(text, span, byte_start, byte_end) do
      validate_char_offsets(text, span, byte_start, byte_end)
    end
  end

  defp validate_byte_range(text, byte_start, byte_end) do
    cond do
      byte_start < 0 or byte_end < 0 ->
        {:error, {:negative_byte_offset, byte_start, byte_end}}

      byte_start >= byte_end ->
        {:error, {:empty_or_reversed_byte_range, byte_start, byte_end}}

      byte_end > byte_size(text) ->
        {:error, {:byte_range_out_of_bounds, byte_start, byte_end, byte_size(text)}}

      true ->
        case slice_bytes(text, byte_start, byte_end) do
          {:ok, _value} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_value(text, span, byte_start, byte_end) do
    case Map.get(span, :value) do
      nil ->
        :ok

      value when is_binary(value) ->
        case slice_bytes(text, byte_start, byte_end) do
          {:ok, ^value} -> :ok
          {:ok, actual} -> {:error, {:value_mismatch, expected: value, actual: actual}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_char_offsets(text, span, byte_start, byte_end) do
    char_start = Map.get(span, :char_start)
    char_end = Map.get(span, :char_end)

    cond do
      is_nil(char_start) and is_nil(char_end) ->
        :ok

      is_integer(char_start) and is_integer(char_end) ->
        validate_char_byte_match(text, char_start, char_end, byte_start, byte_end)

      true ->
        {:error, {:invalid_char_offsets, char_start, char_end}}
    end
  end

  defp validate_char_byte_match(text, char_start, char_end, byte_start, byte_end) do
    with {:ok, expected_byte_start} <- char_to_byte(text, char_start),
         {:ok, expected_byte_end} <- char_to_byte(text, char_end) do
      compare_char_byte_offsets(
        {char_start, char_end},
        {byte_start, byte_end},
        {expected_byte_start, expected_byte_end}
      )
    end
  end

  defp compare_char_byte_offsets(_char_offsets, byte_offsets, byte_offsets), do: :ok

  defp compare_char_byte_offsets(char_offsets, byte_offsets, expected_byte_offsets) do
    {:error,
     {:char_byte_offset_mismatch,
      char: char_offsets, byte: byte_offsets, expected_byte: expected_byte_offsets}}
  end

  defp fetch_integer(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_integer, key, value}}
      :error -> {:error, {:missing_key, key}}
    end
  end

  defp codepoint_length(text), do: text |> String.to_charlist() |> length()
end
