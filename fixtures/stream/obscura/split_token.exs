[
  %{
    id: "obscura.stream.split_email_token",
    kind: :stream,
    source: "obscura:phase-3-stream-fixtures",
    source_license: nil,
    setup: [
      {:get_or_create, :email, "jane@example.com"}
    ],
    chunks: ["Hello <<EMA", "IL_001", ">>"],
    expected_chunks: ["Hello ", "", "jane@example.com"],
    expected_output: "Hello jane@example.com",
    assertions: [:handles_split_token, :flushes_remaining_buffer],
    tags: [:stream, :rehydration, :split_token],
    notes: nil,
    metadata: %{}
  }
]
