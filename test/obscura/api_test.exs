defmodule Obscura.ApiTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Result, as: AnalyzerResult
  alias Obscura.Anonymizer.Result, as: AnonymizerResult

  test "analyze/2 returns byte offsets and explanations when requested" do
    text = "Contact jane@example.com"

    assert {:ok, [%AnalyzerResult{} = result]} =
             Obscura.analyze(text, entities: [:email], explain: true)

    assert result.entity == :email
    assert result.start == 8
    assert result.end == 24
    assert result.byte_start == 8
    assert result.byte_end == 24
    assert result.text == "jane@example.com"
    assert result.explanation.recognizer == :email
  end

  test "anonymize/3 applies entity-specific replacement operators" do
    text = "Contact jane@example.com"
    {:ok, detections} = Obscura.analyze(text, entities: [:email])

    assert {:ok, %AnonymizerResult{} = result} =
             Obscura.anonymize(text, detections,
               operators: %{email: %{type: :replace, value: "[EMAIL]"}}
             )

    assert result.text == "Contact [EMAIL]"
    assert [%{entity: :email, operator: :replace, replacement: "[EMAIL]"}] = result.items
  end

  test "redact/2 analyzes and anonymizes in one call" do
    assert {:ok, result} = Obscura.redact("Call 202-555-0188", entities: [:phone])

    assert result.text == "Call [PHONE]"
    assert [%{entity: :phone}] = result.items
  end

  test "anonymize/3 rejects invalid spans" do
    span = %{entity: :email, byte_start: 20, byte_end: 4, value: "jane@example.com"}

    assert {:error, {:invalid_span, _reason}} =
             Obscura.anonymize("Contact jane@example.com", [span])
  end
end
