defmodule Obscura.Internal.PhoenixLog do
  @moduledoc false

  require Logger

  @filtered "[FILTERED]"
  @omitted "[OMITTED]"
  @filtered_event "[FILTERED EVENT]"
  @filtered_identifier "[FILTERED IDENTIFIER]"
  @filtered_topic "[FILTERED TOPIC]"
  @filtered_key_prefix "[FILTERED KEY "

  @max_parameter_keys 64
  @max_parameter_key_bytes 4_096
  @max_parameter_nodes 1_024
  @max_parameter_value_bytes 65_536
  @max_parameter_analysis_terms 128
  @max_realtime_parameter_analysis_bytes 4_096
  @max_numeric_digits 64
  @max_numeric_magnitude Integer.pow(10, @max_numeric_digits)

  @max_patterns 64
  @max_events 128
  @max_label_bytes 128
  @max_topic_bytes 4_096
  @max_identifier_bytes 255
  @max_method_bytes 32
  @max_measurement 9_223_372_036_854_775_807

  @standard_methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS CONNECT TRACE)
  @unsafe_static_label ~r/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u

  @levels [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

  @reserved_logger_metadata_keys [
    :application,
    :crash_reason,
    :domain,
    :erl_level,
    :error_logger,
    :file,
    :function,
    :gl,
    :initial_call,
    :line,
    :logger_formatter,
    :mfa,
    :module,
    :pid,
    :registered_name,
    :report_cb,
    :time
  ]

  @redaction_options [:entities, :max_depth]

  @type params_policy :: %{mode: :omit} | map()
  @type event_labels :: %{optional(String.t()) => String.t()}
  @type correlation_policy ::
          %{mode: :omit}
          | %{mode: :socket_assign, assign: atom(), metadata_key: atom(), format: :uuid}

  @spec filtered() :: String.t()
  def filtered, do: @filtered

  @spec validate_options(term(), [atom()]) :: :ok | {:error, term()}
  def validate_options(opts, allowed) when is_list(allowed) do
    cond do
      not Keyword.keyword?(opts) ->
        invalid_option(:options, :expected_keyword_list)

      unknown = Keyword.keys(opts) -- allowed ->
        case unknown do
          [] -> :ok
          [option | _rest] -> invalid_option(option, :unknown_option)
        end
    end
  end

  @spec dispatch(pid(), term(), (-> term())) :: :ok
  def dispatch(owner, handler_id, callback)
      when is_pid(owner) and is_function(callback, 0) do
    if Process.alive?(owner) do
      safely_dispatch(callback)
    else
      :telemetry.detach(handler_id)
      :ok
    end
  end

  @spec detach_previous_handlers([[atom()]], module(), term()) :: :ok
  def detach_previous_handlers(events, module, name) do
    events
    |> Enum.flat_map(&:telemetry.list_handlers/1)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.filter(fn
      {^module, ^name, _generation} -> true
      _handler_id -> false
    end)
    |> Enum.each(&:telemetry.detach/1)
  end

  @spec validate_inspect_opts(term()) :: :ok | {:error, term()}
  def validate_inspect_opts(opts) when is_list(opts) do
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

  def validate_inspect_opts(_opts),
    do: {:error, {:invalid_option, :inspect_opts, :expected_keyword_list}}

  @spec prepare_params_policy(term(), keyword()) :: {:ok, params_policy()} | {:error, term()}
  def prepare_params_policy(:omit, _inspect_opts), do: {:ok, %{mode: :omit}}

  def prepare_params_policy({:redact, opts}, inspect_opts) when is_list(opts) do
    with :ok <- validate_redaction_options(opts),
         :ok <- validate_fast_profile(opts),
         {:ok, filter} <- compile_configured_filter(),
         {:ok, key_entities} <- key_entities(),
         redaction_opts <-
           opts
           |> Keyword.put(:profile, :fast)
           |> Keyword.put(:telemetry, false)
           |> Keyword.put(:include_text, false)
           |> Keyword.put(:traverse_structs, false)
           |> Keyword.put(:skip_protocol, true),
         {:ok, _probe} <- Obscura.Structured.redact(%{"sample" => "safe"}, redaction_opts) do
      {:ok,
       %{
         mode: :redact,
         filter: filter,
         inspect_opts: inspect_opts,
         key_entities: key_entities,
         redaction_opts: redaction_opts
       }}
    else
      {:error, {:invalid_option, _, _} = reason} ->
        {:error, reason}

      {:error, _reason} ->
        {:error, {:invalid_option, :params, :invalid_redaction_options}}
    end
  end

  def prepare_params_policy({:redact, _opts}, _inspect_opts),
    do: {:error, {:invalid_option, :params, :expected_keyword_list}}

  def prepare_params_policy(_policy, _inspect_opts),
    do: {:error, {:invalid_option, :params, :expected_omit_or_redact}}

  @spec render_params(term(), params_policy()) :: String.t()
  def render_params(_params, %{mode: :omit}), do: @omitted

  def render_params(params, %{mode: :redact} = policy) do
    with true <- realtime_parameter_budget_safe?(params),
         filtered <- apply_parameter_filter(params, policy.filter),
         {:ok, result} <- Obscura.Structured.redact(filtered, policy.redaction_opts),
         true <- realtime_parameter_budget_safe?(result.data) do
      result.data
      |> log_safe_term(policy.key_entities)
      |> inspect(policy.inspect_opts)
    else
      _failure -> @filtered
    end
  rescue
    _error -> @filtered
  catch
    _kind, _reason -> @filtered
  end

  @spec sanitize_params(term(), [atom()] | :filter_all) :: term()
  def sanitize_params(params, key_entities) do
    with true <- parameter_budget_safe?(params),
         {:ok, filter} <- compile_configured_filter() do
      params
      |> apply_parameter_filter(filter)
      |> log_safe_term(key_entities)
    else
      _failure -> @filtered
    end
  rescue
    _error -> @filtered
  catch
    _kind, _reason -> @filtered
  end

  @spec key_entities_or_filter_all() :: [atom()] | :filter_all
  def key_entities_or_filter_all do
    case key_entities() do
      {:ok, entities} -> entities
      {:error, _reason} -> :filter_all
    end
  end

  @spec safe_method(term(), [atom()] | :filter_all) :: String.t()
  def safe_method(method, _key_entities) when method in @standard_methods, do: method

  def safe_method(method, key_entities)
      when is_binary(method) and byte_size(method) <= @max_method_bytes do
    if http_token?(method) and
         not text_contains_pii?(method, value_entities(key_entities)),
       do: method,
       else: "[FILTERED METHOD]"
  end

  def safe_method(_method, _key_entities), do: "[FILTERED METHOD]"

  @spec prepare_topic_patterns(term()) :: {:ok, list()} | {:error, term()}
  def prepare_topic_patterns(patterns) when is_list(patterns) do
    with :ok <- validate_bounded_list(patterns, @max_patterns, :topic_patterns) do
      compile_topic_patterns(patterns)
    end
  end

  def prepare_topic_patterns(_patterns),
    do: invalid_option(:topic_patterns, :expected_list)

  @spec safe_topic(term(), list()) :: String.t()
  def safe_topic(topic, patterns)
      when is_binary(topic) and byte_size(topic) <= @max_topic_bytes do
    if String.valid?(topic), do: matching_topic_pattern(topic, patterns), else: @filtered_topic
  end

  def safe_topic(_topic, _patterns), do: @filtered_topic

  @spec prepare_correlation(term()) :: {:ok, correlation_policy()} | {:error, term()}
  def prepare_correlation(:omit), do: {:ok, %{mode: :omit}}

  def prepare_correlation({:socket_assign, assign, :uuid})
      when is_atom(assign) and not is_nil(assign) do
    if safe_correlation_key?(assign) do
      {:ok, %{mode: :socket_assign, assign: assign, metadata_key: assign, format: :uuid}}
    else
      invalid_option(:correlation, :invalid_metadata_key)
    end
  end

  def prepare_correlation(_correlation),
    do: invalid_option(:correlation, :expected_omit_or_socket_assign)

  @spec correlation_metadata(term(), correlation_policy(), boolean()) :: keyword()
  def correlation_metadata(_socket, _policy, false), do: []
  def correlation_metadata(_socket, %{mode: :omit}, true), do: []

  def correlation_metadata(
        %{assigns: assigns},
        %{mode: :socket_assign, assign: assign, metadata_key: metadata_key, format: :uuid},
        true
      )
      when is_map(assigns) do
    case Map.get(assigns, assign) do
      value when is_binary(value) ->
        if uuid?(value), do: [{metadata_key, value}], else: []

      _value ->
        []
    end
  end

  def correlation_metadata(_socket, _policy, true), do: []

  @spec prepare_events(term()) :: {:ok, event_labels()} | {:error, term()}
  def prepare_events(events) when is_list(events) do
    with :ok <- validate_bounded_list(events, @max_events, :events) do
      compile_events(events)
    end
  end

  def prepare_events(_events), do: invalid_option(:events, :expected_list)

  @spec safe_event(term(), event_labels()) :: String.t()
  def safe_event(event, allowed) when is_binary(event) and is_map(allowed) do
    case :maps.find(event, allowed) do
      {:ok, configured_event} -> configured_event
      :error -> @filtered_event
    end
  end

  def safe_event(_event, _allowed), do: @filtered_event

  @spec safe_identifier(term()) :: String.t()
  def safe_identifier(identifier) when is_atom(identifier) and not is_nil(identifier) do
    text = Atom.to_string(identifier)

    if byte_size(text) <= @max_identifier_bytes and identifier_text?(text) do
      inspect(identifier)
    else
      @filtered_identifier
    end
  end

  def safe_identifier(_identifier), do: @filtered_identifier

  @spec safe_result(term()) :: String.t()
  def safe_result(:ok), do: "ok"
  def safe_result(:error), do: "error"
  def safe_result(_result), do: "unknown"

  @spec duration(term()) :: iodata()
  def duration(value) when is_integer(value) and value >= 0 and value <= @max_measurement do
    microseconds = System.convert_time_unit(value, :native, :microsecond)

    if microseconds > 1000 do
      [microseconds |> div(1000) |> Integer.to_string(), "ms"]
    else
      [Integer.to_string(microseconds), "us"]
    end
  end

  def duration(_value), do: "unknown"

  @spec safe_count(term()) :: String.t()
  def safe_count(value) when is_integer(value) and value >= 0 and value <= @max_measurement,
    do: Integer.to_string(value)

  def safe_count(_value), do: "unknown"

  @spec log_level(term(), Logger.level()) :: Logger.level() | false
  def log_level(false, _default), do: false
  def log_level(nil, default), do: default
  def log_level(:warn, _default), do: :warning
  def log_level(level, _default) when level in @levels, do: level
  def log_level(_level, _default), do: false

  @spec log(Logger.level() | false, (-> iodata())) :: :ok
  def log(level, message), do: log(level, message, [])

  @spec log(Logger.level() | false, (-> iodata()), keyword()) :: :ok
  def log(false, _message, _metadata), do: :ok

  def log(level, message, safe_metadata)
      when level in @levels and is_function(message, 0) and is_list(safe_metadata) do
    metadata = Logger.metadata()
    Logger.reset_metadata()

    try do
      Logger.log(level, message, safe_metadata)
    after
      Logger.reset_metadata(metadata)
    end
  end

  def log(_level, _message, _metadata), do: :ok

  @spec phoenix_logger_attached?([atom()]) :: boolean()
  def phoenix_logger_attached?(event) do
    Enum.any?(:telemetry.list_handlers(event), fn
      %{id: {Phoenix.Logger, ^event}} -> true
      _handler -> false
    end)
  end

  @spec validate_default_logger([[atom()]]) :: :ok | {:error, term()}
  def validate_default_logger(events) do
    case Enum.find(events, &phoenix_logger_attached?/1) do
      nil -> :ok
      event -> {:error, {:unsafe_phoenix_logger_attached, event}}
    end
  end

  defp safely_dispatch(callback) do
    _result = callback.()
    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp validate_redaction_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        invalid_option(:params, :expected_keyword_list)

      Keyword.has_key?(opts, :profile) and Keyword.get(opts, :profile) != :fast ->
        invalid_option(:params, :fast_profile_required)

      unsupported = Keyword.keys(opts) -- [:profile | @redaction_options] ->
        case unsupported do
          [] -> :ok
          [option | _rest] -> invalid_option(option, :unsupported_realtime_redaction_option)
        end
    end
  end

  defp validate_fast_profile(opts) do
    if Keyword.get(opts, :profile, :fast) == :fast,
      do: :ok,
      else: invalid_option(:profile, :fast_profile_required)
  end

  defp compile_topic_pattern(pattern) do
    if safe_static_label?(pattern) do
      compile_valid_topic_pattern(pattern, :binary.matches(pattern, "*"))
    else
      invalid_option(:topic_patterns, :invalid_pattern)
    end
  end

  defp compile_valid_topic_pattern(pattern, []), do: {:ok, {:exact, pattern}}

  defp compile_valid_topic_pattern(pattern, [{index, 1}])
       when index == byte_size(pattern) - 1 and index > 0 do
    prefix = binary_part(pattern, 0, index)
    {:ok, {:prefix, prefix, pattern}}
  end

  defp compile_valid_topic_pattern("*", [{0, 1}]),
    do: invalid_option(:topic_patterns, :wildcard_only_pattern)

  defp compile_valid_topic_pattern(_pattern, _matches),
    do: invalid_option(:topic_patterns, :invalid_pattern)

  defp compile_topic_patterns(patterns) do
    patterns
    |> Enum.reduce_while({:ok, []}, &compile_topic_pattern_entry/2)
    |> reverse_compiled_patterns()
  end

  defp compile_topic_pattern_entry(pattern, {:ok, compiled}) do
    case compile_topic_pattern(pattern) do
      {:ok, entry} -> {:cont, {:ok, [entry | compiled]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp reverse_compiled_patterns({:ok, compiled}), do: {:ok, Enum.reverse(compiled)}
  defp reverse_compiled_patterns(error), do: error

  defp matching_topic_pattern(topic, patterns) do
    Enum.find_value(patterns, @filtered_topic, &matching_topic_pattern_entry(topic, &1))
  end

  defp matching_topic_pattern_entry(topic, {:exact, pattern}) when topic == pattern, do: pattern

  defp matching_topic_pattern_entry(topic, {:prefix, prefix, pattern}) do
    if String.starts_with?(topic, prefix), do: pattern
  end

  defp matching_topic_pattern_entry(_topic, _pattern), do: nil

  defp compile_events(events) do
    Enum.reduce_while(events, {:ok, %{}}, fn event, {:ok, compiled} ->
      if safe_static_label?(event) do
        owned_event = :binary.copy(event)
        {:cont, {:ok, Map.put(compiled, owned_event, owned_event)}}
      else
        {:halt, invalid_option(:events, :invalid_event)}
      end
    end)
  end

  defp validate_bounded_list(values, maximum, option) do
    cond do
      List.improper?(values) -> invalid_option(option, :expected_proper_list)
      Enum.count_until(values, maximum + 1) > maximum -> invalid_option(option, :too_many_values)
      true -> :ok
    end
  end

  defp safe_static_label?(label) when is_binary(label) do
    byte_size(label) > 0 and byte_size(label) <= @max_label_bytes and
      String.valid?(label) and String.printable?(label) and
      not Regex.match?(@unsafe_static_label, label) and not label_contains_pii?(label)
  end

  defp safe_static_label?(_label), do: false

  defp identifier_text?(<<>>), do: false
  defp identifier_text?(text), do: identifier_bytes?(text)
  defp identifier_bytes?(<<>>), do: true

  defp identifier_bytes?(<<byte, rest::binary>>)
       when byte in ?0..?9 or byte in ?A..?Z or byte in ?a..?z or byte in [?_, ?., ?:, ?-],
       do: identifier_bytes?(rest)

  defp identifier_bytes?(_text), do: false

  defp safe_correlation_key?(key) do
    text = Atom.to_string(key)

    byte_size(text) <= @max_identifier_bytes and identifier_text?(text) and
      key not in @reserved_logger_metadata_keys and not label_contains_pii?(text)
  end

  defp uuid?(
         <<part1::binary-size(8), "-", part2::binary-size(4), "-", part3::binary-size(4), "-",
           part4::binary-size(4), "-", part5::binary-size(12)>>
       ) do
    Enum.all?([part1, part2, part3, part4, part5], &hex?/1)
  end

  defp uuid?(_value), do: false

  defp hex?(value), do: hex_bytes?(value)
  defp hex_bytes?(<<>>), do: true

  defp hex_bytes?(<<byte, rest::binary>>)
       when byte in ?0..?9 or byte in ?A..?F or byte in ?a..?f,
       do: hex_bytes?(rest)

  defp hex_bytes?(_value), do: false

  defp label_contains_pii?(label) do
    case key_entities() do
      {:ok, entities} -> text_contains_pii?(label, [:domain | entities])
      {:error, _reason} -> true
    end
  end

  defp invalid_option(option, reason), do: {:error, {:invalid_option, option, reason}}

  defp compile_configured_filter do
    :phoenix
    |> Application.get_env(:filter_parameters, [])
    |> compile_parameter_filter()
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
      invalid_option(:filter_parameters, :invalid_phoenix_configuration)
    end
  end

  defp compile_parameter_filter(_parameters),
    do: invalid_option(:filter_parameters, :invalid_phoenix_configuration)

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
    if text_contains_pii?(scalar_text(value), value_entities(key_entities)),
      do: @filtered,
      else: value
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

  defp text_contains_pii?(text, entities) do
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
    match?({:ok, _budget}, consume_parameter_term(params, {0, 0, 0, 0, 0}, :standard))
  end

  defp realtime_parameter_budget_safe?(params) do
    case consume_parameter_term(params, {0, 0, 0, 0, 0}, :realtime) do
      {:ok, {_nodes, _keys, key_bytes, value_bytes, _analysis_terms}} ->
        key_bytes + value_bytes <= @max_realtime_parameter_analysis_bytes

      :error ->
        false
    end
  end

  defp consume_parameter_term(
         _term,
         {nodes, keys, key_bytes, value_bytes, analysis_terms},
         _mode
       )
       when nodes >= @max_parameter_nodes or keys > @max_parameter_keys or
              key_bytes > @max_parameter_key_bytes or
              value_bytes > @max_parameter_value_bytes or
              analysis_terms > @max_parameter_analysis_terms,
       do: :error

  defp consume_parameter_term(%{__struct__: module}, budget, _mode) when is_atom(module),
    do: consume_parameter_node(budget)

  defp consume_parameter_term(map, budget, mode) when is_map(map) do
    with {:ok, budget} <- consume_parameter_node(budget) do
      Enum.reduce_while(map, {:ok, budget}, fn entry, acc ->
        consume_parameter_entry(entry, acc, mode)
      end)
    end
  end

  defp consume_parameter_term(list, budget, mode) when is_list(list) do
    with {:ok, budget} <- consume_parameter_node(budget) do
      case bounded_charlist_size(list) do
        {:ok, count, size} -> consume_parameter_charlist(count, size, budget)
        :not_charlist -> consume_parameter_list(list, budget, mode)
        :error -> :error
      end
    end
  end

  defp consume_parameter_term(value, budget, :realtime) when is_binary(value) do
    with {:ok, budget} <- consume_parameter_node(budget),
         {:ok, budget} <- consume_parameter_value(byte_size(value), budget) do
      consume_parameter_analysis(budget)
    end
  end

  defp consume_parameter_term(value, budget, _mode) when is_binary(value) do
    with {:ok, budget} <- consume_parameter_node(budget) do
      consume_parameter_value(byte_size(value), budget)
    end
  end

  defp consume_parameter_term(value, budget, _mode) when is_atom(value) or is_number(value) do
    with {:ok, size} <- bounded_scalar_size(value),
         {:ok, budget} <- consume_parameter_node(budget),
         {:ok, budget} <- consume_parameter_value(size, budget) do
      consume_parameter_analysis(budget)
    end
  end

  defp consume_parameter_term(value, _budget, :realtime) when is_tuple(value), do: :error
  defp consume_parameter_term(_term, budget, _mode), do: consume_parameter_node(budget)

  defp consume_parameter_entry({key, value}, {:ok, budget}, mode) do
    with {:ok, budget} <- consume_parameter_key(key, budget),
         {:ok, budget} <- consume_parameter_term(value, budget, mode) do
      {:cont, {:ok, budget}}
    else
      :error -> {:halt, :error}
    end
  end

  defp consume_parameter_list([], budget, _mode), do: {:ok, budget}

  defp consume_parameter_list([value | rest], budget, mode) do
    with {:ok, budget} <- consume_parameter_term(value, budget, mode) do
      if is_list(rest), do: consume_parameter_list(rest, budget, mode), else: {:ok, budget}
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

  defp consume_parameter_nodes(count, {nodes, keys, key_bytes, value_bytes, analysis_terms}) do
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

  defp consume_parameter_value(size, {nodes, keys, key_bytes, value_bytes, analysis_terms}) do
    budget = {nodes, keys, key_bytes, value_bytes + size, analysis_terms}
    if elem(budget, 3) > @max_parameter_value_bytes, do: :error, else: {:ok, budget}
  end

  defp consume_parameter_analysis({nodes, keys, key_bytes, value_bytes, analysis_terms}) do
    budget = {nodes, keys, key_bytes, value_bytes, analysis_terms + 1}
    if elem(budget, 4) > @max_parameter_analysis_terms, do: :error, else: {:ok, budget}
  end

  defp bounded_key_size(key) when is_binary(key), do: {:ok, byte_size(key)}
  defp bounded_key_size(key) when is_atom(key) or is_number(key), do: bounded_scalar_size(key)
  defp bounded_key_size(_key), do: {:ok, 0}

  defp bounded_scalar_size(value) when is_atom(value),
    do: {:ok, value |> Atom.to_string() |> byte_size()}

  defp bounded_scalar_size(value) when is_integer(value) do
    if value > -@max_numeric_magnitude and value < @max_numeric_magnitude,
      do: {:ok, value |> Integer.to_string() |> byte_size()},
      else: :error
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
  defp flat_charlist?(list), do: Enum.all?(list, &unicode_codepoint?/1)

  defp log_safe_charlist(list, key_entities) do
    if text_contains_pii?(List.to_string(list), value_entities(key_entities)),
      do: @filtered,
      else: list
  end

  defp value_entities(:filter_all), do: :filter_all
  defp value_entities(key_entities), do: [:domain | key_entities]
  defp scalar_text(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar_text(value) when is_number(value), do: to_string(value)

  defp unicode_codepoint?(value) when is_integer(value),
    do: value >= 0 and value <= 0x10FFFF and value not in 0xD800..0xDFFF

  defp unicode_codepoint?(_value), do: false

  defp http_token?(<<>>), do: false
  defp http_token?(method), do: http_token_bytes?(method)
  defp http_token_bytes?(<<>>), do: true

  defp http_token_bytes?(<<byte, rest::binary>>) do
    if http_token_byte?(byte), do: http_token_bytes?(rest), else: false
  end

  defp http_token_byte?(byte)
       when byte in ?0..?9 or byte in ?A..?Z or byte in ?a..?z,
       do: true

  defp http_token_byte?(byte)
       when byte in [?!, ?#, ?$, ?%, ?&, ?', ?*, ?+, ?-, ?., ?^, ?_, ?`, ?|, ?~],
       do: true

  defp http_token_byte?(_byte), do: false

  defp key_entities do
    case Obscura.Profile.fetch(:fast) do
      {:ok, profile} -> {:ok, profile.supported_entities -- [:domain]}
      {:error, reason} -> {:error, reason}
    end
  end
end
