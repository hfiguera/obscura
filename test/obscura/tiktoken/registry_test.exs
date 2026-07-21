defmodule Obscura.Tiktoken.RegistryTest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken

  test "lists and loads supported encodings" do
    assert Tiktoken.list_encoding_names() == [
             "cl100k_base",
             "gpt2",
             "o200k_base",
             "o200k_harmony",
             "p50k_base",
             "p50k_edit",
             "r50k_base"
           ]

    assert {:ok, %{name: "o200k_base"}} = Tiktoken.get_encoding(:o200k_base)
    assert {:error, :unknown_encoding} = Tiktoken.get_encoding("missing")
  end

  test "maps known models to encodings" do
    assert Tiktoken.encoding_name_for_model("gpt2") == {:ok, "gpt2"}
    assert Tiktoken.encoding_name_for_model("gpt-4") == {:ok, "cl100k_base"}
    assert Tiktoken.encoding_name_for_model("gpt-4o") == {:ok, "o200k_base"}
    assert Tiktoken.encoding_name_for_model("gpt-oss-120b") == {:ok, "o200k_harmony"}

    assert Tiktoken.encoding_name_for_model("unknown-model") ==
             {:error, {:unknown_model, "unknown-model"}}
  end
end
