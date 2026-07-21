defmodule Obscura.Operator.Replace do
  @moduledoc false

  alias Obscura.Anonymizer.Error

  @allowed_options [:type, :value]

  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(config) when is_map(config) do
    with :ok <- validate_options(config), do: validate_value(config)
  end

  def validate(_config),
    do: {:error, Error.new(:invalid_operator_config, operator: :replace)}

  @spec apply(String.t(), map()) :: {:ok, String.t(), map()} | {:error, Error.t()}
  def apply(value, config) when is_binary(value) and is_map(config) do
    with :ok <- validate(config) do
      {:ok, Map.get(config, :value, "[REDACTED]"), %{}}
    end
  end

  def apply(_value, _config),
    do:
      {:error,
       Error.new(:invalid_operator_option,
         operator: :replace,
         field: :source,
         reason: :expected_binary
       )}

  defp validate_options(config) do
    case Map.keys(config) -- @allowed_options do
      [] -> :ok
      _unknown -> unknown_option_error()
    end
  end

  defp validate_value(config) do
    case Map.fetch(config, :value) do
      :error -> :ok
      {:ok, value} when is_binary(value) -> :ok
      {:ok, _value} -> invalid_value_error()
    end
  end

  defp unknown_option_error do
    {:error,
     Error.new(:unknown_operator_option,
       operator: :replace,
       metadata: %{allowed_options: @allowed_options}
     )}
  end

  defp invalid_value_error do
    {:error,
     Error.new(:invalid_operator_option,
       operator: :replace,
       field: :value,
       reason: :expected_binary
     )}
  end
end
