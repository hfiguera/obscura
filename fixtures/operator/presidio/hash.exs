text = "Card 4111111111111111"
value = "4111111111111111"
salt = "phase0-salt-0001"
encoded_salt = Base.url_encode64(salt, padding: false)
digest = :crypto.hash(:sha256, salt <> value) |> Base.encode16(case: :lower)

replacement =
  Enum.join(["$obscura", "v1", "hash", "sha256", "deterministic", encoded_salt, digest], "$")

{byte_start, _length} = :binary.match(text, value)
byte_end = byte_start + byte_size(value)
{:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
{:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)
expected_text = String.replace(text, value, replacement)
{replacement_start, _length} = :binary.match(expected_text, replacement)
replacement_end = replacement_start + byte_size(replacement)

[
  %{
    id: "presidio.operator.hash.credit_card.sha256_salted",
    kind: :operator,
    source: "inspiration/presidio/presidio-anonymizer/tests/operators/test_hash.py",
    source_license: "MIT",
    text: text,
    spans: [
      %{
        entity: :credit_card,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        score: 1.0,
        source_entity: "CREDIT_CARD",
        metadata: %{}
      }
    ],
    operators: %{
      default: %{type: :hash, mode: :deterministic, algorithm: :sha256, salt: salt}
    },
    expected_text: expected_text,
    expected_items: [
      %{
        entity: :credit_card,
        operator: :hash,
        source_byte_start: byte_start,
        source_byte_end: byte_end,
        replacement_byte_start: replacement_start,
        replacement_byte_end: replacement_end,
        replacement: replacement,
        metadata: %{
          algorithm: :sha256,
          deterministic: true,
          mode: :deterministic,
          salt: encoded_salt,
          version: 1
        }
      }
    ],
    tags: [:presidio, :operator, :hash, :deterministic],
    notes: "Deterministic mode uses an explicit 16-byte salt and versioned replacement.",
    metadata: %{}
  }
]
