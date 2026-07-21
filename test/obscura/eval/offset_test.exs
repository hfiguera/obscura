defmodule Obscura.Eval.OffsetTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Offset

  @cases [
    {"ASCII before span", "Contact jane@example.com", "jane@example.com"},
    {"Latin style name before span", "Jose writes to jane@example.com", "jane@example.com"},
    {"Accented character before span", "José writes to jane@example.com", "jane@example.com"},
    {"Emoji before span", "Wave 👋 jane@example.com", "jane@example.com"},
    {"Combining mark before span", "Café jane@example.com", "jane@example.com"},
    {"Multiline LF", "Line one\nEmail jane@example.com", "jane@example.com"},
    {"Multiline CRLF", "Line one\r\nEmail jane@example.com", "jane@example.com"}
  ]

  test "converts byte and character offsets for required Unicode cases" do
    for {_name, text, value} <- @cases do
      {byte_start, _length} = :binary.match(text, value)
      byte_end = byte_start + byte_size(value)

      assert {:ok, char_start} = Offset.byte_to_char(text, byte_start)
      assert {:ok, char_end} = Offset.byte_to_char(text, byte_end)
      assert {:ok, ^byte_start} = Offset.char_to_byte(text, char_start)
      assert {:ok, ^byte_end} = Offset.char_to_byte(text, char_end)
      assert {:ok, ^value} = Offset.slice_bytes(text, byte_start, byte_end)

      span = %{
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value
      }

      assert :ok = Offset.validate_span(text, span)
    end
  end

  test "rejects invalid offsets" do
    text = "Contact jane@example.com"

    assert {:error, {:empty_or_reversed_byte_range, 5, 5}} =
             Offset.validate_span(text, %{byte_start: 5, byte_end: 5, value: "x"})

    assert {:error, {:byte_range_out_of_bounds, 0, 200, _size}} =
             Offset.validate_span(text, %{byte_start: 0, byte_end: 200, value: text})
  end
end
