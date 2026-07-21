mk = fn id, text, value, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_credit_card_recognizer.py",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:credit_card],
    expected: [
      %{
        entity: :credit_card,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: "CREDIT_CARD",
        score_range: {0.8, 1.0},
        match_strategy: :exact,
        required: true,
        metadata: %{validator: :luhn}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:presidio, :credit_card, :core_mvp | tags],
    notes: nil,
    metadata: %{}
  }
end

negative = fn id, text, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_credit_card_recognizer.py",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:credit_card],
    expected: [],
    should_match: false,
    profile: :regex_only,
    tags: [:presidio, :credit_card, :invalid | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.(
    "presidio.credit_card.valid.visa.dashed",
    "my credit card: 4012-8888-8888-1881",
    "4012-8888-8888-1881",
    [:luhn_valid, :dashed]
  ),
  mk.(
    "presidio.credit_card.valid.visa.spaced",
    "card 4111 1111 1111 1111",
    "4111 1111 1111 1111",
    [:luhn_valid, :spaced]
  ),
  mk.("presidio.credit_card.valid.mastercard", "mc=5555555555554444", "5555555555554444", [
    :luhn_valid
  ]),
  mk.("presidio.credit_card.valid.amex", "amex 378282246310005", "378282246310005", [:luhn_valid]),
  mk.("presidio.credit_card.valid.discover", "discover 6011111111111117", "6011111111111117", [
    :luhn_valid
  ]),
  mk.("presidio.credit_card.valid.short_context", "cc 5105105105105100", "5105105105105100", [
    :luhn_valid,
    :context
  ]),
  mk.(
    "presidio.credit_card.valid.hyphen_context",
    "payment card 4000-0000-0000-0002",
    "4000-0000-0000-0002",
    [:luhn_valid, :dashed]
  ),
  mk.(
    "presidio.credit_card.valid.long_context",
    "Use account number 4222222222222 for test",
    "4222222222222",
    [:luhn_valid]
  ),
  negative.("presidio.credit_card.invalid.luhn", "card 4111 1111 1111 1112", [:luhn_invalid]),
  negative.("presidio.credit_card.invalid.too_short", "card 4111 1111 111", [:too_short]),
  negative.("presidio.credit_card.invalid.letters", "card 4111 1111 ABCD 1111", [:letters]),
  negative.("presidio.credit_card.invalid.random_digits", "number 1234 5678 9012 3456", [
    :luhn_invalid,
    :spaced
  ]),
  negative.("presidio.credit_card.invalid.long_run", "number 41111111111111111111", [:too_long])
]
