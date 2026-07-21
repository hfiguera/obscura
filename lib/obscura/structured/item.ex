defmodule Obscura.Structured.Item do
  @moduledoc """
  Redaction metadata for one structured data leaf.
  """

  @enforce_keys [:path, :entity, :operator, :replacement]
  defstruct [
    :path,
    :entity,
    :operator,
    :source_byte_start,
    :source_byte_end,
    :replacement,
    metadata: %{}
  ]

  @type path :: [atom() | String.t() | integer()]
  @type t :: %__MODULE__{
          path: path(),
          entity: atom(),
          operator: atom(),
          source_byte_start: non_neg_integer() | nil,
          source_byte_end: non_neg_integer() | nil,
          replacement: String.t(),
          metadata: map()
        }
end

defimpl Inspect, for: Obscura.Structured.Item do
  import Inspect.Algebra

  def inspect(item, opts) do
    safe = %{
      entity: item.entity,
      operator: item.operator,
      path_depth: length(item.path),
      replacement: :redacted,
      source_byte_end: item.source_byte_end,
      source_byte_start: item.source_byte_start
    }

    concat(["#Obscura.Structured.Item<", to_doc(safe, opts), ">"])
  end
end
