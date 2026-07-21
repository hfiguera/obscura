defmodule Obscura.Fixtures.PlaceholderAnalyzer do
  @moduledoc """
  Placeholder analyzer adapter for Phase 0.

  It intentionally returns no predictions so the harness can report measurable
  false negatives before real recognizers exist.
  """

  @spec analyze(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def analyze(text, _opts) when is_binary(text), do: {:ok, []}
end
