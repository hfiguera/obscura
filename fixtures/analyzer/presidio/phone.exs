mk = fn id, text, value, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_phone_recognizer.py",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:phone],
    expected: [
      %{
        entity: :phone,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: "PHONE_NUMBER",
        score_range: {0.4, 1.0},
        match_strategy: :exact,
        required: true,
        metadata: %{country: :us}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:presidio, :phone, :core_mvp | tags],
    notes: nil,
    metadata: %{}
  }
end

negative = fn id, text, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_phone_recognizer.py",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:phone],
    expected: [],
    should_match: false,
    profile: :regex_only,
    tags: [:presidio, :phone, :invalid | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.("presidio.phone.valid.us_dashed", "Call 202-555-0188", "202-555-0188", [
    :country_us,
    :punctuation
  ]),
  mk.("presidio.phone.valid.us_parens", "Call (202) 555-0199", "(202) 555-0199", [
    :country_us,
    :punctuation
  ]),
  mk.("presidio.phone.valid.us_e164", "Mobile +1 202 555 0143", "+1 202 555 0143", [
    :country_us,
    :spaced
  ]),
  mk.("presidio.phone.valid.context", "phone number is 303.555.0191", "303.555.0191", [
    :country_us,
    :context
  ]),
  mk.("presidio.phone.valid.extension", "office 212-555-0100 ext 55", "212-555-0100", [
    :country_us,
    :extension_or_context
  ]),
  mk.("presidio.phone.valid.compact", "tel 4155550134", "4155550134", [:country_us]),
  negative.("presidio.phone.invalid.short", "Call 555-0134", [:too_short]),
  negative.("presidio.phone.invalid.long", "Call 202-555-0188123", [:too_long]),
  negative.("presidio.phone.invalid.letters", "Call 202-ABC-0188", [:letters]),
  negative.("presidio.phone.invalid.fake", "Call 000-000-0000", [:invalid_number])
]
