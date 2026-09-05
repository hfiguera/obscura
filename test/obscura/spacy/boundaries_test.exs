defmodule Obscura.Spacy.BoundariesTest do
  use ExUnit.Case, async: true
  alias Obscura.Spacy.Boundaries

  defp span(text, fragment, label) do
    {first, length} = :binary.match(text, fragment)
    %{"label" => label, "byte_start" => first, "byte_end" => first + length}
  end

  defp contents(text, spans) do
    Enum.map(spans, &binary_part(text, &1["byte_start"], &1["byte_end"] - &1["byte_start"]))
  end

  test "form boundaries retain Unicode bytes and exclude the following field" do
    text = "Name: José García\n- Date of Birth: 1990-01-01"
    found = Boundaries.normalize(text, [span(text, "José García\n- Date", "PERSON")])
    assert contents(text, found) == ["José García"]
  end

  test "address expansion requires an existing location and stops before another field" do
    text = "**Address:** 12 Cedar Road, London, Phone: 555-0100\nName: Dr. Alice Smith"

    found =
      Boundaries.normalize(text, [
        span(text, "London", "GPE"),
        span(text, "Alice Smith", "PERSON")
      ])

    assert contents(text, found) == ["12 Cedar Road, London", "Dr. Alice Smith"]
    assert Boundaries.normalize(text, []) == []
  end

  test "prose locations and initials keep their boundaries" do
    text = "J. R. Smith moved from London to Paris."

    inputs = [
      span(text, "J. R. Smith", "PERSON"),
      span(text, "London", "GPE"),
      span(text, "Paris", "GPE")
    ]

    assert Boundaries.normalize(text, inputs) == inputs
  end

  test "formatting removal never leaves an empty prediction" do
    text = "**Alice Smith**"

    assert contents(text, Boundaries.normalize(text, [span(text, text, "PERSON")])) == [
             "Alice Smith"
           ]

    only_formatting = span("***", "***", "PERSON")
    assert Boundaries.normalize("***", [only_formatting]) == [only_formatting]
  end
end
