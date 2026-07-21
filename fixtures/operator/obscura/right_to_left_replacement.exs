text = "Email jane@example.com and phone 202-555-0188"
email = "jane@example.com"
phone = "202-555-0188"
{email_start, _length} = :binary.match(text, email)
email_end = email_start + byte_size(email)
{phone_start, _length} = :binary.match(text, phone)
phone_end = phone_start + byte_size(phone)
{:ok, email_char_start} = Obscura.Eval.Offset.byte_to_char(text, email_start)
{:ok, email_char_end} = Obscura.Eval.Offset.byte_to_char(text, email_end)
{:ok, phone_char_start} = Obscura.Eval.Offset.byte_to_char(text, phone_start)
{:ok, phone_char_end} = Obscura.Eval.Offset.byte_to_char(text, phone_end)

[
  %{
    id: "obscura.operator.right_to_left.email_phone",
    kind: :operator,
    source: "obscura:right-to-left-replacement-fixtures",
    source_license: nil,
    text: text,
    spans: [
      %{
        entity: :email,
        byte_start: email_start,
        byte_end: email_end,
        char_start: email_char_start,
        char_end: email_char_end,
        value: email,
        score: 1.0,
        source_entity: "EMAIL_ADDRESS",
        metadata: %{}
      },
      %{
        entity: :phone,
        byte_start: phone_start,
        byte_end: phone_end,
        char_start: phone_char_start,
        char_end: phone_char_end,
        value: phone,
        score: 1.0,
        source_entity: "PHONE_NUMBER",
        metadata: %{}
      }
    ],
    operators: %{
      default: %{type: :replace, value: "[PII]"},
      email: %{type: :replace, value: "[EMAIL]"},
      phone: %{type: :replace, value: "[PHONE]"}
    },
    expected_text: "Email [EMAIL] and phone [PHONE]",
    expected_items: [
      %{
        entity: :email,
        operator: :replace,
        source_byte_start: email_start,
        source_byte_end: email_end,
        replacement_byte_start: 6,
        replacement_byte_end: 13,
        replacement: "[EMAIL]",
        metadata: %{replacement_order: :right_to_left}
      },
      %{
        entity: :phone,
        operator: :replace,
        source_byte_start: phone_start,
        source_byte_end: phone_end,
        replacement_byte_start: 24,
        replacement_byte_end: 31,
        replacement: "[PHONE]",
        metadata: %{replacement_order: :right_to_left}
      }
    ],
    tags: [:obscura, :operator, :right_to_left, :offset],
    notes: "Documents replacement order needed to preserve source offsets.",
    metadata: %{}
  }
]
