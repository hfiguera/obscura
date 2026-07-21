text = "Contact jane@example.com today"
value = "jane@example.com"
{byte_start, _length} = :binary.match(text, value)
byte_end = byte_start + byte_size(value)
{:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
{:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

[
  %{
    id: "presidio.operator.redact.email.empty",
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
    operators: %{default: %{type: :redact}},
    expected_text: "Contact  today",
    expected_items: [
      %{
        entity: :email,
        operator: :redact,
        source_byte_start: byte_start,
        source_byte_end: byte_end,
        replacement_byte_start: byte_start,
        replacement_byte_end: byte_start,
        replacement: "",
        metadata: %{}
      }
    ],
    tags: [:presidio, :operator, :redact, :empty_string],
    notes: nil,
    metadata: %{}
  }
]
