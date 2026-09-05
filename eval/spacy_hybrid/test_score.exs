ExUnit.start()

defmodule Obscura.SpacyHybrid.ScoreTest do
  use ExUnit.Case, async: true
  alias Obscura.SpacyHybrid.{ImportedNER, Score}

  test "a spaCy span cannot replace a structured deterministic email" do
    text = "Reach Alice at alice@example.com."
    outputs = [%{label: "PERSON", start: 15, end: 20, score: 0.85, offset_unit: :byte}]

    {:ok, results} =
      Obscura.analyze(text,
        profile: :deterministic_plus,
        entities: [:email, :person],
        include_text: false,
        recognizers: [{ImportedNER, model_outputs: outputs}]
      )

    assert Enum.any?(
             results,
             &(&1.entity == :email and &1.byte_start == 15 and &1.byte_end == 32)
           )

    refute Enum.any?(results, &(&1.entity == :person and &1.byte_start == 15))
  end

  test "real model outputs participate in the actual analyzer with Unicode offsets" do
    text = "🙂 José"
    outputs = [%{label: "PERSON", start: 5, end: 10, score: 0.85, offset_unit: :byte}]

    {:ok, [result]} =
      Obscura.analyze(text,
        profile: :deterministic_plus,
        entities: [:person],
        include_text: false,
        built_ins: false,
        recognizers: [{ImportedNER, model_outputs: outputs}]
      )

    assert {result.entity, result.byte_start, result.byte_end} == {:person, 5, 10}
    assert result.metadata.model_label == "PERSON"
    assert is_nil(result.text)
  end

  test "span import rejects codepoint offsets passed as UTF-8 byte offsets" do
    prediction = %{
      "entity" => "person",
      "byte_start" => 2,
      "byte_end" => 6,
      "char_start" => 2,
      "char_end" => 6,
      "score" => 0.85
    }

    assert_raise MatchError, fn ->
      Score.validate_predictions!("🙂 José", [prediction], [:person])
    end

    valid = %{prediction | "byte_start" => 5, "byte_end" => 10}
    assert :ok == Score.validate_predictions!("🙂 José", [valid], [:person])
  end

  test "prediction imports reject reordered or duplicate sample IDs" do
    entry = %{"name" => "test", "selection_sha256" => "hash"}
    run = %{"mode" => "spacy_full", "repetition" => 1}
    artifact = Map.merge(entry, run) |> Map.put("dataset", "test")

    for ids <- [[2, 1], [1, 1]] do
      rows = Enum.map(ids, &%{"sample_id" => &1})

      assert_raise MatchError, fn ->
        Score.validate_artifact!(Map.put(artifact, "rows", rows), entry, run, [1, 2])
      end
    end
  end
end
