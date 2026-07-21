email = "jane@example.com"
input = %{user: %{email: email, password: "secret"}, note: "Call 202-555-0188"}
expected_data = %{user: %{email: "[EMAIL]"}, note: "Call [PHONE]"}

[
  %{
    id: "obscura.structured.map.email_phone_password",
    kind: :structured,
    source: "obscura:structured-map-fixtures",
    source_license: nil,
    input: input,
    opts: [entities: [:email, :phone], field_policies: %{password: :drop}],
    expected_data: expected_data,
    expected_items: [
      %{
        path: [:user, :email],
        entity: :email,
        operator: :replace,
        source_byte_start: 0,
        source_byte_end: byte_size(email),
        replacement_byte_start: 0,
        replacement_byte_end: byte_size("[EMAIL]"),
        replacement: "[EMAIL]",
        metadata: %{}
      },
      %{
        path: [:user, :password],
        entity: :field,
        operator: :drop,
        source_byte_start: 0,
        source_byte_end: byte_size("secret"),
        replacement_byte_start: 0,
        replacement_byte_end: 0,
        replacement: "",
        metadata: %{dropped: true}
      },
      %{
        path: [:note],
        entity: :phone,
        operator: :replace,
        source_byte_start: 5,
        source_byte_end: 17,
        replacement_byte_start: 5,
        replacement_byte_end: 12,
        replacement: "[PHONE]",
        metadata: %{country: :us, context_words: ["phone", "mobile", "tel", "call"]}
      }
    ],
    tags: [:structured, :map, :email, :phone, :password],
    notes: nil,
    metadata: %{}
  }
]
