defmodule Obscura.VaultTest do
  use ExUnit.Case, async: true

  alias Obscura.Vault
  alias Obscura.Vault.ETS
  alias Obscura.Vault.Memory

  describe "memory vault" do
    test "creates, reuses, looks up, and clears tokens" do
      assert {:ok, vault} = Memory.start_link()

      assert Vault.get_or_create(vault, :email, "jane@example.com") == {:ok, "<<EMAIL_001>>"}
      assert Vault.get_or_create(vault, :email, "jane@example.com") == {:ok, "<<EMAIL_001>>"}
      assert Vault.get_or_create(vault, :phone, "202-555-0188") == {:ok, "<<PHONE_001>>"}

      assert {:ok, entry} = Vault.lookup_token(vault, "<<EMAIL_001>>")
      assert entry.entity == :email
      assert entry.value == "jane@example.com"

      assert {:ok, same_entry} = Vault.lookup_value(vault, :email, "jane@example.com")
      assert same_entry.token == "<<EMAIL_001>>"

      assert :ok = Vault.clear(vault)
      assert {:error, {:token_not_found, _shape}} = Vault.lookup_token(vault, "<<EMAIL_001>>")
    end

    test "isolates independent sessions" do
      assert {:ok, vault_a} = Memory.start_link()
      assert {:ok, vault_b} = Memory.start_link()

      assert Vault.get_or_create(vault_a, :email, "jane@example.com") == {:ok, "<<EMAIL_001>>"}
      assert {:error, {:token_not_found, _shape}} = Vault.lookup_token(vault_b, "<<EMAIL_001>>")
      assert :ok = Vault.clear(vault_a)
      assert Vault.get_or_create(vault_b, :email, "jane@example.com") == {:ok, "<<EMAIL_001>>"}
    end
  end

  describe "ets vault" do
    test "creates, reuses, looks up, and clears tokens" do
      assert {:ok, vault} = ETS.start_link()

      assert Vault.get_or_create(vault, :email, "jane@example.com") == {:ok, "<<EMAIL_001>>"}
      assert Vault.get_or_create(vault, :email, "jane@example.com") == {:ok, "<<EMAIL_001>>"}

      assert {:ok, entry} = Vault.lookup_token(vault, "<<EMAIL_001>>")
      assert entry.value == "jane@example.com"

      assert :ok = Vault.clear(vault)
      assert {:error, {:token_not_found, _shape}} = Vault.lookup_token(vault, "<<EMAIL_001>>")
    end

    test "isolates independent sessions when legacy table labels are supplied" do
      assert {:ok, vault_a} = ETS.start_link(table: :obscura_test_vault_a)
      assert {:ok, vault_b} = ETS.start_link(table: :obscura_test_vault_b)

      assert Vault.get_or_create(vault_a, :email, "jane@example.com") == {:ok, "<<EMAIL_001>>"}
      assert {:error, {:token_not_found, _shape}} = Vault.lookup_token(vault_b, "<<EMAIL_001>>")
    end
  end

  test "inspect for entries omits raw values" do
    assert {:ok, vault} = Memory.start_link()
    assert {:ok, _token} = Vault.get_or_create(vault, :email, "jane@example.com")
    assert {:ok, entry} = Vault.lookup_token(vault, "<<EMAIL_001>>")

    inspected = inspect(entry)
    refute inspected =~ "jane@example.com"
    refute inspected =~ "<<EMAIL_001>>"
    assert inspected =~ "token: :redacted"
  end
end
