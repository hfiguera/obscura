text = "Customer jane@example.com"
value = "jane@example.com"
replacement = "<custom:email>"
{byte_start, _length} = :binary.match(text, value)
byte_end = byte_start + byte_size(value)
{:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
{:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)
expected_text = String.replace(text, value, replacement)
{replacement_start, _length} = :binary.match(expected_text, replacement)
replacement_end = replacement_start + byte_size(replacement)

[
  %{
    id: "presidio.operator.custom.email.callback",
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
    operators: %{
      default: %{
        type: :custom,
        module: Obscura.Fixtures.CustomOperator,
        options: %{replacement: replacement, metadata: %{callback: :email_fixture}}
      }
    },
    expected_text: expected_text,
    expected_items: [
      %{
        entity: :email,
        operator: :custom,
        source_byte_start: byte_start,
        source_byte_end: byte_end,
        replacement_byte_start: replacement_start,
        replacement_byte_end: replacement_end,
        replacement: replacement,
        metadata: %{
          callback: :email_fixture,
          custom_module: Obscura.Fixtures.CustomOperator
        }
      }
    ],
    tags: [:presidio, :operator, :custom],
    notes: "Uses the public custom operator behaviour with a stable fixture implementation.",
    metadata: %{}
  }
]
