defmodule Obscura.Fixtures.PlaceholderOperator do
  @moduledoc """
  Placeholder operator adapter for Phase 0.

  It does not implement real anonymization. Returning the input unchanged keeps
  the runner executable while reports clearly identify placeholder behavior.
  """

  @spec anonymize(String.t(), [map()], map(), keyword()) :: {:ok, map()} | {:error, term()}
  def anonymize(text, spans, _operators, _opts) when is_binary(text) and is_list(spans) do
    {:ok, %{text: text, items: [], status: :unsupported}}
  end
end
