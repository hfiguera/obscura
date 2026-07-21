defmodule Obscura.Vault.Entry do
  @moduledoc """
  One reversible pseudonymization mapping.
  """

  @enforce_keys [:entity, :token, :created_at]
  defstruct [
    :entity,
    :token,
    :created_at,
    :last_used_at,
    use_count: 0,
    metadata: %{},
    value: nil
  ]

  @type t :: %__MODULE__{
          entity: atom(),
          token: String.t(),
          created_at: integer(),
          last_used_at: integer() | nil,
          use_count: non_neg_integer(),
          metadata: map(),
          value: String.t() | nil
        }
end

defimpl Inspect, for: Obscura.Vault.Entry do
  import Inspect.Algebra

  def inspect(entry, opts) do
    data = %{
      created_at: entry.created_at,
      entity: entry.entity,
      last_used_at: entry.last_used_at,
      token: :redacted,
      use_count: entry.use_count,
      value: :redacted
    }

    concat(["#Obscura.Vault.Entry<", to_doc(data, opts), ">"])
  end
end
