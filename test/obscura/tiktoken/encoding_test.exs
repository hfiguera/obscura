defmodule Obscura.Tiktoken.EncodingTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken
  alias Obscura.Tiktoken.Encoding

  test "encodes and decodes simple public examples" do
    gpt2 = Tiktoken.get_encoding!("gpt2")
    cl100k = Tiktoken.get_encoding!("cl100k_base")

    assert Encoding.encode(gpt2, "hello world") == {:ok, [31_373, 995]}
    assert Encoding.decode(gpt2, [31_373, 995]) == {:ok, "hello world"}

    assert Encoding.encode(cl100k, "hello world") == {:ok, [15_339, 1917]}
    assert Encoding.decode(cl100k, [15_339, 1917]) == {:ok, "hello world"}
  end

  test "encodes repeated digit examples from tiktoken" do
    enc = Tiktoken.get_encoding!("gpt2")

    assert Encoding.encode!(enc, "0") == [15]
    assert Encoding.encode!(enc, "00") == [405]
    assert Encoding.encode!(enc, "000") == [830]
    assert Encoding.encode!(enc, "0000") == [2388]
    assert Encoding.encode!(enc, "00000") == [20_483]
    assert Encoding.encode!(enc, "000000") == [10_535]
    assert Encoding.encode!(enc, "0000000") == [24_598]
    assert Encoding.encode!(enc, "00000000") == [8269]
    assert Encoding.encode!(enc, "000000000") == [10_535, 830]
  end

  test "matches newline-sensitive cl100k regex examples" do
    enc = Tiktoken.get_encoding!("cl100k_base")

    assert Encoding.encode!(enc, "rer") == [38_149]
    assert Encoding.encode!(enc, "'rer") == [2351, 81]
    assert Encoding.encode!(enc, "today\n ") == [31_213, 198, 220]
    assert Encoding.encode!(enc, "today\n \n") == [31_213, 27_907]
    assert Encoding.encode!(enc, "today\n  \n") == [31_213, 14_211]
  end

  test "roundtrips representative text across supported encodings" do
    values = [
      "hello",
      "hello world",
      "hello  ",
      " hello",
      "Please call Rachel at +1 415 555 0100.",
      "请考试我的软件！12345"
    ]

    for name <- Tiktoken.list_encoding_names(), value <- values do
      enc = Tiktoken.get_encoding!(name)
      assert Encoding.decode!(enc, Encoding.encode!(enc, value)) == value
    end
  end

  test "single token bytes roundtrip for first known tokens" do
    enc = Tiktoken.get_encoding!("cl100k_base")

    for token <- 0..1_000 do
      case Encoding.decode_single_token_bytes(enc, token) do
        {:ok, bytes} -> assert Encoding.encode_single_token(enc, bytes) == {:ok, token}
        {:error, {:unknown_token, ^token}} -> :ok
      end
    end
  end
end
