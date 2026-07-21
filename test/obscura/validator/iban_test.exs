defmodule Obscura.Validator.IBANTest do
  use ExUnit.Case, async: true

  alias Obscura.Validator.IBAN

  test "validates supported fixture countries" do
    assert IBAN.valid?("DE89370400440532013000")
    assert IBAN.valid?("GB82 WEST 1234 5698 7654 32")
    assert IBAN.valid?("FR1420041010050500013M02606")
    assert IBAN.valid?("NL91ABNA0417164300")
  end

  test "rejects invalid checksum and unsupported countries" do
    refute IBAN.valid?("DE00370400440532013000")
    refute IBAN.valid?("ZZ89370400440532013000")
  end
end
