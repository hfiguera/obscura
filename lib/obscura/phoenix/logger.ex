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

  alias Plug.Conn.Status, as: ConnStatus

  @events [
    [:phoenix, :endpoint, :stop],
    [:phoenix, :error_rendered],
    [:phoenix, :router_dispatch, :start]
  ]

  @filtered "[FILTERED]"
  @filtered_key_prefix "[FILTERED KEY "

  @max_parameter_keys 64
  @max_parameter_key_bytes 4_096
  @max_parameter_nodes 1_024
  @max_parameter_value_bytes 65_536
  @max_parameter_analysis_terms 128
  @max_numeric_digits 64
  @max_numeric_magnitude Integer.pow(10, @max_numeric_digits)

  @max_method_bytes 32
  @standard_methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS CONNECT TRACE)

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
    inspect_opts = Map.get(config, :inspect_opts, limit: 50, printable_limit: 500)

    log(level, fn ->
      params = safe_parameters(conn, config)

      [
        "Processing ",
        safe_method(conn.method, Map.fetch!(config, :key_entities)),
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
    params = redacted_params(conn, config)

    if parameter_budget_safe?(params) do
      params
      |> filter_parameters()
      |> log_safe_term(Map.fetch!(config, :key_entities))
    else
      @filtered
    end
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
        |> Map.merge(%{
          handler_id: handler_id,
          key_entities: key_entities(),
          owner: self()
        })

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

  defp log_safe_term(%{__struct__: module}, _key_entities) when is_atom(module), do: @filtered

  defp log_safe_term(map, key_entities) when is_map(map) do
    map
    |> Enum.with_index(1)
    |> Map.new(fn {{key, value}, index} ->
      {log_safe_key(key, index, key_entities), log_safe_term(value, key_entities)}
    end)
  end

  defp log_safe_term(list, key_entities) when is_list(list) do
    cond do
      List.improper?(list) -> @filtered
      flat_charlist?(list) -> log_safe_charlist(list, key_entities)
      true -> Enum.map(list, &log_safe_term(&1, key_entities))
    end
  end

  defp log_safe_term(tuple, _key_entities) when is_tuple(tuple), do: @filtered

  defp log_safe_term(value, _key_entities) when is_binary(value), do: value

  defp log_safe_term(value, key_entities) when is_number(value) or is_atom(value) do
    if text_contains_pii?(scalar_text(value), value_entities(key_entities)) do
      @filtered
    else
      value
    end
  end

  defp log_safe_term(_value, _key_entities), do: @filtered

  defp log_safe_key(key, index, key_entities) when is_binary(key) do
    if String.starts_with?(key, @filtered_key_prefix) or
         text_contains_pii?(key, key_entities) do
      filtered_key(index)
    else
      key
    end
  end

  defp log_safe_key(key, index, key_entities) when is_atom(key) or is_number(key) do
    if text_contains_pii?(scalar_text(key), key_entities), do: filtered_key(index), else: key
  end

  defp log_safe_key(_key, index, _key_entities), do: filtered_key(index)

  defp text_contains_pii?(_text, :filter_all), do: true

  defp text_contains_pii?(text, entities) when is_list(entities) do
    case Obscura.redact(text,
           profile: :fast,
           entities: entities,
           include_text: false,
           telemetry: false
         ) do
      {:ok, %{text: ^text}} -> false
      {:ok, _redacted} -> true
      {:error, _reason} -> true
    end
  end

  defp filtered_key(index), do: @filtered_key_prefix <> Integer.to_string(index) <> "]"

  defp parameter_budget_safe?(params) do
    match?({:ok, _budget}, consume_parameter_term(params, {0, 0, 0, 0, 0}))
  end

  defp consume_parameter_term(_term, {nodes, keys, key_bytes, value_bytes, analysis_terms})
       when nodes >= @max_parameter_nodes or keys > @max_parameter_keys or
              key_bytes > @max_parameter_key_bytes or
              value_bytes > @max_parameter_value_bytes or
              analysis_terms > @max_parameter_analysis_terms,
       do: :error

  defp consume_parameter_term(%{__struct__: module}, budget) when is_atom(module),
    do: consume_parameter_node(budget)

  defp consume_parameter_term(map, budget) when is_map(map) do
    with {:ok, budget} <- consume_parameter_node(budget) do
      Enum.reduce_while(map, {:ok, budget}, &consume_parameter_entry/2)
    end
  end

  defp consume_parameter_term(list, budget) when is_list(list) do
    with {:ok, budget} <- consume_parameter_node(budget) do
      case bounded_charlist_size(list) do
        {:ok, count, size} ->
          consume_parameter_charlist(count, size, budget)

        :not_charlist ->
          consume_parameter_list(list, budget)

        :error ->
          :error
      end
    end
  end

  defp consume_parameter_term(value, budget) when is_binary(value) do
    with {:ok, budget} <- consume_parameter_node(budget) do
      consume_parameter_value(byte_size(value), budget)
    end
  end

  defp consume_parameter_term(value, budget) when is_atom(value) or is_number(value) do
    with {:ok, size} <- bounded_scalar_size(value),
         {:ok, budget} <- consume_parameter_node(budget),
         {:ok, budget} <- consume_parameter_value(size, budget) do
      consume_parameter_analysis(budget)
    end
  end

  defp consume_parameter_term(_term, budget), do: consume_parameter_node(budget)

  defp consume_parameter_entry({key, value}, {:ok, budget}) do
    with {:ok, budget} <- consume_parameter_key(key, budget),
         {:ok, budget} <- consume_parameter_term(value, budget) do
      {:cont, {:ok, budget}}
    else
      :error -> {:halt, :error}
    end
  end

  defp consume_parameter_list([], budget), do: {:ok, budget}

  defp consume_parameter_list([value | rest], budget) do
    with {:ok, budget} <- consume_parameter_term(value, budget) do
      if is_list(rest), do: consume_parameter_list(rest, budget), else: {:ok, budget}
    end
  end

  defp consume_parameter_charlist(count, size, budget) do
    with {:ok, budget} <- consume_parameter_nodes(count, budget),
         {:ok, budget} <- consume_parameter_value(size, budget) do
      consume_parameter_analysis(budget)
    end
  end

  defp consume_parameter_node({nodes, keys, key_bytes, value_bytes, analysis_terms}) do
    budget = {nodes + 1, keys, key_bytes, value_bytes, analysis_terms}

    if elem(budget, 0) > @max_parameter_nodes, do: :error, else: {:ok, budget}
  end

  defp consume_parameter_nodes(
         count,
         {nodes, keys, key_bytes, value_bytes, analysis_terms}
       ) do
    budget = {nodes + count, keys, key_bytes, value_bytes, analysis_terms}

    if elem(budget, 0) > @max_parameter_nodes, do: :error, else: {:ok, budget}
  end

  defp consume_parameter_key(key, {nodes, keys, key_bytes, value_bytes, analysis_terms}) do
    with {:ok, size} <- bounded_key_size(key) do
      budget = {nodes, keys + 1, key_bytes + size, value_bytes, analysis_terms}

      if elem(budget, 1) > @max_parameter_keys or
           elem(budget, 2) > @max_parameter_key_bytes do
        :error
      else
        consume_parameter_key_analysis(key, budget)
      end
    end
  end

  defp consume_parameter_key_analysis(key, budget)
       when is_binary(key) or is_atom(key) or is_number(key),
       do: consume_parameter_analysis(budget)

  defp consume_parameter_key_analysis(_key, budget), do: {:ok, budget}

  defp consume_parameter_value(
         size,
         {nodes, keys, key_bytes, value_bytes, analysis_terms}
       ) do
    budget = {nodes, keys, key_bytes, value_bytes + size, analysis_terms}

    if elem(budget, 3) > @max_parameter_value_bytes, do: :error, else: {:ok, budget}
  end

  defp consume_parameter_analysis({nodes, keys, key_bytes, value_bytes, analysis_terms}) do
    budget = {nodes, keys, key_bytes, value_bytes, analysis_terms + 1}

    if elem(budget, 4) > @max_parameter_analysis_terms do
      :error
    else
      {:ok, budget}
    end
  end

  defp bounded_key_size(key) when is_binary(key), do: {:ok, byte_size(key)}

  defp bounded_key_size(key) when is_atom(key) or is_number(key),
    do: bounded_scalar_size(key)

  defp bounded_key_size(_key), do: {:ok, 0}

  defp bounded_scalar_size(value) when is_atom(value),
    do: {:ok, value |> Atom.to_string() |> byte_size()}

  defp bounded_scalar_size(value) when is_integer(value) do
    if value > -@max_numeric_magnitude and value < @max_numeric_magnitude do
      {:ok, value |> Integer.to_string() |> byte_size()}
    else
      :error
    end
  end

  defp bounded_scalar_size(value) when is_float(value),
    do: {:ok, value |> Float.to_string() |> byte_size()}

  defp bounded_charlist_size([]), do: :not_charlist
  defp bounded_charlist_size(list), do: bounded_charlist_size(list, 0, 0)

  defp bounded_charlist_size([], count, size), do: {:ok, count, size}

  defp bounded_charlist_size(_list, count, _size) when count >= @max_parameter_nodes,
    do: :error

  defp bounded_charlist_size([value | rest], count, size) do
    if unicode_codepoint?(value) and is_list(rest) do
      bounded_charlist_size(rest, count + 1, size + utf8_codepoint_size(value))
    else
      :not_charlist
    end
  end

  defp bounded_charlist_size(_improper, _count, _size), do: :not_charlist

  defp utf8_codepoint_size(value) when value <= 0x7F, do: 1
  defp utf8_codepoint_size(value) when value <= 0x7FF, do: 2
  defp utf8_codepoint_size(value) when value <= 0xFFFF, do: 3
  defp utf8_codepoint_size(_value), do: 4

  defp flat_charlist?([]), do: false

  defp flat_charlist?(list) do
    Enum.all?(list, &unicode_codepoint?/1)
  end

  defp log_safe_charlist(list, key_entities) do
    if text_contains_pii?(List.to_string(list), value_entities(key_entities)) do
      @filtered
    else
      list
    end
  end

  defp value_entities(:filter_all), do: :filter_all
  defp value_entities(key_entities), do: [:domain | key_entities]

  defp scalar_text(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar_text(value) when is_number(value), do: to_string(value)

  defp unicode_codepoint?(value) when is_integer(value) do
    value >= 0 and value <= 0x10FFFF and value not in 0xD800..0xDFFF
  end

  defp unicode_codepoint?(_value), do: false

  defp key_entities do
    case Obscura.Profile.fetch(:fast) do
      {:ok, profile} -> profile.supported_entities -- [:domain]
      {:error, _reason} -> :filter_all
    end
  end

  defp safe_method(method, _key_entities) when method in @standard_methods, do: method

  defp safe_method(method, key_entities)
       when is_binary(method) and byte_size(method) <= @max_method_bytes do
    if text_contains_pii?(method, value_entities(key_entities)),
      do: "[FILTERED METHOD]",
      else: method
  end

  defp safe_method(_method, _key_entities), do: "[FILTERED METHOD]"

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
