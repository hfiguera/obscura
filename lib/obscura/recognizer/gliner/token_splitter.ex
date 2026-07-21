defmodule Obscura.Recognizer.GLiNER.TokenSplitter do
  @moduledoc """
  GLiNER-compatible token splitting with byte offsets.
  """

  # Python's Unicode `\w` excludes combining marks, while PCRE2's includes them.
  @python_word ~S"[\p{L}\p{N}_]"
  @token_pattern Regex.compile!("#{@python_word}+(?:[-_]#{@python_word}+)*|\\S", "u")

  @type token :: %{text: String.t(), start: non_neg_integer(), end: non_neg_integer()}

  @doc """
  Splits text using GLiNER's whitespace splitter pattern.
  """
  @spec split(String.t()) :: [token()]
  def split(text) when is_binary(text) do
    @token_pattern
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{start, byte_length}] ->
      value = binary_part(text, start, byte_length)
      %{text: value, start: start, end: start + byte_length}
    end)
  end
end
