mk = fn id, text, value, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:iban],
    expected: [
      %{
        entity: :iban,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: "IBAN_CODE",
        score_range: {0.5, 1.0},
        match_strategy: :exact,
        required: true,
        metadata: %{validator: :iban_checksum}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:presidio, :iban, :core_mvp | tags],
    notes: nil,
    metadata: %{}
  }
end

negative = fn id, text, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:iban],
    expected: [],
    should_match: false,
    profile: :regex_only,
    tags: [:presidio, :iban, :invalid | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.("presidio.iban.valid.de", "IBAN DE89370400440532013000", "DE89370400440532013000", [
    :checksum_valid
  ]),
  mk.(
    "presidio.iban.valid.gb_spaced",
    "IBAN GB82 WEST 1234 5698 7654 32",
    "GB82 WEST 1234 5698 7654 32",
    [:checksum_valid, :spaced]
  ),
  mk.(
    "presidio.iban.valid.fr",
    "IBAN FR1420041010050500013M02606",
    "FR1420041010050500013M02606",
    [:checksum_valid]
  ),
  mk.("presidio.iban.valid.nl", "IBAN NL91ABNA0417164300", "NL91ABNA0417164300", [:checksum_valid]),
  mk.("presidio.iban.valid.lowercase", "iban de89370400440532013000", "de89370400440532013000", [
    :checksum_valid,
    :lowercase
  ]),
  negative.("presidio.iban.invalid.checksum", "IBAN DE00370400440532013000", [:checksum_invalid]),
  negative.("presidio.iban.invalid.too_short", "IBAN DE893704004405320", [:too_short]),
  negative.("presidio.iban.invalid.country", "IBAN ZZ89370400440532013000", [:invalid_country]),
  negative.("presidio.iban.invalid.characters", "IBAN DE89-3704-0044-0532-0130-00", [
    :invalid_format
  ])
]
