defmodule Obscura.Recognizer.NER.SecondaryTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.FakeServing
  alias Obscura.Recognizer.NER.LocationGate
  alias Obscura.Recognizer.NER.Secondary

  test "analyze skips the secondary model when the gate does not pass" do
    serving =
      FakeServing.new(%{
        "Alice emailed Bob." => [%{label: "LOC", start: 0, end: 5, score: 0.99}]
      })

    assert {:ok, []} =
             Secondary.analyze("Alice emailed Bob.",
               serving: serving,
               entities: [:location],
               secondary_gate: {LocationGate, :run?}
             )
  end

  test "analyze runs the secondary model when the gate passes" do
    text = "Alice lives in Denver."

    serving =
      FakeServing.new(%{
        text => [%{label: "LOC", start: 15, end: 21, score: 0.99}]
      })

    assert {:ok, [%{entity: :location, text: "Denver"}]} =
             Secondary.analyze(text,
               serving: serving,
               entities: [:location],
               secondary_gate: {LocationGate, :run?}
             )
  end

  test "analyze_many preserves original order while skipping gated-out texts" do
    texts = ["Alice lives in Denver.", "Bob emailed Carol.", "Dana works in Paris."]

    serving =
      FakeServing.new(%{
        "Alice lives in Denver." => [%{label: "LOC", start: 15, end: 21, score: 0.99}],
        "Dana works in Paris." => [%{label: "LOC", start: 14, end: 19, score: 0.99}]
      })

    assert {:ok, [[denver], [], [paris]]} =
             Secondary.analyze_many(texts,
               serving: serving,
               entities: [:location],
               secondary_gate: {LocationGate, :run?}
             )

    assert denver.text == "Denver"
    assert paris.text == "Paris"
  end
end
