defmodule Obscura.Anonymizer.Result do
  @moduledoc """
  Result of an anonymization run.

  Documented fields are stable in `0.1.x`; metadata keys are additive.
  """

  alias Obscura.Anonymizer.Item

  @enforce_keys [:text, :items, :status]
  defstruct [:text, :items, :status, metadata: %{}]

  @type t :: %__MODULE__{
          text: String.t(),
          items: [Item.t()],
          status: atom(),
          metadata: map()
        }
end

defimpl Inspect, for: Obscura.Anonymizer.Result do
  import Inspect.Algebra

  def inspect(result, opts) do
    safe = %{
      item_count: length(result.items),
      output_bytes: byte_size(result.text),
      status: result.status,
      text: :redacted
    }

    concat(["#Obscura.Anonymizer.Result<", to_doc(safe, opts), ">"])
  end
end
