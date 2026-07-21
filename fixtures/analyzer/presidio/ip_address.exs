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
    entities: [:ip_address],
    expected: [
      %{
        entity: entity,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        source_entity: source_entity,
        score_range: {0.5, 1.0},
        match_strategy: :exact,
        required: true,
        metadata: %{}
      }
    ],
    should_match: true,
    profile: :regex_only,
    tags: [:presidio, :ip_address, :core_mvp | tags],
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
    entities: [:ip_address],
    expected: [],
    should_match: false,
    profile: :regex_only,
    tags: [:presidio, :ip_address, :invalid | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.(
    "presidio.ip.valid.ipv4.loopback",
    "source 127.0.0.1",
    "127.0.0.1",
    :ip_address,
    "IP_ADDRESS",
    [:ipv4]
  ),
  mk.(
    "presidio.ip.valid.ipv4.private",
    "client 192.168.1.10",
    "192.168.1.10",
    :ip_address,
    "IP_ADDRESS",
    [:ipv4]
  ),
  mk.("presidio.ip.valid.ipv4.public", "remote 8.8.8.8", "8.8.8.8", :ip_address, "IP_ADDRESS", [
    :ipv4
  ]),
  mk.("presidio.ip.valid.ipv6.loopback", "host ::1", "::1", :ip_address, "IP_ADDRESS", [:ipv6]),
  mk.(
    "presidio.ip.valid.ipv6.full",
    "addr 2001:0db8:85a3:0000:0000:8a2e:0370:7334",
    "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
    :ip_address,
    "IP_ADDRESS",
    [:ipv6]
  ),
  mk.(
    "presidio.ip.valid.ipv6.compressed",
    "addr 2001:db8::1",
    "2001:db8::1",
    :ip_address,
    "IP_ADDRESS",
    [:ipv6]
  ),
  negative.("presidio.ip.invalid.octet", "source 999.1.1.1", [:invalid_octet]),
  negative.("presidio.ip.invalid.format", "source 192.168.1", [:invalid_format]),
  negative.("presidio.ip.invalid.word", "source localhost", [:invalid_format]),
  negative.("presidio.ip.invalid.ipv6", "addr 2001:::1", [:invalid_format])
]
