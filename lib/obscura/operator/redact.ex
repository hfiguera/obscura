defmodule Obscura.Operator.Redact do
  @moduledoc false

  alias Obscura.Anonymizer.Error

  @allowed_options [:type]

  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(config) when is_map(config) do
    case Map.keys(config) -- @allowed_options do
      [] ->
        :ok

      _unknown ->
        {:error,
         Error.new(:unknown_operator_option,
           operator: :redact,
           metadata: %{allowed_options: @allowed_options}
         )}
    end
  end

  def validate(_config),
    do: {:error, Error.new(:invalid_operator_config, operator: :redact)}

  @spec apply(String.t(), map()) :: {:ok, String.t(), map()} | {:error, Error.t()}
  def apply(value, config) when is_binary(value) and is_map(config) do
    with :ok <- validate(config), do: {:ok, "", %{}}
  end

  def apply(_value, _config),
    do:
      {:error,
       Error.new(:invalid_operator_option,
         operator: :redact,
         field: :source,
         reason: :expected_binary
       )}
end
