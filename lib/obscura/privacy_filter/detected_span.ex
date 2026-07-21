defmodule Obscura.PrivacyFilter.DetectedSpan do
  @moduledoc """
  Internal span emitted by privacy-filter postprocessing.
  """

  @enforce_keys [:label, :start, :end, :byte_start, :byte_end, :text]
  defstruct [
    :label,
    :entity,
    :start,
    :end,
    :byte_start,
    :byte_end,
    :text,
    :placeholder,
    :score,
    :token_start,
    :token_end,
    metadata: %{}
  ]

  @type t :: %__MODULE__{}
end

defimpl Inspect, for: Obscura.PrivacyFilter.DetectedSpan do
  import Inspect.Algebra

  def inspect(span, opts) do
    safe = %{
      byte_end: span.byte_end,
      byte_start: span.byte_start,
      entity: span.entity,
      label: span.label,
      score: span.score,
      text: :redacted
    }

    concat(["#Obscura.PrivacyFilter.DetectedSpan<", to_doc(safe, opts), ">"])
  end
end
