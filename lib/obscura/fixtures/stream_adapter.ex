defmodule Obscura.Fixtures.StreamAdapter do
  @moduledoc """
  Runs Phase 3 streaming rehydration fixtures.
  """

  alias Obscura.Stream.Rehydrator
  alias Obscura.Vault
  alias Obscura.Vault.Memory

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(fixture) when is_map(fixture) do
    with {:ok, vault} <- Memory.start_link(),
         :ok <- setup(vault, fixture.setup),
         {:ok, stream} <- Rehydrator.new(vault: vault),
         {:ok, chunks, stream} <- feed_chunks(stream, fixture.chunks),
         {:ok, rest} <- Rehydrator.flush(stream) do
      output = IO.iodata_to_binary(chunks ++ [rest])
      {:ok, %{chunks: chunks, output: output, vault: vault}}
    end
  end

  defp setup(vault, setup) do
    Enum.reduce_while(setup, :ok, fn
      {:get_or_create, entity, value}, :ok ->
        case Vault.get_or_create(vault, entity, value) do
          {:ok, _token} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp feed_chunks(stream, chunks) do
    Enum.reduce_while(chunks, {:ok, [], stream}, fn chunk, {:ok, acc, stream} ->
      case Rehydrator.feed(stream, chunk) do
        {:ok, ready, stream} -> {:cont, {:ok, acc ++ [ready], stream}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
