defmodule Obscura.Vault.Memory do
  @moduledoc """
  Session-scoped in-memory vault.
  """

  use GenServer

  alias Obscura.Vault.Common
  alias Obscura.Vault.Entry
  alias Obscura.Vault.Token

  @doc """
  Starts a memory vault.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ [])

  def start_link(opts) when is_list(opts) do
    Common.start_link(__MODULE__, opts)
  end

  def start_link(_opts), do: {:error, :invalid_vault_options}

  @impl GenServer
  def init(opts) do
    token_options = Keyword.take(opts, Keyword.keys(Token.default_options()))

    case Token.validate_options(token_options) do
      :ok ->
        {:ok,
         %{
           backend: :memory,
           by_value: %{},
           by_token: %{},
           counters: %{},
           token_options: token_options
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:get_or_create, entity, value, opts}, _from, state) do
    start = System.monotonic_time()

    {reply, next_state, created?} =
      case Map.fetch(state.by_value, {entity, value}) do
        {:ok, entry} ->
          entry = Common.touch(entry)
          state = put_entry(state, entry)
          {{:ok, entry.token}, state, false}

        :error ->
          case create_entry(state, entity, value, opts) do
            {:ok, entry, state} -> {{:ok, entry.token}, state, true}
            {:error, reason} -> {{:error, reason}, state, false}
          end
      end

    Common.emit_token_telemetry(:memory, start, entity, created?, reply)
    {:reply, reply, next_state}
  end

  def handle_call({:lookup_token, token, _opts}, _from, state) do
    start = System.monotonic_time()
    {reply, state} = lookup_by_token(state, token)
    Common.emit_lookup_telemetry(:memory, start, :token, reply)
    {:reply, reply, state}
  end

  def handle_call({:lookup_value, entity, value, _opts}, _from, state) do
    start = System.monotonic_time()
    {reply, state} = lookup_by_value(state, entity, value)
    Common.emit_lookup_telemetry(:memory, start, :value, reply)
    {:reply, reply, state}
  end

  def handle_call({:clear, _opts}, _from, state) do
    {:reply, :ok, %{state | by_value: %{}, by_token: %{}, counters: %{}}}
  end

  def handle_call(:info, _from, state) do
    {:reply, {:ok, %{backend: :memory, size: map_size(state.by_token)}}, state}
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

      state =
        state
        |> put_entry(entry)
        |> put_in([:counters, entity], counter)

      {:ok, entry, state}
    end
  end

  defp lookup_by_token(state, token) do
    case Map.fetch(state.by_token, token) do
      {:ok, entry} ->
        entry = Common.touch(entry)
        {{:ok, entry}, put_entry(state, entry)}

      :error ->
        {{:error, {:token_not_found, Common.token_shape(token)}}, state}
    end
  end

  defp lookup_by_value(state, entity, value) do
    case Map.fetch(state.by_value, {entity, value}) do
      {:ok, entry} ->
        entry = Common.touch(entry)
        {{:ok, entry}, put_entry(state, entry)}

      :error ->
        {{:error, {:value_not_found, entity}}, state}
    end
  end

  defp put_entry(state, entry) do
    %{
      state
      | by_value: Map.put(state.by_value, {entry.entity, entry.value}, entry),
        by_token: Map.put(state.by_token, entry.token, entry)
    }
  end
end
