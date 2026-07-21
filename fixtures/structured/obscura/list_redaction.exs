[
  %{
    id: "obscura.structured.list.email",
    kind: :structured,
    source: "obscura:structured-list-fixtures",
    source_license: nil,
    input: ["safe", "jane@example.com"],
    opts: [entities: [:email]],
    expected_data: ["safe", "[EMAIL]"],
    expected_items: [
      %{
        path: [1],
        entity: :email,
        operator: :replace,
        source_byte_start: 0,
        source_byte_end: byte_size("jane@example.com"),
        replacement_byte_start: 0,
        replacement_byte_end: byte_size("[EMAIL]"),
        replacement: "[EMAIL]",
        metadata: %{}
      }
    ],
    tags: [:structured, :list, :email],
    notes: nil,
    metadata: %{}
  }
]
