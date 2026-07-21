defmodule Obscura.Fixtures.ObscuraAnalyzerAdapter do
  @moduledoc """
  Fixture adapter backed by the real Phase 1 analyzer.
  """

  alias Obscura.Eval.Offset

  @spec analyze(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    opts =
      opts
      |> Keyword.put_new(:include_text, true)
      |> Keyword.put_new(:conflict_strategy, :none)

    with {:ok, results} <- Obscura.analyze(text, opts) do
      {:ok, Enum.map(results, &to_fixture_span(text, &1))}
    end
  end

  defp to_fixture_span(text, result) do
    {:ok, char_start} = Offset.byte_to_char(text, result.byte_start)
    {:ok, char_end} = Offset.byte_to_char(text, result.byte_end)

    %{
      entity: result.entity,
      byte_start: result.byte_start,
      byte_end: result.byte_end,
      char_start: char_start,
      char_end: char_end,
      value: result.text,
      source_entity: result.source_entity,
      score: result.score,
      metadata: result.metadata
    }
  end
end
