defmodule Obscura.Phoenix.SocketLogger do
  @moduledoc """
  Privacy-safe logging for Phoenix socket connection and drain events.

  This opt-in telemetry handler replaces the socket portion of Phoenix's
  default logger after `config :phoenix, :logger, false` disables it. Connection
  parameters are omitted by default. `connect_info` is never logged.

  Add the handler to the application supervision tree:

      children = [
        {Obscura.Phoenix.SocketLogger, connect_params: :omit}
      ]

  To include a bounded redacted copy of connection parameters, opt in to the
  dependency-light `:fast` profile:

      {Obscura.Phoenix.SocketLogger,
       connect_params: {:redact, entities: [:email, :phone, :credit_card]}}

  Model-backed profiles and custom realtime callbacks are intentionally not
  accepted in this synchronous logging path. Parameter text above the fixed
  4 KiB realtime analysis budget is logged as `[FILTERED]` without running PII
  recognition. Structs and tuple-bearing terms, including keyword lists, also
  fail closed without protocol dispatch.
  """

  use GenServer

  alias Obscura.Internal.PhoenixLog

  @events [[:phoenix, :socket_connected], [:phoenix, :socket_drain]]
  @allowed_options [:connect_params, :inspect_opts, :name]

  @doc "Starts the Phoenix socket telemetry handler."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with :ok <- PhoenixLog.validate_options(opts, @allowed_options),
         :ok <- PhoenixLog.validate_default_logger(@events),
         inspect_opts = Keyword.get(opts, :inspect_opts, limit: 50, printable_limit: 500),
         :ok <- PhoenixLog.validate_inspect_opts(inspect_opts),
         {:ok, params_policy} <-
           PhoenixLog.prepare_params_policy(
             Keyword.get(opts, :connect_params, :omit),
             inspect_opts
           ) do
      name = Keyword.get(opts, :name, __MODULE__)
      handler_id = {__MODULE__, name, make_ref()}
      detach_previous_handlers(name)

      config = %{
        handler_id: handler_id,
        owner: self(),
        params_policy: params_policy
      }

      case :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_event/4, config) do
        :ok -> {:ok, handler_id}
        {:error, reason} -> {:stop, reason}
      end
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @doc false
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(
        event,
        measurements,
        metadata,
        %{owner: owner, handler_id: handler_id} = config
      ) do
    PhoenixLog.dispatch(owner, handler_id, fn ->
      dispatch(event, measurements, metadata, config)
    end)
  end

  @impl true
  def terminate(_reason, handler_id), do: :telemetry.detach(handler_id)

  defp dispatch([:phoenix, :socket_connected], _measurements, %{log: false}, _config),
    do: :ok

  defp dispatch([:phoenix, :socket_connected], measurements, metadata, config) do
    level = PhoenixLog.log_level(Map.get(metadata, :log), :info)

    PhoenixLog.log(level, fn ->
      [
        connection_result(Map.get(metadata, :result)),
        PhoenixLog.safe_identifier(Map.get(metadata, :user_socket)),
        " in ",
        PhoenixLog.duration(Map.get(measurements, :duration)),
        "\n  Transport: ",
        PhoenixLog.safe_identifier(Map.get(metadata, :transport)),
        "\n  Serializer: ",
        PhoenixLog.safe_identifier(Map.get(metadata, :serializer)),
        "\n  Parameters: ",
        PhoenixLog.render_params(Map.get(metadata, :params), config.params_policy)
      ]
    end)
  end

  defp dispatch([:phoenix, :socket_drain], _measurements, %{log: false}, _config),
    do: :ok

  defp dispatch([:phoenix, :socket_drain], measurements, metadata, _config) do
    level = PhoenixLog.log_level(Map.get(metadata, :log), :info)

    PhoenixLog.log(level, fn ->
      [
        "DRAINING ",
        PhoenixLog.safe_count(Map.get(measurements, :count)),
        " of ",
        PhoenixLog.safe_count(Map.get(measurements, :total)),
        " total connection(s) for socket ",
        PhoenixLog.safe_identifier(Map.get(metadata, :socket)),
        " every ",
        PhoenixLog.safe_count(Map.get(metadata, :interval)),
        "ms - round ",
        PhoenixLog.safe_count(Map.get(measurements, :index)),
        " of ",
        PhoenixLog.safe_count(Map.get(measurements, :rounds))
      ]
    end)
  end

  defp dispatch(_event, _measurements, _metadata, _config), do: :ok

  defp connection_result(:ok), do: "CONNECTED TO "
  defp connection_result(:error), do: "REFUSED CONNECTION TO "
  defp connection_result(_result), do: "SOCKET CONNECTION FOR "

  defp detach_previous_handlers(name) do
    PhoenixLog.detach_previous_handlers(@events, __MODULE__, name)
  end
end
