defmodule Obscura.Analyzer.Result do
  @moduledoc """
  Normalized analyzer result.

  `start` and `end` are byte offsets. `byte_start` and `byte_end` are retained
  for fixture and benchmark interoperability. Documented fields are stable in
  `0.1.x`; metadata keys are additive unless documented separately.
  """

  alias Obscura.Analyzer.Explanation

  @enforce_keys [:entity, :start, :end, :byte_start, :byte_end, :score]
  defstruct [
    :entity,
    :start,
    :end,
    :byte_start,
    :byte_end,
    :score,
    :text,
    :source_entity,
    :recognizer,
    :explanation,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          entity: atom(),
          start: non_neg_integer(),
          end: non_neg_integer(),
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          score: float(),
          text: String.t() | nil,
          source_entity: String.t() | nil,
          recognizer: atom() | nil,
          explanation: Explanation.t() | nil,
          metadata: map()
        }
end

defimpl Inspect, for: Obscura.Analyzer.Result do
  import Inspect.Algebra

  def inspect(result, opts) do
    safe = %{
      byte_end: result.byte_end,
      byte_start: result.byte_start,
      entity: result.entity,
      recognizer: result.recognizer,
      score: result.score,
      text: :redacted
    }

    concat(["#Obscura.Analyzer.Result<", to_doc(safe, opts), ">"])
  end
end
