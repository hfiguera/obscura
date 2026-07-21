mk = fn id, text, value, replacement, config, tags ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)
  expected_text = String.replace(text, value, replacement)
  {replacement_start, _length} = :binary.match(expected_text, replacement)
  replacement_end = replacement_start + byte_size(replacement)

  %{
    id: id,
    kind: :operator,
    source: "inspiration/presidio/presidio-anonymizer/tests/operators/test_mask.py",
    source_license: "MIT",
    text: text,
    spans: [
      %{
        entity: :phone,
        byte_start: byte_start,
        byte_end: byte_end,
        char_start: char_start,
        char_end: char_end,
        value: value,
        score: 1.0,
        source_entity: "PHONE_NUMBER",
        metadata: %{}
      }
    ],
    operators: %{default: Map.put(config, :type, :mask)},
    expected_text: expected_text,
    expected_items: [
      %{
        entity: :phone,
        operator: :mask,
        source_byte_start: byte_start,
        source_byte_end: byte_end,
        replacement_byte_start: replacement_start,
        replacement_byte_end: replacement_end,
        replacement: replacement,
        metadata: %{}
      }
    ],
    tags: [:presidio, :operator, :mask | tags],
    notes: nil,
    metadata: %{}
  }
end

[
  mk.(
    "presidio.operator.mask.phone.all",
    "Call 202-555-0188",
    "202-555-0188",
    "************",
    %{char: "*"},
    [:mask_all]
  ),
  mk.(
    "presidio.operator.mask.phone.keep_last",
    "Call 202-555-0188",
    "202-555-0188",
    "********0188",
    %{char: "*", keep_last: 4},
    [:keep_last]
  )
]
