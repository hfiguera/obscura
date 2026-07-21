defmodule Obscura.Fixtures.NLPAdapter do
  @moduledoc """
  Fixture adapter for Phase 4 NLP fixtures.
  """

  alias Obscura.Fixtures.NERAdapter

  @doc """
  Runs an NLP fixture with the deterministic fake NER serving.
  """
  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(fixture), do: NERAdapter.run(fixture)
end
