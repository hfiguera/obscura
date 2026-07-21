defmodule Obscura.Structured.Result do
  @moduledoc """
  Result of a structured redaction run.

  Documented fields are stable in `0.1.x`; metadata keys are additive.
  """

  alias Obscura.Structured.Item

  @enforce_keys [:data, :items, :status]
  defstruct [:data, :items, :status, metadata: %{}]

  @type t :: %__MODULE__{
          data: term(),
          items: [Item.t()],
          status: atom(),
          metadata: map()
        }
end

defimpl Inspect, for: Obscura.Structured.Result do
  import Inspect.Algebra

  def inspect(result, opts) do
    safe = %{data: :redacted, item_count: length(result.items), status: result.status}
    concat(["#Obscura.Structured.Result<", to_doc(safe, opts), ">"])
  end
end
