defmodule Obscura.Fixtures.RealModelAdapter do
  @moduledoc """
  Adapter for opt-in real local model fixture runs.
  """

  alias Obscura.Eval.Offset
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.Serving

  @doc """
  Runs a fixture through a real local NER model serving.
  """
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(fixture, opts \\ []) when is_map(fixture) and is_list(opts) do
    with {:ok, serving} <- Serving.build(opts),
         {:ok, results} <-
           Obscura.analyze(fixture.text,
             entities: fixture.entities,
             profile: :real_ner,
             recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
             include_text: false,
             conflict_strategy: :none,
             telemetry: Keyword.get(opts, :telemetry, false)
           ) do
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
      source_entity: result.source_entity,
      score: result.score,
      metadata: Map.drop(result.metadata, [:text, :value, :phrase])
    }
  end
end
