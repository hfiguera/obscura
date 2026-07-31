defmodule Obscura.Phoenix.ChannelLogger do
  @moduledoc """
  Privacy-safe logging for Phoenix channel joins and incoming events.

  This opt-in telemetry handler replaces the channel portion of Phoenix's
  default logger after `config :phoenix, :logger, false` disables it. Raw topics
  and event names are never logged. Applications declare safe topic patterns
  and event names at startup; unmatched values are rendered as filtered labels.
  Oversized topics are filtered before content validation. Join and
  incoming-event parameters are omitted by default.

      children = [
        {Obscura.Phoenix.ChannelLogger,
         topic_patterns: ["room:*", "system"],
         events: ["new_message", "typing"]}
      ]

  A bounded redacted parameter copy can be enabled independently for joins and
  incoming events:

      {Obscura.Phoenix.ChannelLogger,
       topic_patterns: ["room:*"],
       events: ["new_message"],
       join_params: {:redact, entities: [:email, :phone]},
       handle_in_params: {:redact, entities: [:email, :phone]}}

  Applications can opt in to include one validated UUID-valued socket assign
  as Logger metadata, allowing related channel events to be correlated.
  Invalid or missing values are omitted:

      {Obscura.Phoenix.ChannelLogger,
       topic_patterns: ["room:*"],
       events: ["new_message"],
       correlation: {:socket_assign, :chat_id, :uuid}}

  This metadata supports log correlation; it does not create spans, propagate
  trace context, or provide distributed tracing. Logger-reserved, PII-bearing,
  and oversized assign names are rejected at startup.

  Phoenix's join telemetry contains the socket from before `join/3` runs.
  Consequently, a correlation assign must already exist before `join/3` to
  appear on the join record. An assign added by `join/3` is available to later
  handled-event records.

  Only the dependency-light `:fast` profile is accepted in this synchronous
  path. Apart from an explicitly configured correlation assign, the handler
  never inspects socket assigns, private application data, identifiers,
  references, or callback results.
  """

  use GenServer

  alias Obscura.Internal.PhoenixLog

  @events [[:phoenix, :channel_joined], [:phoenix, :channel_handled_in]]

  @allowed_options [
    :correlation,
    :events,
    :handle_in_params,
    :inspect_opts,
    :join_params,
    :name,
    :topic_patterns
  ]

  @doc "Starts the Phoenix channel telemetry handler."
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
         {:ok, topic_patterns} <-
           PhoenixLog.prepare_topic_patterns(Keyword.get(opts, :topic_patterns, [])),
         {:ok, events} <- PhoenixLog.prepare_events(Keyword.get(opts, :events, [])),
         {:ok, correlation} <-
           PhoenixLog.prepare_correlation(Keyword.get(opts, :correlation, :omit)),
         {:ok, join_params} <-
           PhoenixLog.prepare_params_policy(Keyword.get(opts, :join_params, :omit), inspect_opts),
         {:ok, handle_in_params} <-
           PhoenixLog.prepare_params_policy(
             Keyword.get(opts, :handle_in_params, :omit),
             inspect_opts
           ) do
      name = Keyword.get(opts, :name, __MODULE__)
      handler_id = {__MODULE__, name, make_ref()}
      detach_previous_handlers(name)

      config = %{
        correlation: correlation,
        events: events,
        handle_in_params: handle_in_params,
        handler_id: handler_id,
        join_params: join_params,
        owner: self(),
        topic_patterns: topic_patterns
      }

      case :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_event/4, config) do
        :ok -> {:ok, handler_id}
        {:error, reason} -> {:stop, reason}
      end
    else
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
        event,
        measurements,
        metadata,
        %{owner: owner, handler_id: handler_id} = config
      ) do
    PhoenixLog.dispatch(owner, handler_id, fn ->
      dispatch(event, measurements, metadata, config)
    end)
  end

  defp dispatch([:phoenix, :channel_joined], measurements, metadata, config) do
    socket = Map.get(metadata, :socket, %{})

    if internal_topic?(Map.get(socket, :topic)) do
      :ok
    else
      case channel_level(socket, :log_join) do
        false ->
          :ok

        level ->
          correlation_metadata =
            PhoenixLog.correlation_metadata(
              socket,
              config.correlation,
              Map.get(metadata, :result) == :ok
            )

          PhoenixLog.log(
            level,
            fn ->
              [
                join_result(Map.get(metadata, :result)),
                PhoenixLog.safe_topic(Map.get(socket, :topic), config.topic_patterns),
                " (",
                PhoenixLog.safe_identifier(Map.get(socket, :channel)),
                ") in ",
                PhoenixLog.duration(Map.get(measurements, :duration)),
                "\n  Parameters: ",
                PhoenixLog.render_params(Map.get(metadata, :params), config.join_params)
              ]
            end,
            correlation_metadata
          )
      end
    end
  end

  defp dispatch([:phoenix, :channel_handled_in], measurements, metadata, config) do
    socket = Map.get(metadata, :socket, %{})

    if internal_topic?(Map.get(socket, :topic)) do
      :ok
    else
      case channel_level(socket, :log_handle_in) do
        false ->
          :ok

        level ->
          correlation_metadata = PhoenixLog.correlation_metadata(socket, config.correlation, true)

          PhoenixLog.log(
            level,
            fn ->
              [
                "HANDLED ",
                PhoenixLog.safe_event(Map.get(metadata, :event), config.events),
                " ON ",
                PhoenixLog.safe_topic(Map.get(socket, :topic), config.topic_patterns),
                " (",
                PhoenixLog.safe_identifier(Map.get(socket, :channel)),
                ") in ",
                PhoenixLog.duration(Map.get(measurements, :duration)),
                "\n  Parameters: ",
                PhoenixLog.render_params(Map.get(metadata, :params), config.handle_in_params)
              ]
            end,
            correlation_metadata
          )
      end
    end
  end

  defp dispatch(_event, _measurements, _metadata, _config), do: :ok

  defp channel_level(%{private: private}, key) when is_map(private) do
    case Map.get(private, key) do
      nil -> false
      level -> PhoenixLog.log_level(level, :info)
    end
  end

  defp channel_level(_socket, _key), do: false

  defp internal_topic?("phoenix" <> _rest), do: true
  defp internal_topic?(_topic), do: false

  defp join_result(:ok), do: "JOINED "
  defp join_result(:error), do: "REFUSED JOIN "
  defp join_result(_result), do: "CHANNEL JOIN "

  defp detach_previous_handlers(name) do
    PhoenixLog.detach_previous_handlers(@events, __MODULE__, name)
  end
end
