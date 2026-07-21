[
  %{
    id: "presidio.context.phone.near_keyword",
    kind: :context,
    source: "inspiration/presidio/presidio-analyzer/tests/data/context_sentences_tests.txt",
    source_license: "MIT",
    text_without_context: "Value 202-555-0188",
    text_with_context: "Phone 202-555-0188",
    entities: [:phone],
    expected_entity: :phone,
    expected_value: "202-555-0188",
    expected_context_words: ["phone"],
    assertions: [:with_context_score_gt_without_context, :context_words_recorded],
    profile: :context,
    tags: [:presidio, :context, :phone],
    notes: nil,
    metadata: %{}
  },
  %{
    id: "presidio.context.credit_card.near_keyword",
    kind: :context,
    source: "inspiration/presidio/presidio-analyzer/tests/data/context_sentences_tests.txt",
    source_license: "MIT",
    text_without_context: "Value 4111 1111 1111 1111",
    text_with_context: "Credit card 4111 1111 1111 1111",
    entities: [:credit_card],
    expected_entity: :credit_card,
    expected_value: "4111 1111 1111 1111",
    expected_context_words: ["credit", "card"],
    assertions: [:with_context_score_gt_without_context, :context_words_recorded],
    profile: :context,
    tags: [:presidio, :context, :credit_card],
    notes: nil,
    metadata: %{}
  }
]
