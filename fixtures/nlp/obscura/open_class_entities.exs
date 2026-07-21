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

text = "Dr. Rivera visited Paris on Monday."

[
  %{
    id: "obscura.nlp.fake.date_nationality_filtering",
    kind: :nlp,
    source: "obscura-phase-4",
    source_license: nil,
    text: text,
    language: :en,
    entities: [:person, :location, :date_time],
    model_outputs: [
      mk_output.(text, "PER", "Rivera", 0.9),
      mk_output.(text, "LOC", "Paris", 0.88),
      mk_output.(text, "DATE", "Monday", 0.86),
      mk_output.(text, "UNKNOWN_LABEL", "Dr.", 0.99)
    ],
    expected: [
      mk_span.(text, :person, "Rivera", "PER"),
      mk_span.(text, :location, "Paris", "LOC"),
      mk_span.(text, :date_time, "Monday", "DATE")
    ],
    should_match: true,
    profile: :nlp,
    tags: [:phase_4, :nlp, :unknown_label],
    notes: nil,
    metadata: %{serving: :fake}
  }
]
