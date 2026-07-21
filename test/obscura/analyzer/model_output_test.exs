defmodule Obscura.Analyzer.ModelOutputTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.ModelOutput

  test "normalizes character offsets to byte offsets" do
    text = "José met Alice in München"

    outputs = [
      %{label: "PER", start: 0, end: 4, offset_unit: :character, score: 0.91},
      %{label: "LOC", start: 18, end: 25, offset_unit: :character, score: 0.92}
    ]

    assert {:ok, [person, location]} = ModelOutput.normalize(text, outputs)
    assert person.entity == :person
    assert person.byte_start == 0
    assert person.byte_end == byte_size("José")
    assert location.entity == :location

    assert binary_part(text, location.byte_start, location.byte_end - location.byte_start) ==
             "München"
  end

  test "filters low scores and ignores unknown labels by default" do
    outputs = [
      %{label: "PER", start: 0, end: 5, score: 0.2},
      %{label: "UNKNOWN", start: 6, end: 10, score: 0.99}
    ]

    assert {:ok, []} = ModelOutput.normalize("Alice Test", outputs, score_threshold: 0.8)
  end

  test "drops empty model spans instead of failing the whole output list" do
    assert {:ok, [person]} =
             ModelOutput.normalize(
               "Call Rachel",
               [
                 %{label: "PER", start: 0, end: 0, score: 0.99},
                 %{label: "PER", start: 5, end: 11, score: 0.99}
               ],
               label_map: :dslim_bert_base_ner
             )

    assert person.entity == :person
    assert person.byte_start == 5
    assert person.byte_end == 11
  end

  test "matches BILOU label prefixes for thresholds and ignored labels" do
    assert {:ok, []} =
             ModelOutput.normalize(
               "Call Rachel",
               [%{label: "U-PATIENT", start: 5, end: 11, score: 0.5}],
               label_map: :obi_deid_roberta_i2b2,
               labels_to_ignore: ["PATIENT"]
             )

    assert {:ok, []} =
             ModelOutput.normalize(
               "Call Rachel",
               [%{label: "U-PATIENT", start: 5, end: 11, score: 0.5}],
               label_map: :obi_deid_roberta_i2b2,
               per_label_thresholds: %{"PATIENT" => 0.9}
             )
  end

  test "supports ignored labels, per-entity thresholds, and low score multipliers" do
    outputs = [
      %{label: "ORG", start: 0, end: 4, score: 0.84},
      %{label: "LOC", start: 8, end: 13, score: 0.8},
      %{label: "PER", start: 17, end: 22, score: 0.9}
    ]

    assert {:ok, [location]} =
             ModelOutput.normalize("Acme in Paris with Alice", outputs,
               labels_to_ignore: ["PER"],
               per_entity_thresholds: %{organization: 0.85, location: 0.3},
               low_score_entity_names: [:location],
               low_confidence_score_multiplier: 0.5
             )

    assert location.entity == :location
    assert location.score == 0.4
    assert location.metadata.model_original_score == 0.8
    assert location.metadata.model_adjusted_score == 0.4
    assert location.metadata.model_score_threshold == 0.3
  end

  test "label-level thresholds take precedence over entity-level thresholds" do
    outputs = [
      %{label: "B-GPE", start: 0, end: 5, score: 0.82},
      %{label: "B-LOC", start: 9, end: 14, score: 0.82}
    ]

    assert {:ok, [gpe]} =
             ModelOutput.normalize("Paris and Texas", outputs,
               label_map: :tner_roberta_large_ontonotes5,
               per_entity_thresholds: %{location: 0.1},
               per_label_thresholds: %{"GPE" => 0.8, "LOC" => 0.9}
             )

    assert gpe.source_entity == "B-GPE"
    assert gpe.entity == :location
    assert gpe.metadata.model_score_threshold == 0.8
    assert gpe.metadata.model_threshold_scope == :label
    assert gpe.metadata.model_threshold_label == "GPE"
  end

  test "low score labels apply the configured multiplier before thresholding" do
    outputs = [
      %{label: "B-FAC", start: 0, end: 8, score: 0.9}
    ]

    assert {:ok, [facility]} =
             ModelOutput.normalize("Hospital", outputs,
               label_map: :tner_roberta_large_ontonotes5,
               low_score_labels: ["FAC"],
               low_confidence_score_multiplier: 0.5,
               per_label_thresholds: %{"FAC" => 0.4}
             )

    assert facility.score == 0.45
    assert facility.metadata.model_original_score == 0.9
    assert facility.metadata.model_adjusted_score == 0.45
    assert facility.metadata.model_score_threshold == 0.4
    assert facility.metadata.model_threshold_label == "FAC"
  end

  test "label-level context gates mark low-confidence spans as requiring context" do
    outputs = [
      %{label: "B-FAC", start: 23, end: 31, score: 0.9}
    ]

    assert {:ok, [facility]} =
             ModelOutput.normalize("Alice visited the city hospital.", outputs,
               label_map: :tner_roberta_large_ontonotes5,
               context_required_below_labels: %{"FAC" => 0.95},
               context_words_by_entity: %{location: ["hospital"]}
             )

    assert facility.metadata.requires_context == true
    assert facility.metadata.context_required_below_score == 0.95
    assert facility.metadata.context_required_scope == :label
    assert facility.metadata.context_required_label == "FAC"
    assert facility.metadata.context_words == ["hospital"]
  end

  test "label-required context gates mark configured labels regardless of score" do
    outputs = [
      %{label: "B-FAC", start: 14, end: 21, offset_unit: :byte, score: 0.99}
    ]

    assert {:ok, [facility]} =
             ModelOutput.normalize("Alice went to Central.", outputs,
               label_map: :tner_roberta_large_ontonotes5,
               context_required_labels: ["FAC"],
               context_words_by_label: %{"FAC" => ["hospital"]}
             )

    assert facility.metadata.requires_context == true
    assert facility.metadata.context_required_below_score == 1.0
    assert facility.metadata.context_required_scope == :label
    assert facility.metadata.context_required_label == "FAC"
    assert facility.metadata.model_context_gate_policy == :label_always_requires_context
  end

  test "label-specific context words and weak words are recorded for gated spans" do
    outputs = [
      %{label: "B-FAC", start: 14, end: 21, offset_unit: :byte, score: 0.9}
    ]

    assert {:ok, [facility]} =
             ModelOutput.normalize("Alice went in Central.", outputs,
               label_map: :tner_roberta_large_ontonotes5,
               context_required_below_labels: %{"FAC" => 0.95},
               context_words_by_label: %{"FAC" => ["hospital"]},
               context_words_by_entity: %{location: ["in"]},
               weak_context_words_by_label: %{"FAC" => ["in"]}
             )

    assert facility.metadata.requires_context == true
    assert facility.metadata.context_words == ["hospital", "in"]
    assert facility.metadata.weak_context_words == ["in"]
  end

  test "label-specific negative context words are recorded for gated spans" do
    outputs = [
      %{label: "B-GPE", start: 21, end: 26, offset_unit: :byte, score: 0.95}
    ]

    assert {:ok, [location]} =
             ModelOutput.normalize("Invoice reference Paris was generated.", outputs,
               label_map: :tner_roberta_large_ontonotes5,
               context_required_below_labels: %{"GPE" => 0.97},
               context_words_by_label: %{"GPE" => ["city"]},
               weak_context_words_by_label: %{"GPE" => ["in"]},
               negative_context_words_by_label: %{"GPE" => ["invoice", "reference"]},
               negative_context_reject_labels: ["GPE"]
             )

    assert location.metadata.requires_context == true
    assert location.metadata.context_required_label == "GPE"
    assert location.metadata.negative_context_words == ["invoice", "reference"]
    assert location.metadata.negative_context_reject == true
    assert location.metadata.context_source == :nlp_artifacts
    assert location.metadata.context_matching_mode == :whole_word
  end

  test "ignored labels match BIOES base labels" do
    assert {:ok, []} =
             ModelOutput.normalize(
               "Acme sent mail.",
               [%{label: "B-company_name", start: 0, end: 4, score: 0.99}],
               label_map: :openmed_pii_bigmed_large,
               labels_to_ignore: ["company_name"]
             )
  end

  test "structured model validation rejects invalid model-predicted structured PII" do
    text = "Alice wrote at words and 4111111111111111."

    outputs = [
      %{label: "email", start: 15, end: 20, offset_unit: :byte, score: 0.99},
      %{label: "credit_debit_card", start: 25, end: 41, offset_unit: :byte, score: 0.99}
    ]

    assert {:ok, [credit_card]} =
             ModelOutput.normalize(text, outputs,
               label_map: :openmed_pii_bigmed_large,
               validate_structured_model_entities: true
             )

    assert credit_card.entity == :credit_card
    assert credit_card.metadata.model_structured_validation == :passed
  end

  test "expands partial model spans to token boundaries by default" do
    text = "Rachel works in Paris."

    assert {:ok, [location]} =
             ModelOutput.normalize(text, [
               %{label: "LOC", start: 17, end: 19, offset_unit: :byte, score: 0.91}
             ])

    assert location.entity == :location
    assert location.text == "Paris"
    assert location.byte_start == 16
    assert location.byte_end == 21
    assert location.metadata.model_alignment_mode == :expand
    assert location.metadata.model_original_byte_start == 17
    assert location.metadata.model_original_byte_end == 19
    assert location.metadata.model_boundary_adjusted == true
  end

  test "strict model alignment preserves original offsets" do
    text = "Rachel works in Paris."

    assert {:ok, [location]} =
             ModelOutput.normalize(
               text,
               [%{label: "LOC", start: 17, end: 19, offset_unit: :byte, score: 0.91}],
               alignment_mode: :strict
             )

    assert location.text == "ar"
    assert location.byte_start == 17
    assert location.byte_end == 19
    assert location.metadata.model_alignment_mode == :strict
  end

  test "conservative boundary normalization trims punctuation and trailing connectors" do
    text = "Reported name: Alice and phone."

    assert {:ok, [person]} =
             ModelOutput.normalize(
               text,
               [%{label: "PER", start: 15, end: 24, offset_unit: :byte, score: 0.91}],
               boundary_normalization: :conservative
             )

    assert person.text == "Alice"
    assert person.byte_start == 15
    assert person.byte_end == 20
    assert person.metadata.model_boundary_normalization == :conservative
    assert person.metadata.model_boundary_normalized == true
  end

  test "boundary normalization is disabled by default" do
    text = "Reported name: Alice and phone."

    assert {:ok, [person]} =
             ModelOutput.normalize(text, [
               %{label: "PER", start: 15, end: 24, offset_unit: :byte, score: 0.91}
             ])

    assert person.text == "Alice and"
    assert person.metadata.model_boundary_normalization == :none
  end

  test "model-anchored organization suffix expansion expands only model spans" do
    text = "Alice works at Acme Corp today."

    assert {:ok, [organization]} =
             ModelOutput.normalize(
               text,
               [%{label: "ORG", start: 15, end: 19, offset_unit: :byte, score: 0.99}],
               model_postprocessors: [:organization_suffix_expansion],
               label_map: :tner_roberta_large_ontonotes5,
               include_text: true
             )

    assert organization.entity == :organization
    assert organization.text == "Acme Corp"
    assert organization.byte_start == 15
    assert organization.byte_end == 24
    assert organization.metadata.model_postprocess_state == :expanded
    assert [event] = organization.metadata.model_postprocess_events
    assert event.postprocessor == :organization_suffix_expansion
    assert event.state == :expanded
    assert event.suffix_token == "Corp"
  end

  test "model-anchored location suffix expansion expands only location model spans" do
    text = "Alice visited Central Hospital."

    assert {:ok, [location]} =
             ModelOutput.normalize(
               text,
               [%{label: "FAC", start: 14, end: 21, offset_unit: :byte, score: 0.99}],
               model_postprocessors: [:location_suffix_expansion],
               label_map: :tner_roberta_large_ontonotes5,
               include_text: true
             )

    assert location.entity == :location
    assert location.text == "Central Hospital"
    assert location.metadata.model_postprocess_state == :expanded
    assert [event] = location.metadata.model_postprocess_events
    assert event.postprocessor == :location_suffix_expansion
    assert event.state == :expanded
    assert event.suffix_token == "Hospital"
  end

  test "model postprocessor records unchanged and rejected states" do
    assert {:ok, [organization]} =
             ModelOutput.normalize(
               "Alice works at Acme today.",
               [%{label: "ORG", start: 15, end: 19, offset_unit: :byte, score: 0.99}],
               model_postprocessors: [:organization_suffix_expansion],
               label_map: :tner_roberta_large_ontonotes5
             )

    assert organization.metadata.model_postprocess_state == :unchanged
    assert [unchanged_event] = organization.metadata.model_postprocess_events
    assert unchanged_event.state == :unchanged
    assert unchanged_event.reason == :next_token_not_suffix

    assert {:ok, [person]} =
             ModelOutput.normalize(
               "Alice works at Acme Corp.",
               [%{label: "PERSON", start: 0, end: 5, offset_unit: :byte, score: 0.99}],
               model_postprocessors: [:organization_suffix_expansion],
               label_map: :tner_roberta_large_ontonotes5
             )

    assert person.metadata.model_postprocess_state == :rejected
    assert [rejected_event] = person.metadata.model_postprocess_events
    assert rejected_event.state == :rejected
    assert rejected_event.reason == :entity_not_supported
  end

  test "returns safe errors for invalid offsets" do
    assert {:error, :model_offset_out_of_bounds} =
             ModelOutput.normalize("Alice", [
               %{label: "PER", start: 0, end: 99, offset_unit: :character}
             ])
  end

  test "marks low-confidence model spans as requiring context when configured" do
    assert {:ok, [organization]} =
             ModelOutput.normalize(
               "Alice works at Acme.",
               [%{label: "ORG", start: 15, end: 19, score: 0.9}],
               context_required_below_thresholds: %{organization: 0.95},
               context_words_by_entity: %{organization: ["works at"]}
             )

    assert organization.metadata.requires_context == true
    assert organization.metadata.context_required_below_score == 0.95
    assert organization.metadata.context_words == ["works at"]
    assert organization.metadata.model_context_gate == :score_below_context_threshold
  end
end
