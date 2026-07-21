defmodule Obscura.ContextWeakGateTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Options
  alias Obscura.Analyzer.Result
  alias Obscura.Context

  test "weak context words do not satisfy required context gates" do
    result = %Result{
      entity: :location,
      start: 17,
      end: 24,
      byte_start: 17,
      byte_end: 24,
      score: 0.9,
      recognizer: :ner,
      metadata: %{
        requires_context: true,
        context_words: ["in"],
        weak_context_words: ["in"]
      }
    }

    assert {:ok, options} =
             Options.new(
               profile: :hybrid_ner_tner_conservative,
               context_boost: 0.15,
               context_min_score: 0.4
             )

    [enhanced] = Context.enhance([result], "Alice was seen in Central.", options)

    assert enhanced.metadata.weak_context_matched == true
    assert enhanced.metadata.context_strength == :weak
    refute Map.get(enhanced.metadata, :context_matched)
    refute Context.accepted?(enhanced)
  end

  test "strong context words satisfy required context gates" do
    result = %Result{
      entity: :location,
      start: 17,
      end: 25,
      byte_start: 17,
      byte_end: 25,
      score: 0.9,
      recognizer: :ner,
      metadata: %{
        requires_context: true,
        context_words: ["hospital"],
        weak_context_words: ["in"]
      }
    }

    assert {:ok, options} =
             Options.new(
               profile: :hybrid_ner_tner_conservative,
               context_boost: 0.15,
               context_min_score: 0.4
             )

    [enhanced] = Context.enhance([result], "Alice was seen near Central hospital.", options)

    assert enhanced.metadata.context_matched == true
    assert enhanced.metadata.context_strength == :strong
    assert Context.accepted?(enhanced)
  end

  test "negative context words reject configured model labels" do
    result = %Result{
      entity: :location,
      start: 18,
      end: 23,
      byte_start: 18,
      byte_end: 23,
      score: 0.95,
      recognizer: :ner,
      metadata: %{
        requires_context: true,
        context_words: ["city"],
        negative_context_words: ["invoice"],
        negative_context_reject: true
      }
    }

    assert {:ok, options} =
             Options.new(
               profile: :hybrid_ner_tner_conservative,
               context_boost: 0.15,
               context_min_score: 0.4
             )

    [enhanced] = Context.enhance([result], "The invoice lists Paris today.", options)

    assert enhanced.metadata.negative_context_matched == true
    assert enhanced.metadata.negative_context_words == ["invoice"]
    assert enhanced.metadata.context_strength == :negative
    refute Context.accepted?(enhanced)
  end
end
