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
  Phoenix's configured `:filter_parameters` policy is applied as an additional
  safeguard. Parameter keys containing high-confidence `:fast` profile PII are
  replaced before inspection. Ambiguous bare domains are left to explicit
  Phoenix filter policies. Original request paths and exception reasons are
  intentionally omitted.
  """

  use GenServer

  require Elixir.Logger

  alias Obscura.Internal.PhoenixLog
  alias Plug.Conn.Status, as: ConnStatus

  @events [
    [:phoenix, :endpoint, :stop],
    [:phoenix, :error_rendered],
    [:phoenix, :router_dispatch, :start]
  ]

  @filtered "[FILTERED]"

  @allowed_options [:assign, :inspect_opts, :name]

  @doc """
  Starts the telemetry handler.

  Options:

    * `:assign` - connection assign populated by `Obscura.Phoenix.Plug`;
      defaults to `:obscura_redacted`
    * `:name` - registered process name; defaults to this module
    * `:inspect_opts` - valid `Inspect.Opts` options used to inspect redacted
      parameters; defaults to `[limit: 50, printable_limit: 500]`

  Unknown options and invalid assign or inspection options stop startup with an
  `{:invalid_option, option, reason}` error. Structs, tuples, character lists
  containing high-confidence `:fast` profile PII, and other opaque terms in the
  assigned params are rendered as `[FILTERED]` rather than invoking custom
  inspection code. Atom and numeric scalar representations are checked for
  high-confidence `:fast` profile PII before inspection. Parameter graphs
  exceeding 64 keys, 4 KiB of cumulative key text, 64 KiB of cumulative scalar
  value text, 1,024 traversed values, 128 terms requiring PII analysis, or 64
  decimal digits in one number also fail closed as `[FILTERED]`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, handler_id, handler_config} <- handler_config(opts) do
      detach_previous_handlers(Keyword.get(opts, :name, __MODULE__))

      case :telemetry.attach_many(
             handler_id,
             @events,
             &__MODULE__.handle_event/4,
             handler_config
           ) do
        :ok -> {:ok, handler_id}
        {:error, reason} -> {:stop, reason}
      end
    end
  end

  @impl true
  def terminate(_reason, handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc false
  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(
        event,
        measurements,
        metadata,
        %{owner: owner, handler_id: handler_id} = config
      ) do
    if Process.alive?(owner) do
      safely_dispatch_event(event, measurements, metadata, config)
    else
      :telemetry.detach(handler_id)
      :ok
    end
  end

  defp safely_dispatch_event(event, measurements, metadata, config) do
    dispatch_event(event, measurements, metadata, config)
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp dispatch_event(
         [:phoenix, :router_dispatch, :start],
         _measurements,
         %{log: false},
         _config
       ),
       do: :ok

  defp dispatch_event(
         [:phoenix, :router_dispatch, :start],
         _measurements,
         %{conn: conn} = metadata,
         config
       ) do
    level = log_level(Map.get(metadata, :log), conn)
    inspect_opts = Map.get(config, :inspect_opts, limit: 50, printable_limit: 500)

    log(level, fn ->
      params = safe_parameters(conn, config)

      [
        "Processing ",
        PhoenixLog.safe_method(conn.method, Map.fetch!(config, :key_entities)),
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

  defp dispatch_event(
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

  defp dispatch_event(
         [:phoenix, :error_rendered],
         _measurements,
         %{log: false},
         _config
       ),
       do: :ok

  defp dispatch_event(
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

  defp safe_parameters(conn, config) do
    conn
    |> redacted_params(config)
    |> PhoenixLog.sanitize_params(Map.fetch!(config, :key_entities))
  end

  defp handler_config(opts) do
    with :ok <- PhoenixLog.validate_options(opts, @allowed_options),
         :ok <- validate_assign(Keyword.get(opts, :assign, :obscura_redacted)),
         :ok <- PhoenixLog.validate_inspect_opts(Keyword.get(opts, :inspect_opts, [])) do
      name = Keyword.get(opts, :name, __MODULE__)
      handler_id = {__MODULE__, name, make_ref()}

      config =
        opts
        |> Keyword.take([:assign, :inspect_opts])
        |> Map.new()
        |> Map.merge(%{
          handler_id: handler_id,
          key_entities: PhoenixLog.key_entities_or_filter_all(),
          owner: self()
        })

      {:ok, handler_id, config}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp validate_assign(assign) when is_atom(assign), do: :ok
  defp validate_assign(_assign), do: {:error, {:invalid_option, :assign, :expected_atom}}

  defp detach_previous_handlers(name) do
    PhoenixLog.detach_previous_handlers(@events, __MODULE__, name)
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

  defp log(level, message) do
    metadata = Elixir.Logger.metadata()
    Elixir.Logger.reset_metadata()

    try do
      Elixir.Logger.log(level, message)
    after
      Elixir.Logger.reset_metadata(metadata)
    end
  end

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
