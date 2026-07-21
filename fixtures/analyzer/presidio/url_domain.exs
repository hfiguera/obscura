mk = fn id, text, value, entity, source_entity, tags ->
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
    entities: [entity],
    expected: [
      %{
        entity: entity,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: source_entity,
        score_range: {0.4, 1.0},
        match_strategy: :exact,
        required: true,
        metadata: %{}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:presidio, :url_domain, :core_mvp | tags],
    notes: nil,
    metadata: %{}
  }
end

negative = fn id, text, entity, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "inspiration/presidio/presidio-analyzer/tests",
    source_license: "MIT",
    text: text,
    language: :en,
    entities: [entity],
    expected: [],
    should_match: false,
    profile: :regex_only,
    tags: [:presidio, :url_domain, :invalid | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.(
    "presidio.url.valid.https",
    "Visit https://example.com",
    "https://example.com",
    :url,
    "URL",
    [:scheme]
  ),
  mk.(
    "presidio.url.valid.http_path",
    "Open http://example.com/a/b",
    "http://example.com/a/b",
    :url,
    "URL",
    [:scheme, :path]
  ),
  mk.(
    "presidio.url.valid.query",
    "See https://example.com?q=1",
    "https://example.com?q=1",
    :url,
    "URL",
    [:scheme, :query]
  ),
  mk.(
    "presidio.domain.valid.basic",
    "Domain example.com is allowed",
    "example.com",
    :domain,
    "DOMAIN_NAME",
    [:no_scheme_domain]
  ),
  mk.(
    "presidio.domain.valid.subdomain",
    "Host api.mail.example.co.uk",
    "api.mail.example.co.uk",
    :domain,
    "DOMAIN_NAME",
    [:no_scheme_domain]
  ),
  mk.(
    "presidio.domain.valid.punctuation",
    "Blocked: presidio.site.",
    "presidio.site",
    :domain,
    "DOMAIN_NAME",
    [:punctuation]
  ),
  negative.("presidio.url.invalid.scheme_only", "Visit https://", :url, [:invalid]),
  negative.("presidio.url.invalid.space", "Visit https://example .com", :url, [:invalid]),
  negative.("presidio.domain.invalid.no_dot", "Domain localhost is local", :domain, [:invalid]),
  negative.("presidio.domain.invalid.starts_dot", "Domain .example.com is invalid", :domain, [
    :invalid
  ])
]
