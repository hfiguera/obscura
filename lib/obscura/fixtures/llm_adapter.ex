defmodule Obscura.Fixtures.LLMAdapter do
  @moduledoc """
  Runs Phase 3 LLM fixtures.
  """

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(fixture) when is_map(fixture) do
    opts = Keyword.put(fixture.opts, :vault, Keyword.get(fixture.opts, :vault_backend, :memory))

    with {:ok, messages, vault} <- Obscura.LLM.redact_messages(fixture.messages, opts),
         {:ok, response} <- Obscura.LLM.rehydrate_response(fixture.response, vault: vault) do
      {:ok, %{messages: messages, rehydrated_response: response, vault: vault}}
    end
  end
end
