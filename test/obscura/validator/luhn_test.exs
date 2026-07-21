defmodule Obscura.Validator.LuhnTest do
  use ExUnit.Case, async: true

  alias Obscura.Validator.Luhn

  test "validates Luhn digit strings" do
    assert Luhn.valid?("4111111111111111")
    assert Luhn.valid?("378282246310005")
    refute Luhn.valid?("4111111111111112")
    refute Luhn.valid?("not digits")
  end
end
