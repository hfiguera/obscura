defmodule Obscura.LLMTest do
  use ExUnit.Case, async: true

  alias Obscura.Vault.Memory

  test "redacts configured roles and preserves message shape" do
    assert {:ok, vault} = Memory.start_link()

    messages = [
      %{role: "system", content: "Keep this."},
      %{role: "user", content: "Email jane@example.com", name: "customer"},
      %{"role" => "assistant", "content" => "No PII"}
    ]

    assert {:ok, safe_messages, ^vault} =
             Obscura.LLM.redact_messages(messages, vault: vault, entities: [:email])

    [system_message, user_message, assistant_message] = safe_messages
    assert system_message.content == "Keep this."
    assert user_message.content == "Email <<EMAIL_001>>"
    assert user_message.name == "customer"
    assert assistant_message["content"] == "No PII"
  end

  test "can create an explicit memory vault" do
    messages = [%{role: :user, content: "Email jane@example.com"}]

    assert {:ok, [%{content: "Email <<EMAIL_001>>"}], vault} =
             Obscura.LLM.redact_messages(messages, vault: :memory, entities: [:email])

    assert {:ok, "Email jane@example.com"} =
             Obscura.LLM.rehydrate_response("Email <<EMAIL_001>>", vault: vault)
  end

  test "rehydrates message content" do
    assert {:ok, vault} = Memory.start_link()

    assert {:ok, safe_messages, ^vault} =
             Obscura.LLM.redact_messages([%{role: :user, content: "Email jane@example.com"}],
               vault: vault,
               entities: [:email]
             )

    assert {:ok, [%{content: "Email jane@example.com"}]} =
             Obscura.LLM.rehydrate_messages(safe_messages, vault: vault)
  end
end
