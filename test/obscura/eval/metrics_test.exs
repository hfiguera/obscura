defmodule Obscura.Eval.MetricsTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Metrics

  test "calculates precision, recall, F1, and F2" do
    expected = [
      %{entity: :email, byte_start: 0, byte_end: 5},
      %{entity: :phone, byte_start: 10, byte_end: 15}
    ]

    predicted = [
      %{entity: :email, byte_start: 0, byte_end: 5},
      %{entity: :phone, byte_start: 99, byte_end: 100}
    ]

    metrics = Metrics.score(expected, predicted, :regex_only)

    assert metrics.true_positives == 1
    assert metrics.false_positives == 1
    assert metrics.false_negatives == 1
    assert metrics.precision == 0.5
    assert metrics.recall == 0.5
    assert metrics.f1 == 0.5
    assert metrics.f2 == 0.5
    assert metrics.error_buckets.false_positives.phone.count == 1
    assert metrics.error_buckets.false_negatives.phone.count == 1
  end

  test "tracks wrong entity types separately" do
    expected = [%{entity: :email, byte_start: 0, byte_end: 5}]
    predicted = [%{entity: :phone, byte_start: 0, byte_end: 5}]

    metrics = Metrics.score(expected, predicted, :regex_only)

    assert metrics.wrong_entity_type == 1
    assert metrics.offset_mismatches == 0
    assert metrics.false_positives == 0
    assert metrics.false_negatives == 0
    assert metrics.wrong_entity_matrix.email.phone == 1
  end

  test "tracks same-entity offset mismatches separately" do
    expected = [%{entity: :email, byte_start: 0, byte_end: 16}]
    predicted = [%{entity: :email, byte_start: 0, byte_end: 15}]

    metrics = Metrics.score(expected, predicted, :regex_only)

    assert metrics.offset_mismatches == 1
    assert metrics.wrong_entity_type == 0
    assert metrics.false_positives == 0
    assert metrics.false_negatives == 0
    assert [{expected_span, predicted_span}] = metrics.examples.offset_mismatches
    assert expected_span.byte_end == 16
    assert predicted_span.byte_end == 15
  end

  test "adds IoU span metrics beside exact metrics" do
    expected = [%{entity: :person, byte_start: 0, byte_end: 12}]
    predicted = [%{entity: :person, byte_start: 0, byte_end: 11}]

    metrics = Metrics.score(expected, predicted, :nlp, iou_threshold: 0.8)

    assert metrics.true_positives == 0
    assert metrics.offset_mismatches == 1
    assert metrics.span_iou.true_positives == 1
    assert metrics.span_iou.false_positives == 0
    assert metrics.span_iou.false_negatives == 0
    assert metrics.span_iou.recall == 1.0
  end

  test "IoU span metrics track wrong entity types" do
    expected = [%{entity: :person, byte_start: 0, byte_end: 5}]
    predicted = [%{entity: :location, byte_start: 0, byte_end: 5}]

    metrics = Metrics.score(expected, predicted, :nlp, iou_threshold: 0.9)

    assert metrics.span_iou.wrong_entity_type == 1
    assert metrics.span_iou.false_positives == 0
    assert metrics.span_iou.false_negatives == 0
  end

  test "normalized span diagnostics merge adjacent spans separated by skip words" do
    text = "The branch is North Valley of Seattle."

    expected = [
      %{entity: :location, byte_start: 14, byte_end: 37, text: "North Valley of Seattle"}
    ]

    predicted = [
      %{entity: :location, byte_start: 14, byte_end: 26, text: "North Valley"},
      %{entity: :location, byte_start: 30, byte_end: 37, text: "Seattle"}
    ]

    metrics = Metrics.score(expected, predicted, :hybrid_ner_tner_conservative, sample_text: text)

    assert metrics.offset_mismatches == 1
    assert metrics.span_normalization.predicted_merge_count == 1
    assert metrics.span_normalization.span_iou.true_positives == 1
    assert metrics.span_normalization.span_iou.f1 == 1.0
  end

  test "handles zero denominators deterministically" do
    metrics = Metrics.score([], [], :regex_only)

    assert metrics.precision == nil
    assert metrics.recall == nil
    assert metrics.f1 == nil
    assert metrics.f2 == nil
  end

  test "supports scoring a requested entity subset" do
    expected = [
      %{entity: :person, byte_start: 0, byte_end: 5},
      %{entity: :location, byte_start: 10, byte_end: 16}
    ]

    predicted = [%{entity: :person, byte_start: 0, byte_end: 5}]

    metrics =
      Metrics.score(expected, predicted, :hybrid_ner_tner_jean_location,
        supported_entities: [:person]
      )

    assert metrics.true_positives == 1
    assert metrics.false_negatives == 0
    assert metrics.unsupported_expected_spans == 1
    assert metrics.total_supported_expected_spans == 1
    assert metrics.precision == 1.0
    assert metrics.recall == 1.0
  end

  test "scores runner results per sample before aggregating" do
    results = [
      %{
        sample: %{template_id: "template_a"},
        expected: [%{entity: :domain, byte_start: 13, byte_end: 24}],
        predicted: [],
        latency_ms: 1.0,
        stage_latency_ms: %{tokenization_ms: 0.1, model_ms: 0.2, decode_ms: 0.3}
      },
      %{
        sample: %{template_id: "template_b"},
        expected: [],
        predicted: [
          %{
            entity: :credit_card,
            byte_start: 13,
            byte_end: 24,
            recognizer: :credit_card,
            metadata: %{sample_id: 2, template_id: "template_b"}
          }
        ],
        latency_ms: 2.0,
        stage_latency_ms: %{tokenization_ms: 0.3, model_ms: 0.4, decode_ms: 0.5}
      }
    ]

    metrics = Metrics.score_results(results, :regex_only)

    assert metrics.true_positives == 0
    assert metrics.false_negatives == 1
    assert metrics.false_positives == 1
    assert metrics.offset_mismatches == 0
    assert metrics.wrong_entity_type == 0
    assert metrics.span_iou.false_negatives == 1
    assert metrics.per_template["template_a"].false_negatives == 1
    assert metrics.per_template["template_b"].false_positives == 1
    assert [signature] = metrics.error_signatures.false_positives
    assert signature.entity == :credit_card
    assert signature.recognizer == :credit_card
    assert signature.template_id == "template_b"
    assert metrics.stage_latency.tokenization_ms.mean_ms == 0.2
    assert metrics.stage_latency.model_ms.p95_ms == 0.4
    assert metrics.stage_latency.decode_ms.max_ms == 0.5
  end

  test "scores runner result templates with a requested entity subset" do
    results = [
      %{
        sample: %{template_id: "template_a"},
        expected: [
          %{entity: :person, byte_start: 0, byte_end: 5},
          %{entity: :location, byte_start: 10, byte_end: 16}
        ],
        predicted: [%{entity: :person, byte_start: 0, byte_end: 5}],
        latency_ms: 1.0,
        stage_latency_ms: nil
      }
    ]

    metrics =
      Metrics.score_results(results, :hybrid_ner_tner_jean_location,
        supported_entities: [:person]
      )

    assert metrics.false_negatives == 0
    assert metrics.unsupported_expected_spans == 1
    assert metrics.per_template["template_a"].false_negatives == 0
    assert metrics.per_template["template_a"].unsupported_expected_spans == 1
  end

  test "actionable location and organization false negative rows include source label and sample context" do
    expected = [
      %{
        entity: :location,
        source_entity: "GPE",
        byte_start: 0,
        byte_end: 5,
        text: "Paris",
        metadata: %{sample_id: "sample-1", template_id: "template_location"}
      },
      %{
        entity: :organization,
        source_entity: "ORG",
        byte_start: 10,
        byte_end: 22,
        text: "Acme Corp",
        metadata: %{sample_id: "sample-2", template_id: "template_org"}
      }
    ]

    metrics = Metrics.score(expected, [], :hybrid_ner_tner_conservative)

    assert [
             %{
               label: :location,
               source_label: "GPE",
               entity: :location,
               score_bucket: "n/a",
               context_state: :not_required,
               sample_ids: ["sample-1"],
               template_ids: ["template_location"]
             }
           ] = metrics.actionable_errors.location_false_negatives_by_template_context

    assert [
             %{
               label: :organization,
               source_label: "ORG",
               entity: :organization,
               score_bucket: "n/a",
               context_state: :not_required,
               sample_ids: ["sample-2"],
               template_ids: ["template_org"]
             }
           ] = metrics.actionable_errors.organization_false_negatives_by_template_context
  end
end
