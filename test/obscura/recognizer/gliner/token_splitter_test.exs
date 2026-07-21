defmodule Obscura.Recognizer.GLiNER.TokenSplitterTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.TokenSplitter

  test "splits words, punctuation, email-like text, and phone punctuation with byte offsets" do
    text = "Rachel_Green emailed rachel@example.com at +1-555-0100."

    assert [
             %{text: "Rachel_Green", start: 0, end: 12},
             %{text: "emailed"},
             %{text: "rachel"},
             %{text: "@"},
             %{text: "example"},
             %{text: "."},
             %{text: "com"},
             %{text: "at"},
             %{text: "+"},
             %{text: "1-555-0100"},
             %{text: "."}
           ] = TokenSplitter.split(text)
  end

  test "keeps non-ascii byte offsets" do
    text = "Ana lives in São Paulo."

    assert Enum.find(TokenSplitter.split(text), &(&1.text == "São")) == %{
             text: "São",
             start: 13,
             end: 17
           }
  end

  test "matches Python whitespace splitting for decomposed Unicode marks" do
    assert [
             %{text: "Jose", start: 0, end: 4},
             %{text: "\u0301", start: 4, end: 6},
             %{text: "works", start: 7, end: 12}
           ] = TokenSplitter.split("Jose\u0301 works")
  end
end
