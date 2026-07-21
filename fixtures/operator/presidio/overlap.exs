text = "Open https://example.com"
url = "https://example.com"
domain = "example.com"
{url_start, _length} = :binary.match(text, url)
url_end = url_start + byte_size(url)
{domain_start, _length} = :binary.match(text, domain)
domain_end = domain_start + byte_size(domain)
{:ok, url_char_start} = Obscura.Eval.Offset.byte_to_char(text, url_start)
{:ok, url_char_end} = Obscura.Eval.Offset.byte_to_char(text, url_end)
{:ok, domain_char_start} = Obscura.Eval.Offset.byte_to_char(text, domain_start)
{:ok, domain_char_end} = Obscura.Eval.Offset.byte_to_char(text, domain_end)

[
  %{
    id: "presidio.operator.overlap.url_domain.prefer_longer",
    kind: :operator,
    source: "inspiration/presidio/presidio-anonymizer/tests/test_anonymizer_engine.py",
    source_license: "MIT",
    text: text,
    spans: [
      %{
        entity: :url,
        byte_start: url_start,
        byte_end: url_end,
        char_start: url_char_start,
        char_end: url_char_end,
        value: url,
        score: 0.8,
        source_entity: "URL",
        metadata: %{}
      },
      %{
        entity: :domain,
        byte_start: domain_start,
        byte_end: domain_end,
        char_start: domain_char_start,
        char_end: domain_char_end,
        value: domain,
        score: 0.7,
        source_entity: "DOMAIN_NAME",
        metadata: %{}
      }
    ],
    operators: %{
      default: %{type: :replace, value: "[PII]"},
      url: %{type: :replace, value: "[URL]"}
    },
    expected_text: "Open [URL]",
    expected_items: [
      %{
        entity: :url,
        operator: :replace,
        source_byte_start: url_start,
        source_byte_end: url_end,
        replacement_byte_start: 5,
        replacement_byte_end: 10,
        replacement: "[URL]",
        metadata: %{conflict_policy: :prefer_longer}
      }
    ],
    tags: [:presidio, :operator, :overlap],
    notes: "Expected behavior documents deterministic overlap resolution for later phases.",
    metadata: %{}
  }
]
