defmodule Obscura.Fixtures.FixtureRunnerTest do
  use ExUnit.Case, async: true

  alias Obscura.Fixtures.Runner

  test "runs all fixtures with real Obscura adapters by default" do
    assert {:ok, report} = Runner.run()

    assert report.run_id == "phase_4_fixture_smoke"
    assert report.phase == "phase_4"
    assert report.adapter == "Obscura.Fixtures.ObscuraAnalyzerAdapter"
    assert report.metrics.true_positives == report.metrics.total_supported_expected_spans
    assert report.metrics.false_negatives == 0
    assert report.metrics.false_positives == 0
  end

  test "runs NLP and NER fixture suites" do
    assert {:ok, nlp_report} = Runner.run(suite: :nlp, profile: :nlp)
    assert {:ok, ner_report} = Runner.run(suite: :ner, profile: :nlp)

    assert nlp_report.run_id == "phase_4_nlp_smoke"
    assert ner_report.run_id == "phase_4_ner_smoke"
    assert nlp_report.metrics.false_negatives == 0
    assert ner_report.metrics.false_negatives == 0
  end

  test "runs opt-in accuracy fixtures with deterministic_plus profile" do
    assert {:ok, report} = Runner.run(suite: :accuracy)

    assert report.run_id == "phase_4_accuracy_fixture_smoke"
    assert report.profile == "deterministic_plus"
    assert report.dataset.suite == "accuracy"
    assert report.metrics.true_positives == report.metrics.total_supported_expected_spans
    assert report.metrics.false_negatives == 0
    assert report.metrics.false_positives == 0
    assert report.metrics.unsupported_expected_spans == 0
  end

  test "can still run placeholder adapters for baseline reports" do
    assert {:ok, report} = Runner.run(adapter: :placeholder, suite: :analyzer)

    assert report.run_id == "phase_0_fixture_smoke"
    assert report.phase == "phase_0"
    assert report.adapter == "Obscura.Fixtures.PlaceholderAnalyzer"
    assert report.metrics.true_positives == 0
    assert report.metrics.false_negatives > 0
  end

  test "filters fixtures by suite, entity, and tag" do
    assert {:ok, report} = Runner.run(suite: :analyzer, entity: "email", tag: "unicode")

    assert report.dataset.suite == "analyzer"
    assert report.dataset.sample_count > 0
    assert report.metrics.false_negatives == 0
    assert report.metrics.false_positives == 0
  end
end
