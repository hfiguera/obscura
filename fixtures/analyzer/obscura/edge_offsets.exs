mk = fn id, text, value, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    id: id,
    kind: :analyzer,
    source: "obscura:edge-offset-fixtures",
    source_license: nil,
    text: text,
    language: :en,
    entities: [:email],
    expected: [
      %{
        entity: :email,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: "EMAIL_ADDRESS",
        score_range: nil,
        match_strategy: :exact,
        required: true,
        metadata: %{offset_contract: :byte}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:obscura, :offset, :edge, :email | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.("obscura.edge.email.at_start", "jane@example.com is first", "jane@example.com", [:byte_zero]),
  mk.("obscura.edge.email.at_end", "last contact jane@example.com", "jane@example.com", [
    :end_of_text
  ]),
  mk.("obscura.edge.email.only_text", "jane@example.com", "jane@example.com", [
    :byte_zero,
    :end_of_text
  ])
]
