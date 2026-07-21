mk = fn id, text, value, operators, replacement, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)
  expected_text = String.replace(text, value, replacement)
  {replacement_start, _length} = :binary.match(expected_text, replacement)
  replacement_end = replacement_start + byte_size(replacement)

  %{
    id: id,
    kind: :operator,
    source: "inspiration/presidio/presidio-anonymizer/tests/test_anonymizer_engine.py",
    source_license: "MIT",
    text: text,
    spans: [
      %{
        entity: :email,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        score: 1.0,
        source_entity: "EMAIL_ADDRESS",
        metadata: %{}
      }
    ],
    operators: operators,
    expected_text: expected_text,
    expected_items: [
      %{
        entity: :email,
        operator: :replace,
        source_byte_start: byte_start,
        source_byte_end: byte_end,
        replacement_byte_start: replacement_start,
        replacement_byte_end: replacement_end,
        replacement: replacement,
        metadata: %{}
      }
    ],
    tags: [:presidio, :operator, :replace | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.(
    "presidio.operator.replace.email.default",
    "Contact jane@example.com today",
    "jane@example.com",
    %{
      default: %{type: :replace, value: "[REDACTED]"},
      email: %{type: :replace, value: "[EMAIL]"}
    },
    "[EMAIL]",
    [:entity_override]
  ),
  mk.(
    "presidio.operator.replace.email.fallback",
    "Contact jane@example.com today",
    "jane@example.com",
    %{default: %{type: :replace, value: "[REDACTED]"}},
    "[REDACTED]",
    [:default_fallback]
  )
]
