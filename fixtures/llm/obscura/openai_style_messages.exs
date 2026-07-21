[
  %{
    id: "obscura.llm.openai_style.user_email",
    kind: :llm,
    source: "obscura:phase-3-llm-fixtures",
    source_license: nil,
    messages: [
      %{role: "system", content: "Be concise."},
      %{role: "user", content: "Email jane@example.com"}
    ],
    opts: [entities: [:email], roles: [:user], vault_backend: :memory],
    expected_messages: [
      %{role: "system", content: "Be concise."},
      %{role: "user", content: "Email <<EMAIL_001>>"}
    ],
    response: "I will contact <<EMAIL_001>>.",
    expected_rehydrated_response: "I will contact jane@example.com.",
    assertions: [:redacts_configured_roles, :preserves_unconfigured_roles, :rehydrates_response],
    tags: [:llm, :message, :email],
    notes: nil,
    metadata: %{}
  }
]
