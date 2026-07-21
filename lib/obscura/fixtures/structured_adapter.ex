defmodule Obscura.Fixtures.StructuredAdapter do
  @moduledoc """
  Fixture adapter for structured Phase 2 redaction.
  """

  @spec redact(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def redact(input, opts) when is_list(opts) do
    with {:ok, result} <- Obscura.Structured.redact(input, opts) do
      {:ok,
       %{
         data: result.data,
         items: Enum.map(result.items, &Map.from_struct/1),
         status: result.status
       }}
    end
  end
end
