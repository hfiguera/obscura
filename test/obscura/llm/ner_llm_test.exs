defmodule Obscura.LLM.NERLLMTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.FakeServing

  test "LLM helpers pass explicit NER options through" do
    serving = FakeServing.new(%{"Alice" => [%{label: "PER", start: 0, end: 5, score: 0.9}]})

    assert {:ok, [%{content: "<<PERSON_001>>"}], vault} =
             Obscura.LLM.redact_messages([%{role: :user, content: "Alice"}],
               vault: :memory,
               entities: [:person],
               recognizers: [{NER, serving: serving}]
             )

    assert {:ok, "Alice"} = Obscura.LLM.rehydrate_response("<<PERSON_001>>", vault: vault)
  end
end
