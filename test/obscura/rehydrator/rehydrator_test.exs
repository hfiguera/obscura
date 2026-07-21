defmodule Obscura.RehydratorTest do
  use ExUnit.Case, async: true

  alias Obscura.Vault
  alias Obscura.Vault.Memory

  defmodule User do
    defstruct [:message]
  end

  test "rehydrates repeated tokens in text" do
    assert {:ok, vault} = Memory.start_link()
    assert {:ok, _token} = Vault.get_or_create(vault, :email, "jane@example.com")

    assert Obscura.rehydrate("<<EMAIL_001>> and <<EMAIL_001>>", vault: vault) ==
             {:ok, "jane@example.com and jane@example.com"}
  end

  test "keeps or errors on unknown tokens" do
    assert {:ok, vault} = Memory.start_link()

    assert Obscura.rehydrate("Hello <<EMAIL_999>>", vault: vault) ==
             {:ok, "Hello <<EMAIL_999>>"}

    assert {:error, {:token_not_found, _shape}} =
             Obscura.rehydrate("Hello <<EMAIL_999>>", vault: vault, unknown: :error)
  end

  test "requires a vault" do
    assert Obscura.rehydrate("Hello <<EMAIL_001>>") == {:error, :missing_vault}
  end

  test "rehydrates supported structured data" do
    assert {:ok, vault} = Memory.start_link()
    assert {:ok, _token} = Vault.get_or_create(vault, :email, "jane@example.com")

    input = %{messages: ["Email <<EMAIL_001>>"], user: %User{message: "<<EMAIL_001>>"}}

    assert {:ok, restored} = Obscura.rehydrate(input, vault: vault)
    assert restored.messages == ["Email jane@example.com"]
    assert restored.user.message == "jane@example.com"
  end

  test "structured redaction can pseudonymize and rehydrate" do
    assert {:ok, vault} = Memory.start_link()

    assert {:ok, result} =
             Obscura.redact(%{message: "Email jane@example.com"},
               entities: [:email],
               operators: %{email: %{type: :pseudonymize}},
               vault: vault
             )

    assert result.data == %{message: "Email <<EMAIL_001>>"}
    assert {:ok, restored} = Obscura.rehydrate(result.data, vault: vault)
    assert restored == %{message: "Email jane@example.com"}
  end
end
