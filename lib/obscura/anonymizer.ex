defmodule Obscura.Anonymizer do
  @moduledoc """
  String anonymizer facade for validated operators.

  Operator configuration is validated before replacements begin. Invalid
  configuration returns `{:error, %Obscura.Anonymizer.Error{}}` without a
  partially anonymized result.
  """

  alias Obscura.Anonymizer.Engine

  @doc """
  Applies configured operators to analyzer results or fixture-compatible spans.
  """
  @spec anonymize(String.t(), [map() | struct()], keyword()) ::
          {:ok, Obscura.Anonymizer.Result.t()} | {:error, term()}
  def anonymize(text, spans, opts \\ []) when is_binary(text) and is_list(spans) do
    Engine.anonymize(text, spans, opts)
  end

  @doc false
  @spec validate_options(keyword()) :: {:ok, map()} | {:error, Obscura.Anonymizer.Error.t()}
  def validate_options(opts), do: Engine.validate_options(opts)
end
