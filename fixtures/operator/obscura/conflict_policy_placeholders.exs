text = "Token https://example.com"
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
    id: "obscura.operator.conflict_policy.prefer_higher_confidence",
    kind: :operator,
    source: "obscura:conflict-policy-fixtures",
    source_license: nil,
    text: text,
    spans: [
      %{
        entity: :url,
        byte_start: url_start,
        byte_end: url_end,
        char_start: url_char_start,
        char_end: url_char_end,
        value: url,
        score: 0.6,
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
        score: 0.9,
        source_entity: "DOMAIN_NAME",
        metadata: %{}
      }
    ],
    operators: %{
      default: %{type: :replace, value: "[PII]"},
      conflict_policy: :prefer_higher_confidence
    },
    expected_text: "Token https://[PII]",
    expected_items: [
      %{
        entity: :domain,
        operator: :replace,
        source_byte_start: domain_start,
        source_byte_end: domain_end,
        replacement_byte_start: 14,
        replacement_byte_end: 19,
        replacement: "[PII]",
        metadata: %{conflict_policy: :prefer_higher_confidence}
      }
    ],
    tags: [:obscura, :operator, :conflict_policy, :overlap],
    notes: "Documents a future conflict policy; Phase 0 only validates fixture shape.",
    metadata: %{}
  }
]
