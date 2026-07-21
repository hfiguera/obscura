defmodule Obscura.Anonymizer.Item do
  @moduledoc """
  Metadata for one anonymization replacement.
  """

  @enforce_keys [
    :entity,
    :operator,
    :source_byte_start,
    :source_byte_end,
    :replacement_byte_start,
    :replacement_byte_end,
    :replacement
  ]
  defstruct [
    :entity,
    :operator,
    :source_byte_start,
    :source_byte_end,
    :replacement_byte_start,
    :replacement_byte_end,
    :replacement,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          entity: atom(),
          operator: atom(),
          source_byte_start: non_neg_integer(),
          source_byte_end: non_neg_integer(),
          replacement_byte_start: non_neg_integer(),
          replacement_byte_end: non_neg_integer(),
          replacement: String.t(),
          metadata: map()
        }
end

defimpl Inspect, for: Obscura.Anonymizer.Item do
  import Inspect.Algebra

  def inspect(item, opts) do
    safe = %{
      entity: item.entity,
      operator: item.operator,
      replacement: :redacted,
      replacement_byte_end: item.replacement_byte_end,
      replacement_byte_start: item.replacement_byte_start,
      source_byte_end: item.source_byte_end,
      source_byte_start: item.source_byte_start
    }

    concat(["#Obscura.Anonymizer.Item<", to_doc(safe, opts), ">"])
  end
end
