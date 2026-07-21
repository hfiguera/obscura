defmodule Obscura.Recognizer.Phase2ExtensibilityTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.PatternDefinition

  defmodule TicketRecognizer do
    @behaviour Obscura.Recognizer

    alias Obscura.Analyzer.Result

    def name, do: :ticket
    def supported_entities, do: [:ticket]

    def analyze(text, _opts) do
      for [{start, length}] <- Regex.scan(~r/TKT-\d{4}/, text, return: :index) do
        value = binary_part(text, start, length)

        %Result{
          entity: :ticket,
          start: start,
          end: start + length,
          byte_start: start,
          byte_end: start + length,
          score: 0.8,
          text: value,
          source_entity: "TICKET",
          recognizer: :ticket,
          metadata: %{}
        }
      end
    end
  end

  test "analyze/2 accepts custom recognizer modules" do
    assert {:ok, [result]} =
             Obscura.analyze("Ticket TKT-1234",
               entities: [:ticket],
               recognizers: [TicketRecognizer]
             )

    assert result.entity == :ticket
    assert result.text == "TKT-1234"
  end

  test "analyze/2 accepts inline pattern definitions" do
    recognizer =
      PatternDefinition.new!(
        name: :employee_id,
        entity: :employee_id,
        patterns: [%{name: :employee_id_v1, regex: ~r/EMP-\d{6}/, score: 0.65}],
        context: ["employee"]
      )

    assert {:ok, [result]} =
             Obscura.analyze("employee EMP-123456",
               entities: [:employee_id],
               recognizers: [recognizer],
               explain: true,
               context: ["employee"]
             )

    assert result.entity == :employee_id
    assert result.score > 0.65
    assert result.explanation.context_words == ["employee"]
  end

  test "pattern definitions support validation score changes and invalidation drops" do
    recognizer =
      PatternDefinition.new!(
        name: :case_id,
        entity: :case_id,
        patterns: [%{name: :case_id_v1, regex: ~r/CASE-\d{3}/, score: 0.2}],
        validate: fn
          "CASE-123" -> {:ok, 0.9, %{checksum: :valid}}
          _value -> false
        end,
        invalidate: fn value -> value == "CASE-000" end
      )

    assert {:ok, [result]} =
             Obscura.analyze("CASE-123 CASE-000",
               entities: [:case_id],
               recognizers: [recognizer],
               explain: true
             )

    assert result.text == "CASE-123"
    assert result.score == 0.9
    assert result.metadata.checksum == :valid
    assert result.explanation.validation == :valid
  end

  test "weak pattern definitions can require context before acceptance" do
    recognizer =
      PatternDefinition.new!(
        name: :postal_code,
        entity: :postal_code,
        patterns: [
          %{
            name: :zip_like,
            regex: ~r/\b\d{5}\b/,
            score: 0.2,
            requires_context: true,
            context_min_score: 0.55
          }
        ],
        context: ["zip"]
      )

    assert {:ok, []} =
             Obscura.analyze("Value 12345",
               entities: [:postal_code],
               recognizers: [recognizer],
               score_threshold: 0.5
             )

    assert {:ok, [result]} =
             Obscura.analyze("ZIP 12345",
               entities: [:postal_code],
               recognizers: [recognizer],
               profile: :context,
               score_threshold: 0.5
             )

    assert result.score >= 0.55
    assert result.metadata.context_matched == true
  end

  test "deny lists and allow lists compose with analyzer results" do
    assert {:ok, [project]} =
             Obscura.analyze("Project ORCHID",
               entities: [:project_codename],
               deny_lists: [
                 %{entity: :project_codename, values: ["orchid"], case_sensitive: false}
               ]
             )

    assert project.text == "ORCHID"

    assert {:ok, [email]} =
             Obscura.analyze("support@example.com jane@example.com",
               entities: [:email],
               allow_list: [%{entity: :email, values: ["support@example.com"]}]
             )

    assert email.text == "jane@example.com"
  end
end
