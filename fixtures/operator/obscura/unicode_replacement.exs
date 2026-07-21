text = "José 👋 jane@example.com"
value = "jane@example.com"
replacement = "[EMAIL]"
{byte_start, _length} = :binary.match(text, value)
byte_end = byte_start + byte_size(value)
{:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
{:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)
expected_text = String.replace(text, value, replacement)
{replacement_start, _length} = :binary.match(expected_text, replacement)
replacement_end = replacement_start + byte_size(replacement)

[
  %{
    id: "obscura.operator.unicode_replacement.email_after_unicode",
    kind: :operator,
    source: "obscura:unicode-replacement-fixtures",
    source_license: nil,
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
        metadata: %{offset_contract: :byte}
      }
    ],
    operators: %{default: %{type: :replace, value: replacement}},
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
        metadata: %{offset_contract: :byte}
      }
    ],
    tags: [:obscura, :operator, :unicode, :offset],
    notes: nil,
    metadata: %{}
  }
]
