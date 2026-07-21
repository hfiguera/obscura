defmodule Obscura.Tiktoken.UpstreamPublicTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken
  alias Obscura.Tiktoken.Encoding

  @fixture_path Path.expand("../../fixtures/tiktoken/parity/generated.json", __DIR__)

  test "matches upstream simple public examples" do
    gpt2 = Tiktoken.get_encoding!("gpt2")
    cl100k = Tiktoken.get_encoding!("cl100k_base")

    assert Encoding.encode!(gpt2, "hello world") == [31_373, 995]
    assert Encoding.decode!(gpt2, [31_373, 995]) == "hello world"

    assert Encoding.encode!(gpt2, "hello <|endoftext|>", allowed_special: :all) == [
             31_373,
             220,
             50_256
           ]

    assert Encoding.encode!(cl100k, "hello world") == [15_339, 1917]
    assert Encoding.decode!(cl100k, [15_339, 1917]) == "hello world"

    assert Encoding.encode!(cl100k, "hello <|endoftext|>", allowed_special: :all) == [
             15_339,
             220,
             100_257
           ]
  end

  test "matches upstream model to encoding mappings relevant to Obscura" do
    assert {:ok, "gpt2"} = Tiktoken.encoding_name_for_model("gpt2")
    assert {:ok, "p50k_base"} = Tiktoken.encoding_name_for_model("text-davinci-003")
    assert {:ok, "p50k_edit"} = Tiktoken.encoding_name_for_model("text-davinci-edit-001")
    assert {:ok, "cl100k_base"} = Tiktoken.encoding_name_for_model("gpt-3.5-turbo-0301")
    assert {:ok, "cl100k_base"} = Tiktoken.encoding_name_for_model("gpt-4")
    assert {:ok, "o200k_base"} = Tiktoken.encoding_name_for_model("gpt-4o")
    assert {:ok, "o200k_harmony"} = Tiktoken.encoding_name_for_model("gpt-oss-120b")
  end

  test "matches upstream repeated digit examples" do
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
    assert Encoding.encode!(enc, "0000000000") == [8269, 405]
    assert Encoding.encode!(enc, "00000000000") == [8269, 830]
    assert Encoding.encode!(enc, "000000000000") == [8269, 2388]
    assert Encoding.encode!(enc, "0000000000000") == [8269, 20_483]
    assert Encoding.encode!(enc, "00000000000000") == [8269, 10_535]
    assert Encoding.encode!(enc, "000000000000000") == [8269, 24_598]
    assert Encoding.encode!(enc, "0000000000000000") == [25_645]
    assert Encoding.encode!(enc, "00000000000000000") == [8269, 10_535, 830]
  end

  test "matches upstream special-token controls" do
    enc = Tiktoken.get_encoding!("cl100k_base")

    assert {:ok, eot} = Encoding.encode_single_token(enc, "<|endoftext|>")
    assert eot == enc.eot_token
    assert {:ok, fip} = Encoding.encode_single_token(enc, "<|fim_prefix|>")
    assert {:ok, fim} = Encoding.encode_single_token(enc, "<|fim_middle|>")

    text = "<|endoftext|> hello <|fim_prefix|> there <|fim_middle|>"

    ordinary_tokens = Encoding.encode!(enc, text, disallowed_special: [])
    refute eot in ordinary_tokens
    refute fip in ordinary_tokens
    refute fim in ordinary_tokens

    all_special_tokens = Encoding.encode!(enc, text, allowed_special: :all)
    assert eot in all_special_tokens
    assert fip in all_special_tokens
    assert fim in all_special_tokens

    prefix_tokens =
      Encoding.encode!(enc, text,
        allowed_special: ["<|fim_prefix|>"],
        disallowed_special: []
      )

    refute eot in prefix_tokens
    assert fip in prefix_tokens
    refute fim in prefix_tokens

    assert {:error, {:disallowed_special_token, "<|endoftext|>"}} = Encoding.encode(enc, text)
  end

  test "single-token byte roundtrip matches upstream public sample range" do
    for name <- Tiktoken.list_encoding_names() do
      enc = Tiktoken.get_encoding!(name)

      for token <- 0..min(9_999, Encoding.n_vocab(enc) - 1) do
        case Encoding.decode_single_token_bytes(enc, token) do
          {:ok, bytes} -> assert Encoding.encode_single_token(enc, bytes) == {:ok, token}
          {:error, {:unknown_token, ^token}} -> :ok
        end
      end
    end
  end

  test "ported and unsupported upstream tests are recorded in fixture metadata" do
    upstream_tests =
      @fixture_path
      |> File.read!()
      |> Jason.decode!()
      |> get_in(["metadata", "upstream_tests"])

    assert "test_encoding.test_simple" in upstream_tests["ported"]
    assert "test_offsets.test_basic_offsets" in upstream_tests["ported"]

    assert Enum.any?(
             upstream_tests["out_of_scope"],
             &(&1["test"] == "test_encoding.test_encode_bytes")
           )

    assert Enum.all?(upstream_tests["out_of_scope"], &is_binary(&1["reason"]))
  end
end
