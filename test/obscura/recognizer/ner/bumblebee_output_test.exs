defmodule Obscura.Recognizer.NER.BumblebeeOutputTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.ModelOutput
  alias Obscura.Recognizer.NER.BumblebeeOutput

  test "normalizes Bumblebee entities with atom keys" do
    text = "Rachel Green works at Ralph Lauren in New York City."

    output = %{
      entities: [
        %{label: "PER", phrase: "Rachel Green", start: 0, end: 12, score: 0.9997},
        %{label: "ORG", phrase: "Ralph Lauren", start: 22, end: 34, score: 0.9968},
        %{label: "MISC", phrase: "ignored", start: 38, end: 46, score: 0.5}
      ]
    }

    assert {:ok, normalized} = BumblebeeOutput.normalize(text, output, offset_unit: :byte)
    assert [%{label: "PER"}, %{label: "ORG"}, %{label: "MISC"}] = normalized
    refute Enum.any?(normalized, &Map.has_key?(&1, :phrase))

    assert {:ok, [person, organization]} =
             ModelOutput.normalize(text, normalized, label_map: :dslim_bert_base_ner)

    assert person.entity == :person
    assert organization.entity == :organization
  end

  test "normalizes string-keyed entities and direct entity lists" do
    text = "Alice is in Denver"

    output = [
      %{"label" => "PER", "start" => 0, "end" => 5, "score" => 0.9},
      %{"label" => "LOC", "start" => 12, "end" => 18, "score" => 0.8}
    ]

    assert {:ok, normalized} = BumblebeeOutput.normalize(text, output)
    assert [%{label: "PER", start: 0, end: 5}, %{label: "LOC", start: 12, end: 18}] = normalized
  end

  test "strict phrase validation rejects mismatched spans without exposing phrase" do
    output = %{entities: [%{label: "PER", phrase: "Alice", start: 0, end: 3, score: 0.9}]}

    assert {:error, :bumblebee_phrase_mismatch} =
             BumblebeeOutput.normalize("Alice", output, strict_phrase_validation: true)
  end

  test "long-text byte offsets align fragmented model spans to full tokens" do
    prefix = String.duplicate("padding ", 40)
    text = prefix <> "Rachel Green visited New York City."
    person_start = byte_size(prefix)
    person_end = person_start + byte_size("Rachel Green")

    output = %{
      entities: [
        %{
          label: "PER",
          start: person_start + 1,
          end: person_end - 1,
          score: 0.93
        }
      ]
    }

    assert {:ok, normalized} = BumblebeeOutput.normalize(text, output, offset_unit: :byte)

    assert {:ok, [person]} =
             ModelOutput.normalize(text, normalized,
               label_map: :dslim_bert_base_ner,
               alignment_mode: :expand
             )

    assert person.text == "Rachel Green"
    assert person.byte_start == person_start
    assert person.byte_end == person_end
    assert person.metadata.model_boundary_adjusted == true
  end

  test "returns safe errors for malformed output" do
    assert {:error, :invalid_bumblebee_output} = BumblebeeOutput.normalize("Alice", %{})

    assert {:error, {:invalid_bumblebee_offset, :start}} =
             BumblebeeOutput.normalize("Alice", %{entities: [%{label: "PER", start: -1, end: 5}]})
  end
end
