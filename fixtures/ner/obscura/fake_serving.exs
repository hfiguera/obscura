mk_span = fn text, entity, value, source_entity ->
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
    metadata: %{}
  }
end

mk_output = fn text, label, value, score ->
  {byte_start, _length} = :binary.match(text, value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_start + byte_size(value))

  %{label: label, start: char_start, end: char_end, offset_unit: :character, score: score}
end

basic = "Alice works at Acme in Denver."
unicode = "José met Alice in München."

[
  %{
    id: "obscura.ner.fake.person_org_location",
    kind: :ner,
    source: "obscura-phase-4",
    source_license: nil,
    text: basic,
    language: :en,
    entities: [:person, :organization, :location],
    model_outputs: [
      mk_output.(basic, "PER", "Alice", 0.94),
      mk_output.(basic, "ORG", "Acme", 0.91),
      mk_output.(basic, "LOC", "Denver", 0.89)
    ],
    expected: [
      mk_span.(basic, :person, "Alice", "PER"),
      mk_span.(basic, :organization, "Acme", "ORG"),
      mk_span.(basic, :location, "Denver", "LOC")
    ],
    should_match: true,
    profile: :nlp,
    tags: [:phase_4, :ner, :fake_serving],
    notes: nil,
    metadata: %{serving: :fake}
  },
  %{
    id: "obscura.ner.fake.unicode_offsets",
    kind: :ner,
    source: "obscura-phase-4",
    source_license: nil,
    text: unicode,
    language: :en,
    entities: [:person, :location],
    model_outputs: [
      mk_output.(unicode, "PER", "José", 0.93),
      mk_output.(unicode, "LOC", "München", 0.9)
    ],
    expected: [
      mk_span.(unicode, :person, "José", "PER"),
      mk_span.(unicode, :location, "München", "LOC")
    ],
    should_match: true,
    profile: :nlp,
    tags: [:phase_4, :ner, :unicode, :offsets],
    notes: nil,
    metadata: %{serving: :fake}
  }
]
