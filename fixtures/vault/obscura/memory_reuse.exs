[
  %{
    id: "obscura.vault.memory.email_phone_reuse",
    kind: :vault,
    source: "obscura:phase-3-vault-fixtures",
    source_license: nil,
    backend: :memory,
    operations: [
      {:get_or_create, :email, "jane@example.com"},
      {:get_or_create, :email, "jane@example.com"},
      {:get_or_create, :phone, "202-555-0188"},
      {:rehydrate, "Email <<EMAIL_001>> Phone <<PHONE_001>>"}
    ],
    expected_tokens: ["<<EMAIL_001>>", "<<EMAIL_001>>", "<<PHONE_001>>"],
    expected_rehydrated: "Email jane@example.com Phone 202-555-0188",
    assertions: [:token_reuse, :entity_scoped_counter, :rehydrates_text],
    tags: [:vault, :memory, :email, :phone],
    notes: nil,
    metadata: %{}
  },
  %{
    id: "obscura.vault.ets.email_reuse",
    kind: :vault,
    source: "obscura:phase-3-vault-fixtures",
    source_license: nil,
    backend: :ets,
    operations: [
      {:get_or_create, :email, "jane@example.com"},
      {:get_or_create, :email, "jane@example.com"},
      {:rehydrate, "Email <<EMAIL_001>>"}
    ],
    expected_tokens: ["<<EMAIL_001>>", "<<EMAIL_001>>"],
    expected_rehydrated: "Email jane@example.com",
    assertions: [:token_reuse, :rehydrates_text],
    tags: [:vault, :ets, :email],
    notes: nil,
    metadata: %{}
  }
]
