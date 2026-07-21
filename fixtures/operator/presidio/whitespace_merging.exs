text = "Emails jane@example.com   john@example.com"
first = "jane@example.com"
second = "john@example.com"
{first_start, _length} = :binary.match(text, first)
first_end = first_start + byte_size(first)
{second_start, _length} = :binary.match(text, second)
second_end = second_start + byte_size(second)
{:ok, first_char_start} = Obscura.Eval.Offset.byte_to_char(text, first_start)
{:ok, first_char_end} = Obscura.Eval.Offset.byte_to_char(text, first_end)
{:ok, second_char_start} = Obscura.Eval.Offset.byte_to_char(text, second_start)
{:ok, second_char_end} = Obscura.Eval.Offset.byte_to_char(text, second_end)

[
  %{
    id: "presidio.operator.whitespace_merging.adjacent_email",
    kind: :operator,
    source: "inspiration/presidio/presidio-anonymizer/tests/test_anonymizer_engine.py",
    source_license: "MIT",
    text: text,
    spans: [
      %{
        entity: :email,
        byte_start: first_start,
        byte_end: first_end,
        char_start: first_char_start,
        char_end: first_char_end,
        value: first,
        score: 1.0,
        source_entity: "EMAIL_ADDRESS",
        metadata: %{}
      },
      %{
        entity: :email,
        byte_start: second_start,
        byte_end: second_end,
        char_start: second_char_start,
        char_end: second_char_end,
        value: second,
        score: 1.0,
        source_entity: "EMAIL_ADDRESS",
        metadata: %{}
      }
    ],
    operators: %{default: %{type: :replace, value: "[EMAILS]"}, merge_whitespace: true},
    expected_text: "Emails [EMAILS]",
    expected_items: [
      %{
        entity: :email,
        operator: :replace,
        source_byte_start: first_start,
        source_byte_end: second_end,
        replacement_byte_start: 7,
        replacement_byte_end: 15,
        replacement: "[EMAILS]",
        metadata: %{merged: true}
      }
    ],
    tags: [:presidio, :operator, :whitespace_merging],
    notes: "Documents future merge behavior for adjacent same-type spans.",
    metadata: %{}
  }
]
