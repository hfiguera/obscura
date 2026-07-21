defmodule Obscura.Analyzer.Explanation do
  @moduledoc """
  Basic recognizer explanation for deterministic decisions.
  """

  @enforce_keys [:recognizer, :pattern, :score]
  defstruct [
    :recognizer,
    :pattern,
    :score,
    :original_score,
    :validation,
    context_words: [],
    score_context_delta: 0.0,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          recognizer: atom(),
          pattern: atom(),
          score: float(),
          original_score: float() | nil,
          validation: atom() | nil,
          context_words: [String.t()],
          score_context_delta: float(),
          metadata: map()
        }
end

defimpl Inspect, for: Obscura.Analyzer.Explanation do
  import Inspect.Algebra

  def inspect(explanation, opts) do
    safe = %{
      context_word_count: length(explanation.context_words),
      original_score: explanation.original_score,
      recognizer: explanation.recognizer,
      score: explanation.score,
      score_context_delta: explanation.score_context_delta,
      validation: explanation.validation
    }

    concat(["#Obscura.Analyzer.Explanation<", to_doc(safe, opts), ">"])
  end
end
