defmodule Obscura.Stream.RehydratorTest do
  use ExUnit.Case, async: true

  alias Obscura.Stream.Rehydrator
  alias Obscura.Vault
  alias Obscura.Vault.Memory

  test "rehydrates a token split across chunks" do
    assert {:ok, vault} = Memory.start_link()
    assert {:ok, _token} = Vault.get_or_create(vault, :email, "jane@example.com")
    assert {:ok, stream} = Rehydrator.new(vault: vault)

    assert {:ok, a, stream} = Rehydrator.feed(stream, "Hello <<EMA")
    assert {:ok, b, stream} = Rehydrator.feed(stream, "IL_001")
    assert {:ok, c, stream} = Rehydrator.feed(stream, ">>")
    assert {:ok, rest} = Rehydrator.flush(stream)

    assert a <> b <> c <> rest == "Hello jane@example.com"
  end

  test "handles a token split at every byte boundary" do
    assert {:ok, vault} = Memory.start_link()
    assert {:ok, token} = Vault.get_or_create(vault, :email, "jane@example.com")

    for split <- 0..byte_size(token) do
      assert {:ok, stream} = Rehydrator.new(vault: vault)
      first = binary_part(token, 0, split)
      second = binary_part(token, split, byte_size(token) - split)

      assert {:ok, a, stream} = Rehydrator.feed(stream, first)
      assert {:ok, b, stream} = Rehydrator.feed(stream, second)
      assert {:ok, rest} = Rehydrator.flush(stream)

      assert a <> b <> rest == "jane@example.com"
    end
  end

  test "keeps unknown tokens by default" do
    assert {:ok, vault} = Memory.start_link()
    assert {:ok, stream} = Rehydrator.new(vault: vault)
    assert {:ok, ready, stream} = Rehydrator.feed(stream, "<<EMAIL_999>>")
    assert {:ok, rest} = Rehydrator.flush(stream)
    assert ready <> rest == "<<EMAIL_999>>"
  end
end
