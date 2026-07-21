mk = fn id, text, value, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    id: id,
    kind: :analyzer,
    source: "obscura:unicode-offset-fixtures",
    source_license: nil,
    text: text,
    language: :en,
    entities: [:email],
    expected: [
      %{
        entity: :email,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: "EMAIL_ADDRESS",
        score_range: nil,
        match_strategy: :exact,
        required: true,
        metadata: %{offset_contract: :byte}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:obscura, :unicode, :offset, :email | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.("obscura.unicode.email.after_emoji", "Wave 👋 jane@example.com", "jane@example.com", [:emoji]),
  mk.("obscura.unicode.email.after_combining_mark", "Café jane@example.com", "jane@example.com", [
    :combining_mark
  ]),
  mk.(
    "obscura.unicode.email.after_accented_character",
    "José writes to jane@example.com",
    "jane@example.com",
    [:accented]
  ),
  mk.("obscura.unicode.email.after_lf", "Line one\nEmail jane@example.com", "jane@example.com", [
    :multiline_lf
  ]),
  mk.(
    "obscura.unicode.email.after_crlf",
    "Line one\r\nEmail jane@example.com",
    "jane@example.com",
    [:multiline_crlf]
  )
]
