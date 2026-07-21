defmodule Obscura.Fixtures.ObscuraOperatorAdapter do
  @moduledoc """
  Fixture adapter backed by the real Obscura anonymizer.
  """

  @spec anonymize(String.t(), [map()], map(), keyword()) :: {:ok, map()} | {:error, term()}
  def anonymize(text, spans, operators, opts)
      when is_binary(text) and is_list(spans) and is_map(operators) and is_list(opts) do
    anonymize_opts =
      opts
      |> Keyword.put(:operators, operators)
      |> Keyword.put_new(:merge_whitespace, Map.get(operators, :merge_whitespace, false))

    case Obscura.anonymize(text, spans, anonymize_opts) do
      {:ok, result} ->
        {:ok,
         %{
           text: result.text,
           items: Enum.map(result.items, &Map.from_struct/1),
           status: result.status
         }}

      {:error, {:invalid_span, _reason} = reason} ->
        {:ok, %{text: text, items: [], status: :invalid_span, error: reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
