defmodule Obscura.Eval.ReportTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Metrics
  alias Obscura.Eval.Report

  test "builds report with required top-level fields" do
    metrics = Metrics.score([], [], :regex_only)

    report =
      Report.build(
        run_id: "test",
        adapter: "Adapter",
        profile: :regex_only,
        dataset: %{
          name: "fixtures",
          source: "fixtures",
          version: "phase_0",
          sample_count: 0,
          smoke: true
        },
        metrics: metrics,
        limitations: ["test limitation"]
      )

    for key <- [
          :run_id,
          :phase,
          :timestamp,
          :git_sha,
          :dependencies,
          :adapter,
          :profile,
          :dataset,
          :entity_mapping,
          :offset_mode,
          :metrics,
          :per_entity,
          :latency,
          :stage_latency,
          :examples,
          :skip_reason,
          :limitations
        ] do
      assert Map.has_key?(report, key)
    end

    assert report.phase == "phase_0"
    assert report.profile == "regex_only"
    assert is_binary(report.dependencies["obscura"])
    assert is_binary(report.dependencies["mix_lock_sha256"])
    assert {:ok, _timestamp, 0} = DateTime.from_iso8601(report.timestamp)
    assert Report.markdown(report) =~ "Phase 0 Evaluation Report"
  end

  test "writes JSON and Markdown reports" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "obscura-report-test-#{System.unique_integer([:positive])}")

    json_path = Path.join(tmp_dir, "report.json")
    md_path = Path.join(tmp_dir, "report.md")
    metrics = Metrics.score([], [], :regex_only)

    report =
      Report.build(
        run_id: "test",
        adapter: "Adapter",
        profile: :regex_only,
        dataset: %{
          name: "fixtures",
          source: "fixtures",
          version: "phase_0",
          sample_count: 0,
          smoke: true
        },
        metrics: metrics,
        limitations: []
      )

    assert :ok = Report.write_pair(report, json_path, md_path)
    assert {:ok, decoded} = json_path |> File.read!() |> Jason.decode()
    assert decoded["dataset"]["smoke"] == true
    assert decoded["metrics"]["precision"] == nil
    assert File.read!(md_path) =~ "Phase 0 Evaluation Report"
  end

  test "omits raw values from report examples" do
    metrics =
      Metrics.score(
        [%{entity: :email, byte_start: 0, byte_end: 16, value: "jane@example.com"}],
        [],
        :regex_only
      )

    report =
      Report.build(
        run_id: "test",
        adapter: "Adapter",
        profile: :regex_only,
        dataset: %{
          name: "fixtures",
          source: "fixtures",
          version: "phase_1",
          sample_count: 1,
          smoke: true
        },
        metrics: metrics,
        limitations: []
      )

    assert [%{value: "[omitted]"}] = report.examples.false_negatives

    assert report.metrics.error_buckets.false_negatives.email.examples == [
             %{byte_end: 16, byte_start: 0, entity: :email, value: "[omitted]"}
           ]

    assert report.metrics.error_buckets.false_negatives.email.likely_causes ==
             %{recognizer_recall_gap: 1}
  end

  test "markdown includes error bucket and wrong entity matrix summaries" do
    metrics =
      Metrics.score(
        [%{entity: :email, byte_start: 0, byte_end: 16, value: "jane@example.com"}],
        [%{entity: :phone, byte_start: 0, byte_end: 16, text: "jane@example.com"}],
        :regex_only
      )

    report =
      Report.build(
        run_id: "test",
        adapter: "Adapter",
        profile: :regex_only,
        dataset: %{
          name: "fixtures",
          source: "fixtures",
          version: "phase_1",
          sample_count: 1,
          smoke: true
        },
        metrics: metrics,
        limitations: []
      )

    markdown = Report.markdown(report)

    assert markdown =~ "### Error Buckets"
    assert markdown =~ "### Top Sanitized Error Signatures"
    assert markdown =~ "Likely causes"
    assert markdown =~ "recognizer_label_confusion: 1"
    assert markdown =~ "#### Wrong Entity Matrix"
    assert markdown =~ "| email | phone | 1 |"
    assert markdown =~ "### Example Errors"
    assert markdown =~ "#### Wrong entity type"
    assert markdown =~ "| email/phone | 0/0 | 16/16 | n/a | n/a/n/a |"

    assert report.metrics.error_buckets.wrong_entity_type.email.examples |> inspect() =~
             "[omitted]"
  end

  test "markdown includes model-label error analysis" do
    metrics =
      Metrics.score(
        [
          %{entity: :location, byte_start: 0, byte_end: 5},
          %{entity: :organization, byte_start: 20, byte_end: 24}
        ],
        [
          %{
            entity: :location,
            byte_start: 8,
            byte_end: 13,
            text: "Paris",
            recognizer: :ner,
            source_entity: "B-FAC",
            metadata: %{
              model_label: "B-FAC",
              template_id: "template_a",
              sample_id: "sample_a",
              requires_context: true
            }
          },
          %{
            entity: :organization,
            byte_start: 20,
            byte_end: 23,
            text: "Acm",
            recognizer: :ner,
            source_entity: "B-ORG",
            metadata: %{
              model_label: "B-ORG",
              template_id: "template_b",
              sample_id: "sample_b",
              model_boundary_adjusted: true,
              conflict_policy: :presidio_like,
              conflict_reason: :exact_duplicate_contained_or_structured_precedence
            }
          }
        ],
        :hybrid_ner_tner_conservative
      )

    report =
      Report.build(
        run_id: "test",
        adapter: "Adapter",
        profile: :hybrid_ner_tner_conservative,
        dataset: %{
          name: "fixtures",
          source: "fixtures",
          version: "phase_1",
          sample_count: 1,
          smoke: true
        },
        metrics: metrics,
        limitations: []
      )

    markdown = Report.markdown(report)

    assert markdown =~ "### Model Label Error Analysis"
    assert markdown =~ "#### False positives by model label"
    assert markdown =~ "| B-FAC | 1 | location: 1 | template_a: 1 |"
    assert markdown =~ "#### False negatives by expected entity"
    assert markdown =~ "| location | 1 | location: 1 | n/a |"
    assert markdown =~ "#### Offset mismatches by model label"
    assert markdown =~ "| B-ORG | 1 | organization: 1 | template_b: 1 |"
    assert markdown =~ "### Actionable Error Rows"
    assert markdown =~ "#### Location false positives by GPE/FAC/LOC model label"
    assert markdown =~ "#### Location false negatives by template/context"
    assert markdown =~ "#### Organization false negatives by template/context"
    assert markdown =~ "Score bucket"
    assert markdown =~ "Boundary"
    assert markdown =~ "### Structured Model Error Rows"
    assert markdown =~ "Presidio-Research-style error context"
    assert markdown =~ "| FP | O | location | location | B-FAC | AAAAA |"
    assert markdown =~ "missing_required"
    assert markdown =~ "sample_a"
    assert markdown =~ "template_a"
    assert markdown =~ "presidio_like/exact_duplicate_contained_or_structured_precedence"
  end

  test "markdown includes per-template metrics and threshold sweeps" do
    metrics =
      Metrics.score_results(
        [
          %{
            sample: %{template_id: "template_a"},
            expected: [%{entity: :email, byte_start: 0, byte_end: 16}],
            predicted: [],
            latency_ms: 1.0
          }
        ],
        :regex_only
      )

    report =
      Report.build(
        run_id: "test",
        adapter: "Adapter",
        profile: :regex_only,
        dataset: %{
          name: "fixtures",
          source: "fixtures",
          version: "phase_1",
          sample_count: 1,
          smoke: true
        },
        metrics: metrics,
        threshold_sweep: %{
          best: %{
            score_threshold: 0.7,
            precision: 1.0,
            recall: 0.5,
            f1: 0.6667
          },
          rows: [
            %{
              score_threshold: 0.7,
              per_entity_thresholds: %{person: 0.7, location: 0.7, organization: 0.85},
              precision: 1.0,
              recall: 0.5,
              f1: 0.6667,
              f2: 0.5556,
              true_positives: 1,
              false_positives: 0,
              false_negatives: 1,
              offset_mismatches: 0,
              wrong_entity_type: 0,
              unsupported_expected_spans: 0
            }
          ]
        },
        limitations: []
      )

    markdown = Report.markdown(report)

    assert markdown =~ "### Worst Per-Template Metrics"
    assert markdown =~ "| template_a | 1 |"
    assert markdown =~ "### Threshold Sweep"
    assert markdown =~ "organization=0.8500"
  end

  test "markdown includes template split metadata" do
    metrics = Metrics.score([], [], :regex_only)

    report =
      Report.build(
        run_id: "test",
        adapter: "Adapter",
        profile: :regex_only,
        dataset: %{
          name: "fixtures",
          source: "fixtures",
          version: "phase_1",
          sample_count: 1,
          smoke: false,
          template_split: %{
            name: :template_heldout,
            strategy: :template_id,
            train_ratio: 0.7,
            template_count: 10,
            selected_template_count: 3,
            heldout_template_count: 3
          }
        },
        metrics: metrics,
        limitations: []
      )

    markdown = Report.markdown(report)

    assert markdown =~ "### Template Split"
    assert markdown =~ "| Split | template_heldout |"
    assert markdown =~ "| Selected templates | 3 |"
  end
end
