defmodule Obscura.OperatorPropagationTest do
  use ExUnit.Case, async: true

  alias Obscura.Anonymizer.Error
  alias Obscura.CLI
  alias Obscura.Fixtures.ObscuraOperatorAdapter

  test "redact/2 propagates structured operator errors" do
    assert {:error, %Error{code: :unsupported_operator, operator: :unknown}} =
             Obscura.redact("Email jane@example.com",
               entities: [:email],
               operators: %{email: %{type: :unknown}}
             )
  end

  test "structured redaction validates every field operator before traversal" do
    input = %{first: "jane@example.com", second: "202-555-0188"}

    assert {:error, %Error{code: :unsupported_operator}} =
             Obscura.redact(input,
               field_policies: %{
                 first: {:operator, %{type: :replace, value: "[EMAIL]"}},
                 second: {:operator, %{type: :unknown}}
               }
             )

    assert input == %{first: "jane@example.com", second: "202-555-0188"}
  end

  test "structured redaction propagates invalid global operator configuration" do
    assert {:error, %Error{code: :invalid_operator_collection, field: :operators}} =
             Obscura.redact(%{email: "jane@example.com"},
               entities: [:email],
               operators: :invalid
             )
  end

  test "LLM helpers propagate operator errors without returning partial messages" do
    messages = [
      %{role: :user, content: "Email jane@example.com"},
      %{role: :user, content: "Phone 202-555-0188"}
    ]

    assert {:error, %Error{code: :unsupported_operator}} =
             Obscura.LLM.redact_messages(messages,
               vault: :memory,
               entities: [:email, :phone],
               operators: %{default: %{type: :unknown}}
             )

    assert Enum.at(messages, 0).content == "Email jane@example.com"
  end

  test "fixture adapter propagates operator configuration errors" do
    text = "Email jane@example.com"
    spans = [%{entity: :email, byte_start: 6, byte_end: 22}]

    assert {:error, %Error{code: :unsupported_operator}} =
             ObscuraOperatorAdapter.anonymize(
               text,
               spans,
               %{default: %{type: :unknown}},
               []
             )
  end

  test "CLI renders operator errors without source values" do
    error = %Error{
      code: :invalid_operator_option,
      operator: :replace,
      field: :value,
      reason: :expected_binary
    }

    rendered = CLI.format_error(error)

    assert rendered =~ "code=invalid_operator_option"
    assert rendered =~ "operator=replace"
    refute rendered =~ "jane@example.com"
  end
end
