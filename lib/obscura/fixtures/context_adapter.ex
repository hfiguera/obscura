defmodule Obscura.Fixtures.ContextAdapter do
  @moduledoc """
  Fixture adapter for Phase 2 context enhancement checks.
  """

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(fixture) when is_map(fixture) do
    base_opts = [entities: fixture.entities, explain: true, context: [], profile: :regex_only]

    context_opts = [
      entities: fixture.entities,
      explain: true,
      context: fixture.expected_context_words,
      profile: :context
    ]

    with {:ok, without_context} <- Obscura.analyze(fixture.text_without_context, base_opts),
         {:ok, with_context} <- Obscura.analyze(fixture.text_with_context, context_opts) do
      {:ok,
       %{
         without_context: pick(without_context, fixture),
         with_context: pick(with_context, fixture),
         status: :ran
       }}
    end
  end

  defp pick(results, fixture) do
    Enum.find(results, fn result ->
      result.entity == fixture.expected_entity and result.text == fixture.expected_value
    end)
  end
end
