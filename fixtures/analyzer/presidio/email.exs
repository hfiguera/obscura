mk = fn id, text, value, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_email_recognizer.py",
    source_license: "MIT",
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
        score_range: {0.5, 1.0},
        match_strategy: :exact,
        required: true,
        metadata: %{}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:presidio, :email, :core_mvp | tags],
    notes: nil,
    metadata: %{}
  }
end

negative = fn id, text, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests/test_email_recognizer.py",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [:email],
    expected: [],
    should_match: false,
    profile: :regex_only,
    tags: [:presidio, :email, :invalid | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.("presidio.email.valid.basic", "Contact jane@example.com today", "jane@example.com", [:basic]),
  mk.("presidio.email.valid.punctuation", "Email: info@presidio.site.", "info@presidio.site", [
    :punctuation
  ]),
  mk.("presidio.email.valid.uppercase", "Reach ADMIN@EXAMPLE.ORG now", "ADMIN@EXAMPLE.ORG", [
    :uppercase
  ]),
  mk.(
    "presidio.email.valid.subdomain",
    "Send to alerts@mail.example.co.uk",
    "alerts@mail.example.co.uk",
    [:subdomain]
  ),
  mk.(
    "presidio.email.valid.plus_tag",
    "Owner is first.last+tag@example.io",
    "first.last+tag@example.io",
    [:plus_tag]
  ),
  negative.("presidio.email.invalid.missing_domain", "Contact jane@", [:missing_domain]),
  negative.("presidio.email.invalid.no_at", "Contact jane.example.com", [:missing_at]),
  negative.("presidio.email.invalid.domain_dot", "Contact jane@example", [:missing_tld])
]
