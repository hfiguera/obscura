defmodule Obscura.Anonymizer.Error do
  @moduledoc """
  Structured, value-safe anonymizer operator error.

  Errors contain stable machine-readable fields and never include source text,
  replacement values, salts, callback return values, or exception messages.
  Codes and fields are stable in `0.1.x`; rendered messages are not.
  """

  @enforce_keys [:code]
  defexception [:code, :operator, :field, :reason, metadata: %{}]

  @type code ::
          :invalid_operator_collection
          | :invalid_operator_config
          | :unsupported_operator
          | :unknown_operator_option
          | :missing_operator_option
          | :invalid_operator_option
          | :operator_failed
          | :invalid_operator_result

  @type t :: %__MODULE__{
          code: code(),
          operator: atom() | nil,
          field: atom() | nil,
          reason: atom() | nil,
          metadata: map()
        }

  @doc false
  @spec new(code(), keyword()) :: t()
  def new(code, opts \\ []) when is_atom(code) and is_list(opts) do
    %__MODULE__{
      code: code,
      operator: safe_atom(Keyword.get(opts, :operator)),
      field: safe_atom(Keyword.get(opts, :field)),
      reason: safe_atom(Keyword.get(opts, :reason)),
      metadata: safe_metadata(Keyword.get(opts, :metadata, %{}))
    }
  end

  @impl Exception
  def message(%__MODULE__{} = error) do
    [
      "anonymizer operator error",
      "code=#{error.code}",
      optional_part("operator", error.operator),
      optional_part("field", error.field),
      optional_part("reason", error.reason)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp optional_part(_name, nil), do: nil
  defp optional_part(name, value), do: "#{name}=#{value}"

  defp safe_atom(value) when is_atom(value), do: value
  defp safe_atom(_value), do: nil

  defp safe_metadata(metadata) when is_map(metadata) do
    Map.take(metadata, [:allowed_options, :minimum_bytes, :version])
  end

  defp safe_metadata(_metadata), do: %{}
end
