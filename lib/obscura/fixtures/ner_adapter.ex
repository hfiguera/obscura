defmodule Obscura.Fixtures.NERAdapter do
  @moduledoc """
  Fixture adapter for Phase 4 fake-serving NER fixtures.
  """

  alias Obscura.Eval.Offset
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.FakeServing

  @doc """
  Runs a NER fixture through Obscura's analyzer.
  """
  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(fixture) when is_map(fixture) do
    serving = FakeServing.new(%{fixture.text => fixture.model_outputs})

    opts = [
      entities: fixture.entities,
      profile: fixture.profile,
      language: fixture.language,
      recognizers: [{NER, serving: serving}],
      include_text: true,
      conflict_strategy: :none,
      explain: true
    ]

    with {:ok, results} <- Obscura.analyze(fixture.text, opts) do
      {:ok, %{predicted: Enum.map(results, &to_fixture_span(fixture.text, &1))}}
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
      metadata: Map.drop(result.metadata, [:text, :value])
    }
  end
end
