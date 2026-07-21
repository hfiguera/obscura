defmodule Obscura.Vault.TokenTest do
  use ExUnit.Case, async: true

  alias Obscura.Vault.Token

  test "formats default sequential tokens" do
    assert Token.format(:email, 1) == {:ok, "<<EMAIL_001>>"}
    assert Token.format(:credit_card, 12) == {:ok, "<<CREDIT_CARD_012>>"}
  end

  test "supports token formatting options" do
    assert Token.format(:email, 7,
             token_prefix: "[[",
             token_suffix: "]]",
             token_separator: "-",
             token_width: 2,
             token_case: :lower
           ) == {:ok, "[[email-07]]"}
  end
end
