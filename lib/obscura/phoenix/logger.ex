defmodule Obscura.Phoenix.Logger do
  @moduledoc """
  Privacy-safe Phoenix request logging backed by redacted Plug assigns.

  This handler is an opt-in replacement for Phoenix's default telemetry logger.
  It never reads `conn.params`. Instead, it logs the redacted copy produced by
  `Obscura.Phoenix.Plug` in `:assign_redacted` mode.

  Disable Phoenix's default logger before starting this handler:

      config :phoenix, :logger, false

  Place `Obscura.Phoenix.Plug` after `Plug.Parsers` and before the router:

      plug Obscura.Phoenix.Plug,
        mode: :assign_redacted,
        fields: [:params]

      plug MyAppWeb.Router

  Then add the handler to the application supervision tree:

      children = [
        {Obscura.Phoenix.Logger, assign: :obscura_redacted}
      ]

  When the expected assign is missing, parameters are logged as `[FILTERED]`.
  Original request paths and exception reasons are intentionally omitted.
  """

  use GenServer

  require Elixir.Logger

  alias Plug.Conn.Status, as: ConnStatus

  @events [
    [:phoenix, :endpoint, :stop],
    [:phoenix, :error_rendered],
    [:phoenix, :router_dispatch, :start]
  ]

  @filtered "[FILTERED]"

  @doc """
  Starts the telemetry handler.

  Options:

    * `:assign` - connection assign populated by `Obscura.Phoenix.Plug`;
      defaults to `:obscura_redacted`
    * `:name` - registered process name; defaults to this module
    * `:inspect_opts` - options used to inspect redacted parameters
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    handler_id = {__MODULE__, self()}
    handler_config = Map.new(Keyword.take(opts, [:assign, :inspect_opts]))

    case :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_event/4, handler_config) do
      :ok -> {:ok, handler_id}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc false
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(
        [:phoenix, :router_dispatch, :start],
        _measurements,
        %{log: false},
        _config
      ),
      do: :ok

  def handle_event(
        [:phoenix, :router_dispatch, :start],
        _measurements,
        %{conn: conn} = metadata,
        config
      ) do
    level = log_level(Map.get(metadata, :log), conn)
    params = redacted_params(conn, config)
    inspect_opts = Map.get(config, :inspect_opts, limit: 50, printable_limit: 500)

    log(level, fn ->
      [
        "Processing ",
        conn.method,
        " with ",
        route(metadata),
        ?\n,
        "  Parameters: ",
        inspect(params, inspect_opts),
        ?\n,
        "  Pipelines: ",
        inspect(Map.get(metadata, :pipe_through, []))
      ]
    end)
  end

  def handle_event(
        [:phoenix, :endpoint, :stop],
        %{duration: duration},
        %{conn: conn} = metadata,
        _config
      ) do
    level = log_level(get_in(metadata, [:options, :log]), conn)

    log(level, fn ->
      [
        connection_type(conn.state),
        ?\s,
        status(conn.status),
        " in ",
        duration(duration)
      ]
    end)
  end

  def handle_event(
        [:phoenix, :error_rendered],
        _measurements,
        %{log: false},
        _config
      ),
      do: :ok

  def handle_event(
        [:phoenix, :error_rendered],
        _measurements,
        metadata,
        _config
      ) do
    level = Map.get(metadata, :log, :error)

    log(level, fn ->
      [
        "Converted ",
        metadata |> Map.get(:kind, :error) |> to_string(),
        " to ",
        status(Map.get(metadata, :status)),
        " response"
      ]
    end)
  end

  defp redacted_params(conn, config) do
    assign = Map.get(config, :assign, :obscura_redacted)

    case Map.get(conn.assigns, assign) do
      %{params: params} -> params
      %{"params" => params} -> params
      _missing -> @filtered
    end
  end

  defp route(metadata) do
    case Map.get(metadata, :route) do
      route when is_binary(route) -> route
      _missing -> "[FILTERED ROUTE]"
    end
  end

  defp log_level(nil, _conn), do: :info
  defp log_level(false, _conn), do: false
  defp log_level(level, _conn) when is_atom(level), do: level

  defp log_level({module, function, args}, conn)
       when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, [conn | args])
  end

  defp log(false, _message), do: :ok
  defp log(level, message), do: Elixir.Logger.log(level, message)

  defp connection_type(:set_chunked), do: "Chunked"
  defp connection_type(_state), do: "Sent"

  defp status(nil), do: "unknown"

  defp status(status) when is_atom(status) do
    status
    |> ConnStatus.code()
    |> Integer.to_string()
  end

  defp status(status) when is_integer(status), do: Integer.to_string(status)

  defp duration(duration) do
    microseconds = System.convert_time_unit(duration, :native, :microsecond)

    if microseconds > 1000 do
      [microseconds |> div(1000) |> Integer.to_string(), "ms"]
    else
      [Integer.to_string(microseconds), "µs"]
    end
  end
end
