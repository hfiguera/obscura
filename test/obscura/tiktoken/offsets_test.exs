defmodule Obscura.Tiktoken.OffsetsTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken
  alias Obscura.Tiktoken.Encoding
  alias Obscura.Tiktoken.Offsets

  test "decode_with_offsets matches tiktoken offset examples" do
    enc = Tiktoken.get_encoding!("cl100k_base")

    assert decode_with_offsets(enc, "hello world") == {"hello world", [0, 5]}

    assert decode_with_offsets(enc, "hello world<|endoftext|> green cow", allowed_special: :all) ==
             {"hello world<|endoftext|> green cow", [0, 5, 11, 24, 30]}

    assert decode_with_offsets(enc, "我非常渴望与人工智能一起工作") ==
             {"我非常渴望与人工智能一起工作", [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13]}

    assert decode_with_offsets(enc, "நடிகர் சூர்யா") ==
             {"நடிகர் சூர்யா", [0, 0, 1, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 9, 10, 11, 12, 12]}

    assert decode_with_offsets(enc, " Ġ除") == {" Ġ除", [0, 1]}
  end

  test "converts character spans to byte spans" do
    assert Offsets.char_span_to_byte_span("Rachel 北京", 7, 9) == {:ok, {7, 13}}
  end

  defp decode_with_offsets(enc, text, opts \\ []) do
    tokens = Encoding.encode!(enc, text, opts)
    {:ok, result} = Encoding.decode_with_offsets(enc, tokens)
    result
  end
end
