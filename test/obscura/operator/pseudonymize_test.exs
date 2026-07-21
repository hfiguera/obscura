defmodule Obscura.Operator.PseudonymizeTest do
  use ExUnit.Case, async: true

  alias Obscura.Anonymizer.Error
  alias Obscura.Vault.Memory

  test "pseudonymizes through anonymize/3 with vault in operator config" do
    assert {:ok, vault} = Memory.start_link()

    spans = [
      %{entity: :email, byte_start: 6, byte_end: 22, value: "jane@example.com"}
    ]

    assert {:ok, result} =
             Obscura.anonymize("Email jane@example.com", spans,
               operators: %{email: %{type: :pseudonymize, vault: vault}}
             )

    assert result.text == "Email <<EMAIL_001>>"
    assert [%{operator: :pseudonymize, replacement: "<<EMAIL_001>>"}] = result.items
    assert hd(result.items).metadata.deterministic == true
    assert hd(result.items).metadata.token_created == true
  end

  test "pseudonymizes through redact/2 with vault in anonymizer opts" do
    assert {:ok, vault} = Memory.start_link()

    assert {:ok, result} =
             Obscura.redact("Email jane@example.com",
               entities: [:email],
               operators: %{email: %{type: :pseudonymize}},
               vault: vault
             )

    assert result.text == "Email <<EMAIL_001>>"
  end

  test "requires a vault" do
    spans = [
      %{entity: :email, byte_start: 6, byte_end: 22, value: "jane@example.com"}
    ]

    assert {:error,
            %Error{
              code: :missing_operator_option,
              operator: :pseudonymize,
              field: :vault
            }} =
             Obscura.anonymize("Email jane@example.com", spans,
               operators: %{email: %{type: :pseudonymize}}
             )
  end

  test "rejects invalid vaults, token options, and operator options safely" do
    spans = [%{entity: :email, byte_start: 6, byte_end: 22}]

    assert {:error,
            %Error{code: :operator_failed, operator: :pseudonymize, reason: :invalid_vault}} =
             Obscura.anonymize("Email jane@example.com", spans,
               operators: %{email: %{type: :pseudonymize, vault: "private"}}
             )

    assert {:ok, vault} = Memory.start_link()

    assert {:error,
            %Error{
              code: :invalid_operator_option,
              operator: :pseudonymize,
              field: :token_options
            }} =
             Obscura.anonymize("Email jane@example.com", spans,
               operators: %{email: %{type: :pseudonymize}},
               vault: vault,
               token_width: 0
             )

    assert {:error, %Error{code: :unknown_operator_option}} =
             Obscura.anonymize("Email jane@example.com", spans,
               operators: %{email: %{type: :pseudonymize, vault: vault, unknown: true}}
             )
  end
end
