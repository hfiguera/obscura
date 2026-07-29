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
  safeguard. Parameter keys containing deterministic structured PII are
  replaced before inspection. Original request paths and exception reasons are
  intentionally omitted.
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
  @filtered_key_prefix "[FILTERED KEY "

  @key_entities [
    :credit_card,
    :domain,
    :email,
    :iban,
    :ip_address,
    :phone,
    :url,
    :us_ssn
  ]

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
  `{:invalid_option, option, reason}` error. Structs and other opaque terms in
  the assigned params are rendered as `[FILTERED]` rather than invoking custom
  inspection code.
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
      dispatch_event(event, measurements, metadata, config)
    else
      :telemetry.detach(handler_id)
      :ok
    end
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
    params = safe_parameters(conn, config)
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
    |> filter_parameters()
    |> log_safe_term()
  rescue
    _error -> @filtered
  catch
    _kind, _reason -> @filtered
  end

  defp filter_parameters(values) do
    :phoenix
    |> Application.get_env(:filter_parameters, [])
    |> compile_parameter_filter()
    |> case do
      {:ok, filter} -> apply_parameter_filter(values, filter)
      :error -> @filtered
    end
  end

  defp compile_parameter_filter({:compiled, _key_match, _value_match} = filter),
    do: {:ok, filter}

  defp compile_parameter_filter({:discard, parameters}),
    do: compile_parameter_filter(parameters)

  defp compile_parameter_filter({:keep, parameters}) when is_list(parameters),
    do: {:ok, {:keep, parameters}}

  defp compile_parameter_filter([]), do: {:ok, {:compiled, [], []}}

  defp compile_parameter_filter(parameters)
       when is_list(parameters) or is_binary(parameters) do
    parameters = List.wrap(parameters)

    if Enum.all?(parameters, &is_binary/1) do
      key_match = :binary.compile_pattern(parameters)
      value_match = parameters |> Enum.map(&(&1 <> "=")) |> :binary.compile_pattern()
      {:ok, {:compiled, key_match, value_match}}
    else
      :error
    end
  end

  defp compile_parameter_filter(_parameters), do: :error

  defp apply_parameter_filter(values, {:compiled, key_match, value_match}),
    do: discard_parameter_values(values, key_match, value_match)

  defp apply_parameter_filter(values, {:keep, parameters}),
    do: keep_parameter_values(values, parameters)

  defp discard_parameter_values(%{__struct__: module} = struct, _key_match, _value_match)
       when is_atom(module),
       do: struct

  defp discard_parameter_values(map, key_match, value_match) when is_map(map) do
    Map.new(map, fn {key, value} ->
      cond do
        is_binary(key) and String.contains?(key, key_match) ->
          {key, @filtered}

        is_binary(value) and String.contains?(value, value_match) ->
          {key, @filtered}

        true ->
          {key, discard_parameter_values(value, key_match, value_match)}
      end
    end)
  end

  defp discard_parameter_values(list, key_match, value_match) when is_list(list) do
    if List.improper?(list) do
      list
    else
      Enum.map(list, &discard_parameter_values(&1, key_match, value_match))
    end
  end

  defp discard_parameter_values(value, _key_match, _value_match), do: value

  defp keep_parameter_values(%{__struct__: module}, _parameters) when is_atom(module),
    do: @filtered

  defp keep_parameter_values(map, parameters) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if is_binary(key) and key in parameters do
        {key, value}
      else
        {key, keep_parameter_values(value, parameters)}
      end
    end)
  end

  defp keep_parameter_values(list, parameters) when is_list(list) do
    if List.improper?(list) do
      @filtered
    else
      Enum.map(list, &keep_parameter_values(&1, parameters))
    end
  end

  defp keep_parameter_values(_value, _parameters), do: @filtered

  defp handler_config(opts) do
    with :ok <- validate_options(opts),
         :ok <- validate_assign(Keyword.get(opts, :assign, :obscura_redacted)),
         :ok <- validate_inspect_opts(Keyword.get(opts, :inspect_opts, [])) do
      name = Keyword.get(opts, :name, __MODULE__)
      handler_id = {__MODULE__, name, make_ref()}

      config =
        opts
        |> Keyword.take([:assign, :inspect_opts])
        |> Map.new()
        |> Map.merge(%{handler_id: handler_id, owner: self()})

      {:ok, handler_id, config}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp validate_options(opts) do
    case Keyword.keys(opts) -- @allowed_options do
      [] -> :ok
      [option | _rest] -> {:error, {:invalid_option, option, :unknown_option}}
    end
  end

  defp validate_assign(assign) when is_atom(assign), do: :ok
  defp validate_assign(_assign), do: {:error, {:invalid_option, :assign, :expected_atom}}

  defp validate_inspect_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      try do
        _opts = Inspect.Opts.new(opts)
        _rendered = inspect(%{sample: [1, "value"]}, opts)
        :ok
      rescue
        _error -> {:error, {:invalid_option, :inspect_opts, :invalid_inspect_options}}
      end
    else
      {:error, {:invalid_option, :inspect_opts, :expected_keyword_list}}
    end
  end

  defp validate_inspect_opts(_opts),
    do: {:error, {:invalid_option, :inspect_opts, :expected_keyword_list}}

  defp detach_previous_handlers(name) do
    @events
    |> Enum.flat_map(&:telemetry.list_handlers/1)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.filter(fn
      {__MODULE__, ^name, _generation} -> true
      _handler_id -> false
    end)
    |> Enum.each(&:telemetry.detach/1)
  end

  defp log_safe_term(%{__struct__: module}) when is_atom(module), do: @filtered

  defp log_safe_term(map) when is_map(map) do
    map
    |> Enum.with_index(1)
    |> Map.new(fn {{key, value}, index} ->
      {log_safe_key(key, index), log_safe_term(value)}
    end)
  end

  defp log_safe_term(list) when is_list(list) do
    if List.improper?(list), do: @filtered, else: Enum.map(list, &log_safe_term/1)
  end

  defp log_safe_term(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&log_safe_term/1)
    |> List.to_tuple()
  end

  defp log_safe_term(value)
       when is_binary(value) or is_number(value) or is_atom(value),
       do: value

  defp log_safe_term(_value), do: @filtered

  defp log_safe_key(key, index) when is_binary(key) do
    if String.starts_with?(key, @filtered_key_prefix) or key_contains_pii?(key) do
      filtered_key(index)
    else
      key
    end
  end

  defp log_safe_key(key, _index) when is_atom(key) or is_number(key), do: key
  defp log_safe_key(_key, index), do: filtered_key(index)

  defp key_contains_pii?(key) do
    case Obscura.redact(key,
           profile: :fast,
           entities: @key_entities,
           include_text: false,
           telemetry: false
         ) do
      {:ok, %{text: ^key}} -> false
      {:ok, _redacted} -> true
      {:error, _reason} -> true
    end
  end

  defp filtered_key(index), do: @filtered_key_prefix <> Integer.to_string(index) <> "]"

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
