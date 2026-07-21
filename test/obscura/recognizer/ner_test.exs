defmodule Obscura.Recognizer.NERTest do
  use ExUnit.Case, async: true

  alias Obscura.NLP.Artifacts
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.FakeServing
  alias Obscura.Vault.Memory

  test "requires explicit serving configuration" do
    assert {:error, {:recognizer_failed, :ner, :missing_ner_serving}} =
             Obscura.analyze("Alice", entities: [:person], recognizers: [:ner])
  end

  test "detects open-class entities with fake serving" do
    text = "Alice works at Acme in Denver."

    serving =
      FakeServing.new(%{
        text => [
          %{label: "PER", start: 0, end: 5, score: 0.94},
          %{label: "ORG", start: 15, end: 19, score: 0.91},
          %{label: "LOC", start: 23, end: 29, score: 0.89}
        ]
      })

    assert {:ok, [person, organization, location]} =
             Obscura.analyze(text,
               entities: [:person, :organization, :location],
               recognizers: [{NER, serving: serving}],
               explain: true
             )

    assert person.entity == :person
    assert organization.entity == :organization
    assert location.entity == :location
    assert person.explanation.metadata.model_label == "PER"
  end

  test "maps nationality labels" do
    serving = FakeServing.new(%{"French" => [%{label: "NRP", start: 0, end: 6, score: 0.9}]})

    assert {:ok, [%{entity: :nationality, text: "French"}]} =
             Obscura.analyze("French",
               entities: [:nationality],
               recognizers: [{NER, serving: serving}]
             )
  end

  test "hybrid profile ignores organization labels by default" do
    text = "Alice works at Acme in Denver."

    serving =
      FakeServing.new(%{
        text => [
          %{label: "PER", start: 0, end: 5, score: 0.94},
          %{label: "ORG", start: 15, end: 19, score: 0.99},
          %{label: "LOC", start: 23, end: 29, score: 0.89}
        ]
      })

    assert {:ok, results} =
             Obscura.analyze(text,
               profile: :hybrid_ner,
               entities: [:person, :organization, :location],
               recognizers: [{NER, serving: serving}]
             )

    assert Enum.map(results, & &1.entity) == [:person, :location]
  end

  test "hybrid profile organization ignore list can be overridden explicitly" do
    text = "Alice works at Acme."

    serving =
      FakeServing.new(%{
        text => [
          %{label: "ORG", start: 15, end: 19, score: 0.99}
        ]
      })

    assert {:ok, [%{entity: :organization, text: "Acme"}]} =
             Obscura.analyze(text,
               profile: :hybrid_ner,
               entities: [:organization],
               recognizers: [{NER, serving: serving, labels_to_ignore: []}]
             )
  end

  test "uses precomputed model outputs from NLP artifacts without serving" do
    text = "Rachel works in Paris."

    {:ok, artifacts} =
      text
      |> Artifacts.build()
      |> Artifacts.put_model_outputs([
        %{label: "PER", start: 0, end: 6, score: 0.99},
        %{label: "LOC", start: 16, end: 21, score: 0.98}
      ])

    assert {:ok, [person, location]} =
             Obscura.analyze(text,
               entities: [:person, :location],
               recognizers: [NER],
               nlp_artifacts: artifacts
             )

    assert person.entity == :person
    assert location.entity == :location
  end

  test "treats ready empty artifact model outputs as no detections" do
    assert {:ok, artifacts} =
             "No entities here"
             |> Artifacts.build()
             |> Artifacts.put_model_outputs([])

    assert {:ok, []} =
             Obscura.analyze("No entities here",
               entities: [:person],
               recognizers: [NER],
               nlp_artifacts: artifacts
             )
  end

  test "org-enabled hybrid profile keeps organization labels with thresholding" do
    text = "Alice works at Acme."

    serving =
      FakeServing.new(%{
        text => [
          %{label: "ORG", start: 15, end: 19, score: 0.99}
        ]
      })

    assert {:ok, [%{entity: :organization, text: "Acme"}]} =
             Obscura.analyze(text,
               profile: :hybrid_ner_org,
               entities: [:organization],
               recognizers: [{NER, serving: serving}]
             )
  end

  test "org-enabled hybrid profile gates lower-score organization spans by context" do
    serving =
      FakeServing.new(%{
        "Alice mentioned Acme." => [
          %{label: "ORG", start: 16, end: 20, score: 0.9}
        ],
        "Alice works at Acme." => [
          %{label: "ORG", start: 15, end: 19, score: 0.9}
        ]
      })

    assert {:ok, []} =
             Obscura.analyze("Alice mentioned Acme.",
               profile: :hybrid_ner_org,
               entities: [:organization],
               recognizers: [{NER, serving: serving}]
             )

    assert {:ok, [%{entity: :organization, text: "Acme"} = organization]} =
             Obscura.analyze("Alice works at Acme.",
               profile: :hybrid_ner_org,
               entities: [:organization],
               recognizers: [{NER, serving: serving}]
             )

    assert organization.metadata.context_matched == true
    assert organization.metadata.supportive_context_word == "works at"
  end

  test "hybrid preset aliases expose conservative and balanced organization behavior" do
    text = "Alice works at Acme."

    serving =
      FakeServing.new(%{
        text => [
          %{label: "ORG", start: 15, end: 19, score: 0.9}
        ]
      })

    assert {:ok, []} =
             Obscura.analyze(text,
               profile: :hybrid_ner_conservative,
               entities: [:organization],
               recognizers: [{NER, serving: serving}]
             )

    assert {:ok, [%{entity: :organization, text: "Acme"}]} =
             Obscura.analyze(text,
               profile: :hybrid_ner_balanced,
               entities: [:organization],
               recognizers: [{NER, serving: serving}]
             )
  end

  test "returns explicit errors for unknown recognizer atoms" do
    assert {:error, {:unknown_recognizer, :unknown_ner}} =
             Obscura.analyze("Alice", entities: [:person], recognizers: [:unknown_ner])
  end

  test "analyze_many preserves input order" do
    serving =
      FakeServing.new(%{
        "Alice" => [%{label: "PER", start: 0, end: 5, score: 0.9}],
        "Denver" => [%{label: "LOC", start: 0, end: 6, score: 0.9}]
      })

    assert {:ok, [[person], [location]]} =
             Obscura.analyze_many(["Alice", "Denver"],
               entities: [:person, :location],
               recognizers: [{NER, serving: serving}]
             )

    assert person.entity == :person
    assert location.entity == :location
  end

  test "pseudonymizes NER detections through the existing vault operator" do
    assert {:ok, vault} = Memory.start_link()
    serving = FakeServing.new(%{"Alice" => [%{label: "PER", start: 0, end: 5, score: 0.9}]})

    assert {:ok, result} =
             Obscura.redact("Alice",
               entities: [:person],
               recognizers: [{NER, serving: serving}],
               operators: %{person: %{type: :pseudonymize}},
               vault: vault
             )

    assert result.text == "<<PERSON_001>>"
    assert {:ok, "Alice"} = Obscura.rehydrate(result.text, vault: vault)
  end
end
