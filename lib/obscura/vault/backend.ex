defmodule Obscura.Vault.Backend do
  @moduledoc """
  Behaviour for optional vault backends.

  Obscura ships memory and ETS backends. Applications can use this behaviour
  as the contract for persistent backends without making Ecto or another
  storage dependency mandatory for Obscura.
  """

  @type vault_ref :: GenServer.server()

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback init(keyword()) :: {:ok, term()} | {:stop, term()}
  @callback handle_call(term(), GenServer.from(), term()) ::
              {:reply, term(), term()} | {:reply, term(), term(), timeout() | :hibernate}
end
