defmodule Obscura.Fixtures.VaultAdapter do
  @moduledoc """
  Runs Phase 3 vault fixtures.
  """

  alias Obscura.Vault
  alias Obscura.Vault.ETS
  alias Obscura.Vault.Memory

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(fixture) when is_map(fixture) do
    case start_vault(fixture.backend) do
      {:ok, vault} -> run_operations(vault, fixture.operations)
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_vault(:memory), do: Memory.start_link()
  defp start_vault(:ets), do: ETS.start_link()
  defp start_vault(backend), do: {:error, {:unsupported_vault_backend, backend}}

  defp run_operations(vault, operations) do
    Enum.reduce_while(operations, {:ok, %{tokens: [], rehydrated: nil, vault: vault}}, fn
      {:get_or_create, entity, value}, {:ok, acc} ->
        case Vault.get_or_create(vault, entity, value) do
          {:ok, token} -> {:cont, {:ok, %{acc | tokens: acc.tokens ++ [token]}}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {:rehydrate, text}, {:ok, acc} ->
        case Obscura.rehydrate(text, vault: vault) do
          {:ok, rehydrated} -> {:cont, {:ok, %{acc | rehydrated: rehydrated}}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end
end
