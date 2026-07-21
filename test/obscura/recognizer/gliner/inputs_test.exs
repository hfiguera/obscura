defmodule Obscura.Recognizer.GLiNER.InputsTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Inputs
  alias Obscura.Recognizer.GLiNER.TokenSplitter

  test "builds prompt text in GLiNER label order format" do
    assert Inputs.prompt_text(["person", "phone number"]) ==
             "<<ENT>> person <<ENT>> phone number <<SEP>>"
  end

  test "builds compact prompts for tokenizers which preserve separator whitespace" do
    assert Inputs.prompt_text(["person", "organization"], "") ==
             "<<ENT>>person<<ENT>>organization<<SEP>>"
  end

  test "builds model text from split tokens so punctuation is encoded as its own word" do
    tokens = TokenSplitter.split("Rachel works in Paris.")

    assert Inputs.model_text(tokens) == "Rachel works in Paris ."
  end

  test "limits model words to the checkpoint maximum length" do
    tokens = TokenSplitter.split("one two three four")

    assert Enum.map(Inputs.limit_tokens(tokens, 3), & &1.text) == ["one", "two", "three"]
  end

  test "builds inclusive span indexes and masks" do
    assert Inputs.span_indexes(3, 2) ==
             {[[0, 0], [0, 1], [1, 1], [1, 2], [2, 2], [2, 3]],
              [true, true, true, true, true, false]}
  end

  test "reconstructs first-subword words mask from byte offsets" do
    text = "Rachel Green"
    tokens = TokenSplitter.split(text)
    text_offset = 20

    offsets = [
      {0, 0},
      {20, 26},
      {26, 26},
      {27, 32},
      {28, 32}
    ]

    assert Inputs.words_mask(offsets, tokens, text_offset) == [0, 1, 0, 2, 0]
  end

  test "assigns a standalone tokenizer word-prefix token to following punctuation" do
    tokens = TokenSplitter.split("München .")

    offsets = [
      {0, 8},
      {8, 9},
      {9, 10}
    ]

    assert Inputs.words_mask(offsets, tokens, 0) == [1, 2, 0]
  end

  test "assigns a leading standalone tokenizer word-prefix token to the first word" do
    tokens = TokenSplitter.split("李 雷")

    offsets = [
      {-1, 0},
      {0, 3},
      {3, 4},
      {4, 7}
    ]

    assert Inputs.words_mask(offsets, tokens, 0) == [1, 0, 2, 0]
  end
end
