defmodule Obscura.PrivacyFilter.TokenizationTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Tokenization

  test "tokenizes from a privacy-filter config encoding" do
    config = %{"encoding" => "cl100k_base"}
    text = "Rachel works at OpenAI."

    assert {:ok, tokenization} = Tokenization.from_config(config, text)
    assert tokenization.encoding_name == "cl100k_base"
    assert tokenization.pad_token_id == 100_257
    assert tokenization.decoded_text == text
    refute tokenization.decoded_mismatch
    assert tokenization.token_ids == [84_978, 4375, 520, 5377, 15_836, 13]
    assert length(tokenization.char_starts) == length(tokenization.token_ids)
    assert length(tokenization.char_ends) == length(tokenization.token_ids)
  end

  test "reports missing encoding in privacy-filter config" do
    assert Tokenization.from_config(%{}, "text") == {:error, :missing_privacy_filter_encoding}
  end
end
