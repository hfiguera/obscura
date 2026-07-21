defmodule Obscura.Operator.Mask do
  @moduledoc false

  alias Obscura.Anonymizer.Error

  @allowed_options [:type, :char, :keep_last]

  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(config) when is_map(config) do
    with :ok <- validate_options(config),
         :ok <- validate_char(Map.get(config, :char, "*")) do
      validate_keep_last(Map.get(config, :keep_last, 0))
    end
  end

  def validate(_config), do: {:error, Error.new(:invalid_operator_config, operator: :mask)}

  @spec apply(String.t(), map()) :: {:ok, String.t(), map()} | {:error, Error.t()}
  def apply(value, config) when is_binary(value) and is_map(config) do
    with :ok <- validate(config),
         :ok <- validate_source(value) do
      char = Map.get(config, :char, "*")
      keep_last = Map.get(config, :keep_last, 0)
      graphemes = String.graphemes(value)
      masked_length = max(length(graphemes) - keep_last, 0)
      kept = graphemes |> Enum.drop(masked_length) |> Enum.join()

      {:ok, String.duplicate(char, masked_length) <> kept, %{}}
    end
  end

  def apply(_value, _config),
    do:
      {:error,
       Error.new(:invalid_operator_option,
         operator: :mask,
         field: :source,
         reason: :expected_binary
       )}

  defp validate_options(config) do
    case Map.keys(config) -- @allowed_options do
      [] ->
        :ok

      _unknown ->
        {:error,
         Error.new(:unknown_operator_option,
           operator: :mask,
           metadata: %{allowed_options: @allowed_options}
         )}
    end
  end

  defp validate_char(char) when is_binary(char) do
    if String.valid?(char) and match?([_grapheme], String.graphemes(char)) do
      :ok
    else
      invalid_char_error()
    end
  end

  defp validate_char(_char), do: invalid_char_error()

  defp validate_keep_last(keep_last) when is_integer(keep_last) and keep_last >= 0, do: :ok

  defp validate_keep_last(_keep_last) do
    {:error,
     Error.new(:invalid_operator_option,
       operator: :mask,
       field: :keep_last,
       reason: :expected_non_negative_integer
     )}
  end

  defp validate_source(value) do
    if String.valid?(value) do
      :ok
    else
      {:error,
       Error.new(:invalid_operator_option,
         operator: :mask,
         field: :source,
         reason: :expected_utf8_string
       )}
    end
  end

  defp invalid_char_error do
    {:error,
     Error.new(:invalid_operator_option,
       operator: :mask,
       field: :char,
       reason: :expected_single_grapheme
     )}
  end
end
