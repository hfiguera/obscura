base = %{
  kind: :operator,
  source: "inspiration/presidio/presidio-anonymizer/tests/test_anonymizer_engine.py",
  source_license: "MIT",
  text: "Contact jane@example.com",
  operators: %{default: %{type: :replace, value: "[EMAIL]"}},
  expected_text: "Contact jane@example.com",
  expected_items: [],
  tags: [:presidio, :operator, :invalid_span],
  notes: "Invalid spans are accepted as fixtures so validation behavior can be tested.",
  metadata: %{}
}

span = fn start_offset, end_offset ->
  %{
    entity: :email,
    byte_start: start_offset,
    byte_end: end_offset,
    char_start: nil,
    char_end: nil,
    value: "jane@example.com",
    score: 1.0,
    source_entity: "EMAIL_ADDRESS",
    metadata: %{}
  }
end

[
  Map.merge(base, %{id: "presidio.operator.invalid_span.negative_start", spans: [span.(-1, 10)]}),
  Map.merge(base, %{id: "presidio.operator.invalid_span.reversed", spans: [span.(20, 10)]}),
  Map.merge(base, %{id: "presidio.operator.invalid_span.outside_text", spans: [span.(8, 200)]})
]
