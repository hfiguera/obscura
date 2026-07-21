defmodule Obscura.Tiktoken.SpecialTokensTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken
  alias Obscura.Tiktoken.Encoding

  test "raises an error for disallowed special tokens by default" do
    enc = Tiktoken.get_encoding!("cl100k_base")

    assert Encoding.encode(enc, "<|endoftext|>") ==
             {:error, {:disallowed_special_token, "<|endoftext|>"}}
  end

  test "encodes allowed special tokens as special IDs" do
    enc = Tiktoken.get_encoding!("cl100k_base")

    assert Encoding.encode!(enc, "hello <|endoftext|>", allowed_special: :all) == [
             15_339,
             220,
             100_257
           ]

    assert Encoding.special_token?(enc, 100_257)
    assert Encoding.decode_single_token_bytes(enc, 100_257) == {:ok, "<|endoftext|>"}
  end

  test "can encode special-token text as ordinary text" do
    enc = Tiktoken.get_encoding!("cl100k_base")

    tokens = Encoding.encode!(enc, "<|endoftext|>", disallowed_special: [])
    refute 100_257 in tokens
    assert Encoding.decode!(enc, tokens) == "<|endoftext|>"
  end
end
