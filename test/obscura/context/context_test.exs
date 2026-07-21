defmodule Obscura.ContextTest do
  use ExUnit.Case, async: true

  test "context boosts scores and records explanation metadata" do
    {:ok, [without_context]} =
      Obscura.analyze("Value 202-555-0188", entities: [:phone], explain: true)

    {:ok, [with_context]} =
      Obscura.analyze("Phone 202-555-0188",
        entities: [:phone],
        profile: :context,
        context: ["phone"],
        explain: true
      )

    assert with_context.score > without_context.score
    assert with_context.score <= 1.0
    assert "phone" in with_context.explanation.context_words
    assert with_context.explanation.score_context_delta > 0.0
  end

  test "whole-word context does not boost substring-only matches" do
    {:ok, [without_context]} =
      Obscura.analyze("Value 202-555-0188",
        entities: [:phone],
        profile: :context,
        context: ["one"],
        explain: true
      )

    {:ok, [with_context]} =
      Obscura.analyze("Phone 202-555-0188",
        entities: [:phone],
        profile: :context,
        context: ["phone"],
        explain: true
      )

    assert without_context.explanation.context_words == []
    assert with_context.score > without_context.score
  end

  test "context policies can reject weak spans unless supportive context appears" do
    policy = %{
      phone: %{
        context_words: ["phone"],
        require_context_below: 0.95,
        min_score: 0.95
      }
    }

    assert {:ok, []} =
             Obscura.analyze("Value 202-555-0188",
               entities: [:phone],
               profile: :context,
               context_policies: policy
             )

    assert {:ok, [phone]} =
             Obscura.analyze("Phone 202-555-0188",
               entities: [:phone],
               profile: :context,
               context_policies: policy
             )

    assert phone.score == 0.95
    assert phone.metadata.context_policy == :require_context_below
    assert phone.metadata.supportive_context_word == "phone"
  end
end
