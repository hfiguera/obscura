defmodule Obscura.Recognizer.NER.ConfigTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.Config

  test "TNER conservative defaults match the registry policy" do
    assert {:ok, opts} = Config.new(profile: :hybrid_ner_tner_conservative)

    assert opts[:per_label_thresholds] == %{
             "PERSON" => 0.72,
             "ORG" => 0.98,
             "GPE" => 0.9,
             "LOC" => 0.92,
             "FAC" => 0.97
           }

    assert opts[:context_required_below_labels] == %{
             "ORG" => 0.99,
             "LOC" => 0.96,
             "FAC" => 0.99
           }

    assert opts[:context_required_labels] == ["FAC"]
    assert opts[:weak_context_words_by_label] == %{"FAC" => ["in"]}
    assert "invoice" in opts[:negative_context_words_by_label]["GPE"]
    assert opts[:negative_context_reject_labels] == ["GPE"]
  end

  test "TNER high-recall defaults are opt-in and less strict for open labels" do
    assert {:ok, conservative} = Config.new(profile: :hybrid_ner_tner_conservative)
    assert {:ok, high_recall} = Config.new(profile: :hybrid_ner_tner_high_recall)

    assert high_recall[:per_label_thresholds]["ORG"] < conservative[:per_label_thresholds]["ORG"]
    assert high_recall[:per_label_thresholds]["GPE"] < conservative[:per_label_thresholds]["GPE"]
    assert high_recall[:per_label_thresholds]["FAC"] < conservative[:per_label_thresholds]["FAC"]

    assert high_recall[:context_required_below_labels]["FAC"] <
             conservative[:context_required_below_labels]["FAC"]

    assert conservative[:context_required_labels] == ["FAC"]
    assert high_recall[:context_required_labels] == []
  end

  test "model chunking is opt-in and validates chunk size and overlap" do
    assert {:ok, defaults} = Config.new([])
    assert defaults[:model_chunking] == :none
    assert defaults[:model_chunk_size] == 400
    assert defaults[:model_chunk_overlap] == 40

    assert {:ok, chunked} =
             Config.new(
               model_chunking: :character,
               model_chunk_size: 120,
               model_chunk_overlap: 24
             )

    assert chunked[:model_chunking] == :character
    assert chunked[:model_chunk_size] == 120
    assert chunked[:model_chunk_overlap] == 24

    assert {:error, :invalid_model_chunking} = Config.new(model_chunking: :tokens)

    assert {:error, :invalid_model_chunk_overlap} =
             Config.new(model_chunking: :character, model_chunk_size: 10, model_chunk_overlap: 10)
  end
end
