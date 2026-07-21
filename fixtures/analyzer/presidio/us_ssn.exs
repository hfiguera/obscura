mk = fn id, text, value, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_us_ssn_recognizer.py",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:us_ssn],
    expected: [
      %{
        entity: :us_ssn,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: "US_SSN",
        score_range: {0.5, 1.0},
        match_strategy: :exact,
        required: true,
        metadata: %{country: :us}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:presidio, :us_ssn, :core_mvp, :country_us | tags],
    notes: nil,
    metadata: %{}
  }
end

negative = fn id, text, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_us_ssn_recognizer.py",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:us_ssn],
    expected: [],
    should_match: false,
    profile: :regex_only,
    tags: [:presidio, :us_ssn, :invalid, :country_us | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.("presidio.us_ssn.valid.basic", "SSN 123-45-6789", "123-45-6789", [:valid_format]),
  mk.("presidio.us_ssn.valid.context", "social security number is 219-09-9999", "219-09-9999", [
    :valid_format,
    :context
  ]),
  mk.("presidio.us_ssn.valid.no_context", "Employee 078-05-1120", "078-05-1120", [:valid_format]),
  mk.("presidio.us_ssn.valid.low_area", "Tax id 001-01-0001", "001-01-0001", [:valid_format]),
  mk.("presidio.us_ssn.valid.high_area", "Applicant 665-12-3456", "665-12-3456", [:valid_format]),
  mk.("presidio.us_ssn.valid.punctuation", "ID: 321-54-9876.", "321-54-9876", [
    :valid_format,
    :punctuation
  ]),
  negative.("presidio.us_ssn.invalid.area_000", "SSN 000-12-3456", [:invalid_area]),
  negative.("presidio.us_ssn.invalid.area_666", "SSN 666-12-3456", [:invalid_area]),
  negative.("presidio.us_ssn.invalid.area_900", "SSN 900-12-3456", [:invalid_area]),
  negative.("presidio.us_ssn.invalid.group_00", "SSN 123-00-3456", [:invalid_group]),
  negative.("presidio.us_ssn.invalid.serial_0000", "SSN 123-45-0000", [:invalid_serial]),
  negative.("presidio.us_ssn.invalid.format", "SSN 12-345-6789", [:invalid_format])
]
