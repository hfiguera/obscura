defprotocol Obscura.Redactable do
  @moduledoc """
  Protocol for application data that can define its own Obscura redaction policy.
  """

  @fallback_to_any true

  @spec redact(t(), keyword()) :: {:ok, term(), [Obscura.Structured.Item.t()]} | {:error, term()}
  def redact(value, opts)
end

defimpl Obscura.Redactable, for: BitString do
  def redact(value, opts) do
    path = Keyword.get(opts, :path, [])

    with {:ok, result} <- Obscura.Structured.redact(value, opts) do
      {:ok, result.data, Enum.map(result.items, &%{&1 | path: path ++ &1.path})}
    end
  end
end

defimpl Obscura.Redactable, for: Map do
  def redact(value, opts) do
    with {:ok, result} <- Obscura.Structured.redact(value, opts) do
      {:ok, result.data, result.items}
    end
  end
end

defimpl Obscura.Redactable, for: List do
  def redact(value, opts) do
    with {:ok, result} <- Obscura.Structured.redact(value, opts) do
      {:ok, result.data, result.items}
    end
  end
end

defimpl Obscura.Redactable, for: Any do
  def redact(value, _opts), do: {:ok, value, []}

  defmacro __deriving__(module, _struct, opts) do
    quote do
      defimpl Obscura.Redactable, for: unquote(module) do
        def redact(value, opts) do
          Obscura.Structured.redact_derived(value, unquote(Macro.escape(opts)), opts)
        end
      end
    end
  end
end
