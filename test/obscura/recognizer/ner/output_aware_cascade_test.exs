defmodule Obscura.Recognizer.NER.OutputAwareCascadeTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.FakeServing
  alias Obscura.Recognizer.NER.OutputAwareCascade

  @text "Alice works at Acme in Denver."

  test "runs the location specialist when TNER has no accepted location" do
    ref = make_ref()

    assert {:ok, results} =
             OutputAwareCascade.analyze(
               @text,
               cascade_opts(
                 primary_outputs: [output("PERSON", 0, 5, 0.99), output("ORG", 15, 19, 0.99)],
                 secondary_outputs: [output("LOC", 23, 29, 0.999)],
                 cascade_observer: {self(), ref}
               )
             )

    assert Enum.map(results, &{&1.entity, &1.text}) == [
             {:person, "Alice"},
             {:organization, "Acme"},
             {:location, "Denver"}
           ]

    assert_receive {:ner_output_aware_cascade, ^ref,
                    %{
                      secondary_run: true,
                      trigger_reason: :missing,
                      secondary_proposed_count: 1,
                      secondary_accepted_count: 1
                    }}
  end

  test "skips the location specialist when TNER already has a location" do
    ref = make_ref()

    assert {:ok, results} =
             OutputAwareCascade.analyze(
               @text,
               cascade_opts(
                 primary_outputs: [output("GPE", 23, 29, 0.99)],
                 secondary_outputs: [output("LOC", 23, 29, 0.999)],
                 cascade_observer: {self(), ref}
               )
             )

    assert [%{entity: :location, text: "Denver", metadata: metadata}] = results
    assert metadata.cascade_role == :primary

    assert_receive {:ner_output_aware_cascade, ^ref,
                    %{secondary_run: false, trigger_reason: :primary_location}}
  end

  test "uncertainty trigger runs Jean and deduplicates identical spans" do
    assert {:ok, [location]} =
             OutputAwareCascade.analyze(
               @text,
               cascade_opts(
                 primary_outputs: [output("GPE", 23, 29, 0.93)],
                 secondary_outputs: [output("LOC", 23, 29, 0.999)],
                 cascade_trigger: :missing_or_uncertain,
                 cascade_uncertainty_threshold: 0.97,
                 cascade_context_policy: :strong_or_overlap
               )
             )

    assert location.entity == :location
    assert location.score == 0.999
    assert location.metadata.cascade_role == :secondary
  end

  test "strong context policy rejects unsupported secondary guesses" do
    assert {:ok, []} =
             OutputAwareCascade.analyze(
               "The reference is Mercury.",
               cascade_opts(
                 secondary_outputs: [output("LOC", 17, 24, 0.999)],
                 cascade_context_policy: :strong
               )
             )
  end

  test "rejects malformed cascade configuration" do
    assert {:error, {:invalid_cascade_option, :primary_opts}} =
             OutputAwareCascade.analyze(@text, [])
  end

  defp cascade_opts(overrides) do
    primary_outputs = Keyword.get(overrides, :primary_outputs, [])
    secondary_outputs = Keyword.get(overrides, :secondary_outputs, [])

    defaults = [
      primary_opts: [
        serving: FakeServing.new(primary_outputs),
        label_map: :tner_roberta_large_ontonotes5,
        entities: [:person, :organization, :location],
        per_label_thresholds: %{}
      ],
      secondary_opts: [
        serving: FakeServing.new(secondary_outputs),
        label_map: :jean_baptiste_roberta_large_ner_english,
        entities: [:location],
        per_label_thresholds: %{}
      ],
      cascade_trigger: :missing,
      cascade_context_policy: :none
    ]

    overrides = Keyword.drop(overrides, [:primary_outputs, :secondary_outputs])
    Keyword.merge(defaults, overrides)
  end

  defp output(label, start, finish, score),
    do: %{label: label, start: start, end: finish, score: score}
end
