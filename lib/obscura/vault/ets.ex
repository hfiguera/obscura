defmodule Obscura.Vault.ETS do
  @moduledoc """
  Session-scoped ETS-backed vault.
  """

  use GenServer

  alias Obscura.Vault.Common
  alias Obscura.Vault.Entry
  alias Obscura.Vault.Token

  @doc """
  Starts an ETS vault owner process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ [])

  def start_link(opts) when is_list(opts) do
    with :ok <- validate_table_option(opts) do
      Common.start_link(__MODULE__, opts, [:table])
    end
  end

  def start_link(_opts), do: {:error, :invalid_vault_options}

  @impl GenServer
  def init(opts) do
    token_options = Keyword.take(opts, Keyword.keys(Token.default_options()))

    with :ok <- validate_table_option(opts),
         :ok <- Token.validate_options(token_options) do
      {:ok,
       %{
         backend: :ets,
         by_value: :ets.new(:obscura_vault_by_value, [:set, :private]),
         by_token: :ets.new(:obscura_vault_by_token, [:set, :private]),
         counters: %{},
         token_options: token_options
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:get_or_create, entity, value, opts}, _from, state) do
    start = System.monotonic_time()

    {reply, next_state, created?} =
      case :ets.lookup(state.by_value, {entity, value}) do
        [{_key, entry}] ->
          entry = Common.touch(entry)
          put_entry(state, entry)
          {{:ok, entry.token}, state, false}

        [] ->
          case create_entry(state, entity, value, opts) do
            {:ok, entry, state} -> {{:ok, entry.token}, state, true}
            {:error, reason} -> {{:error, reason}, state, false}
          end
      end

    Common.emit_token_telemetry(:ets, start, entity, created?, reply)
    {:reply, reply, next_state}
  end

  def handle_call({:lookup_token, token, _opts}, _from, state) do
    start = System.monotonic_time()
    {reply, state} = lookup_by_token(state, token)
    Common.emit_lookup_telemetry(:ets, start, :token, reply)
    {:reply, reply, state}
  end

  def handle_call({:lookup_value, entity, value, _opts}, _from, state) do
    start = System.monotonic_time()
    {reply, state} = lookup_by_value(state, entity, value)
    Common.emit_lookup_telemetry(:ets, start, :value, reply)
    {:reply, reply, state}
  end

  def handle_call({:clear, _opts}, _from, state) do
    :ets.delete_all_objects(state.by_value)
    :ets.delete_all_objects(state.by_token)
    {:reply, :ok, %{state | counters: %{}}}
  end

  def handle_call(:info, _from, state) do
    {:reply, {:ok, %{backend: :ets, size: :ets.info(state.by_token, :size)}}, state}
  end

  defp create_entry(state, entity, value, opts) do
    counter = Map.get(state.counters, entity, 0) + 1
    token_options = Keyword.merge(state.token_options, opts)

    with {:ok, token} <- Token.format(entity, counter, token_options) do
      now = System.monotonic_time()

      entry = %Entry{
        entity: entity,
        value: value,
        token: token,
        created_at: now,
        last_used_at: now,
        use_count: 1
      }

      put_entry(state, entry)
      {:ok, entry, %{state | counters: Map.put(state.counters, entity, counter)}}
    end
  end

  defp lookup_by_token(state, token) do
    case :ets.lookup(state.by_token, token) do
      [{_token, entry}] ->
        entry = Common.touch(entry)
        put_entry(state, entry)
        {{:ok, entry}, state}

      [] ->
        {{:error, {:token_not_found, Common.token_shape(token)}}, state}
    end
  end

  defp lookup_by_value(state, entity, value) do
    case :ets.lookup(state.by_value, {entity, value}) do
      [{_key, entry}] ->
        entry = Common.touch(entry)
        put_entry(state, entry)
        {{:ok, entry}, state}

      [] ->
        {{:error, {:value_not_found, entity}}, state}
    end
  end

  defp put_entry(state, entry) do
    :ets.insert(state.by_value, {{entry.entity, entry.value}, entry})
    :ets.insert(state.by_token, {entry.token, entry})
  end

  defp validate_table_option(opts) do
    case Keyword.fetch(opts, :table) do
      :error -> :ok
      {:ok, table} when is_atom(table) -> :ok
      {:ok, _table} -> {:error, :invalid_vault_table}
    end
  end
end
