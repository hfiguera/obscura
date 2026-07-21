mk = fn id, text, spans, tags ->
  expected =
    Enum.map(spans, fn {entity, source_entity, value} ->
      {byte_start, _length} = :binary.match(text, value)
      byte_end = byte_start + byte_size(value)
      {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
      {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

      %{
        entity: entity,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: source_entity,
        score_range: nil,
        match_strategy: :exact,
        required: true,
        metadata: %{overlap_fixture: true}
      }
    end)

  %{
    id: id,
    kind: :analyzer,
    source: "obscura:overlap-candidate-fixtures",
    source_license: nil,
    text: text,
    language: :en,
    entities: Enum.map(spans, fn {entity, _source, _value} -> entity end),
    expected: expected,
    should_match: true,
    profile: :regex_only,
    tags: [:obscura, :overlap, :offset | tags],
    notes: "Fixture records candidate spans before conflict resolution.",
    metadata: %{}
  }
end

[
  mk.(
    "obscura.overlap.url_and_domain",
    "Open https://example.com/login",
    [{:url, "URL", "https://example.com/login"}, {:domain, "DOMAIN_NAME", "example.com"}],
    [:url_domain]
  ),
  mk.(
    "obscura.overlap.email_without_domain",
    "Send to jane@example.com",
    [{:email, "EMAIL_ADDRESS", "jane@example.com"}],
    [:email_no_domain]
  )
]
