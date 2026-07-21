defmodule Obscura.Tiktoken.Offsets do
  @moduledoc false

  alias Obscura.Tiktoken.Encoding

  @spec token_char_ranges([non_neg_integer()], Encoding.t()) ::
          {:ok, {String.t(), [non_neg_integer()], [non_neg_integer()]}} | {:error, term()}
  def token_char_ranges(token_ids, %Encoding{} = encoding) when is_list(token_ids) do
    with {:ok, token_bytes} <- Encoding.decode_tokens_bytes(encoding, token_ids) do
      decoded_text = token_bytes |> IO.iodata_to_binary() |> String.replace_invalid()
      char_ranges = character_byte_ranges(decoded_text)

      {starts, endings, _cursor} =
        Enum.reduce(token_bytes, {[], [], 0}, fn raw_bytes, {starts, endings, cursor} ->
          token_start = cursor
          token_end = token_start + byte_size(raw_bytes)
          start_index = first_char_after_byte_end(char_ranges, token_start)
          end_index = first_char_start_at_or_after(char_ranges, token_end)
          end_index = max(end_index, start_index)
          {[start_index | starts], [end_index | endings], token_end}
        end)

      {:ok, {decoded_text, Enum.reverse(starts), Enum.reverse(endings)}}
    end
  end

  @spec char_span_to_byte_span(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def char_span_to_byte_span(text, char_start, char_end)
      when is_binary(text) and is_integer(char_start) and is_integer(char_end) do
    graphemes = String.graphemes(text)

    if char_start <= char_end and char_start >= 0 and char_end <= length(graphemes) do
      byte_start = graphemes |> Enum.take(char_start) |> Enum.join() |> byte_size()
      byte_end = graphemes |> Enum.take(char_end) |> Enum.join() |> byte_size()
      {:ok, {byte_start, byte_end}}
    else
      {:error, {:invalid_char_span, char_start, char_end}}
    end
  end

  defp character_byte_ranges(text) do
    text
    |> String.graphemes()
    |> Enum.map_reduce(0, fn char, cursor ->
      ending = cursor + byte_size(char)
      {{cursor, ending}, ending}
    end)
    |> elem(0)
  end

  defp first_char_after_byte_end(ranges, byte_offset) do
    Enum.find_index(ranges, fn {_start, ending} -> ending > byte_offset end) || length(ranges)
  end

  defp first_char_start_at_or_after(ranges, byte_offset) do
    Enum.find_index(ranges, fn {start, _ending} -> start >= byte_offset end) || length(ranges)
  end
end
