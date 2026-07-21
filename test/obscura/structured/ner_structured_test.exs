defmodule Obscura.Structured.NERStructuredTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.FakeServing

  test "structured redaction can use explicit NER configuration" do
    serving = FakeServing.new(%{"Alice" => [%{label: "PER", start: 0, end: 5, score: 0.9}]})

    assert {:ok, result} =
             Obscura.redact(%{name: "Alice"},
               entities: [:person],
               recognizers: [{NER, serving: serving}],
               operators: %{person: %{type: :replace, value: "[PERSON]"}}
             )

    assert result.data == %{name: "[PERSON]"}
  end
end
