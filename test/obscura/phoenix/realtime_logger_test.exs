defmodule Obscura.Phoenix.RealtimeLoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  alias Obscura.Internal.PhoenixLog
  alias Obscura.Phoenix.ChannelLogger
  alias Obscura.Phoenix.SocketLogger

  defmodule ProtocolPayload do
    defstruct [:observer, :secret]
  end

  defimpl Obscura.Redactable, for: ProtocolPayload do
    def redact(value, _opts) do
      send(value.observer, {:redactable_called, value.secret})
      {:ok, %{"callback_output" => value.secret}, []}
    end
  end

  defmodule RoomChannel do
    use Phoenix.Channel, log_join: :info, log_handle_in: :info

    @impl true
    def join(_topic, _params, socket), do: {:ok, socket}

    @impl true
    def handle_in("new_message", _params, socket), do: {:reply, :ok, socket}

    def handle_in("metadata_test", _params, socket) do
      :ok =
        :logger.set_process_metadata(%{
          request_id: "logger-metadata-secret@example.test"
        })

      {:reply, :ok, socket}
    end

    def handle_in(_event, _params, socket), do: {:reply, :ok, socket}
  end

  defmodule JoinAssignChannel do
    use Phoenix.Channel, log_join: :info, log_handle_in: :info

    @chat_id "43ad7b8f-b62c-4e1b-8349-8c8ea0a72362"

    @impl true
    def join(_topic, _params, socket), do: {:ok, assign(socket, :chat_id, @chat_id)}

    @impl true
    def handle_in("new_message", _params, socket), do: {:reply, :ok, socket}
  end

  defmodule WarnChannel do
    use Phoenix.Channel, log_join: :warn, log_handle_in: :warn

    @impl true
    def join(_topic, _params, socket), do: {:ok, socket}

    @impl true
    def handle_in("new_message", _params, socket), do: {:reply, :ok, socket}
  end

  defmodule UserSocket do
    use Phoenix.Socket

    channel("room:*", RoomChannel)
    channel("join-assign:*", JoinAssignChannel)
    channel("warn-room:*", WarnChannel)

    @impl true
    def connect(_params, socket, _connect_info), do: {:ok, socket}

    @impl true
    def id(_socket), do: nil
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :obscura

    socket("/socket", UserSocket,
      websocket: true,
      longpoll: false
    )
  end

  import Phoenix.ChannelTest

  @endpoint Endpoint

  setup_all do
    {:ok, _applications} = Application.ensure_all_started(:phoenix_pubsub)
    previous_endpoint = Application.fetch_env(:obscura, Endpoint)

    Application.put_env(:obscura, Endpoint,
      secret_key_base: String.duplicate("a", 64),
      pubsub_server: Obscura.Phoenix.RealtimeLoggerTest.PubSub,
      server: false
    )

    start_supervised!({Phoenix.PubSub, name: Obscura.Phoenix.RealtimeLoggerTest.PubSub})
    start_supervised!(Endpoint)

    on_exit(fn ->
      case previous_endpoint do
        {:ok, value} -> Application.put_env(:obscura, Endpoint, value)
        :error -> Application.delete_env(:obscura, Endpoint)
      end
    end)

    :ok
  end

  setup do
    previous_filter_parameters = Application.fetch_env(:phoenix, :filter_parameters)
    Application.delete_env(:phoenix, :filter_parameters)

    on_exit(fn ->
      case previous_filter_parameters do
        {:ok, value} -> Application.put_env(:phoenix, :filter_parameters, value)
        :error -> Application.delete_env(:phoenix, :filter_parameters)
      end
    end)

    :ok
  end

  test "real Phoenix socket connections omit params and connect info" do
    start_socket_logger()

    log =
      capture_log(fn ->
        result =
          connect(
            UserSocket,
            %{"email" => "socket-secret@example.test"},
            connect_info: %{
              peer_data: %{address: {127, 0, 0, 1}},
              x_headers: [{"x-secret", "connect-info-secret@example.test"}]
            }
          )

        assert {:ok, %Phoenix.Socket{}} = result
      end)

    assert log =~ "CONNECTED TO Obscura.Phoenix.RealtimeLoggerTest.UserSocket"
    assert log =~ "Parameters: [OMITTED]"
    refute log =~ "socket-secret@example.test"
    refute log =~ "connect-info-secret@example.test"
    refute log =~ "peer_data"
  end

  test "socket connection params require explicit bounded fast redaction" do
    start_socket_logger(connect_params: {:redact, entities: [:email]})

    log =
      capture_log(fn ->
        assert {:ok, %Phoenix.Socket{}} =
                 connect(UserSocket, %{
                   "email" => "socket-secret@example.test",
                   "locale" => "en"
                 })
      end)

    assert log =~ ~s("email" => "[EMAIL]")
    assert log =~ ~s("locale" => "en")
    refute log =~ "socket-secret@example.test"
  end

  test "oversized socket parameter graphs fail closed" do
    start_socket_logger(connect_params: {:redact, entities: [:email]})

    log =
      capture_log(fn ->
        assert {:ok, %Phoenix.Socket{}} =
                 connect(UserSocket, %{"body" => String.duplicate("x", 65_537)})
      end)

    assert log =~ "Parameters: [FILTERED]"
    refute log =~ String.duplicate("x", 100)
  end

  test "dense socket parameters over the realtime analysis budget fail closed" do
    start_socket_logger(connect_params: {:redact, entities: [:email]})
    dense = String.duplicate("person@example.test ", 400)

    log =
      capture_log(fn ->
        assert {:ok, %Phoenix.Socket{}} = connect(UserSocket, %{"body" => dense})
      end)

    assert log =~ "Parameters: [FILTERED]"
    refute log =~ "person@example.test"
    refute log =~ "[EMAIL]"
  end

  test "socket drain logs only typed operational fields" do
    start_socket_logger()

    log =
      capture_log(fn ->
        :telemetry.execute(
          [:phoenix, :socket_drain],
          %{count: 4, total: 10, index: 1, rounds: 3},
          %{
            endpoint: :"endpoint-secret@example.test",
            interval: 2_000,
            log: :info,
            socket: UserSocket
          }
        )
      end)

    assert log =~ "DRAINING 4 of 10 total connection(s)"
    assert log =~ "Obscura.Phoenix.RealtimeLoggerTest.UserSocket"
    assert log =~ "every 2000ms - round 1 of 3"
    refute log =~ "endpoint-secret@example.test"
  end

  test "real Phoenix channel joins use configured topic patterns and omit payloads" do
    start_channel_logger(topic_patterns: ["room:*"], events: ["new_message"])

    socket =
      socket(
        UserSocket,
        "socket-id-secret@example.test",
        %{private_secret: "assign-secret@example.test"}
      )

    log =
      capture_log(fn ->
        assert {:ok, %{}, %Phoenix.Socket{}} =
                 subscribe_and_join(
                   socket,
                   RoomChannel,
                   "room:topic-secret@example.test",
                   %{"email" => "join-secret@example.test"}
                 )
      end)

    assert log =~ "JOINED room:*"
    assert log =~ "Obscura.Phoenix.RealtimeLoggerTest.RoomChannel"
    assert log =~ "Parameters: [OMITTED]"
    refute log =~ "topic-secret@example.test"
    refute log =~ "join-secret@example.test"
    refute log =~ "socket-id-secret@example.test"
    refute log =~ "assign-secret@example.test"
  end

  test "deprecated Phoenix warn levels emit as warning for sockets and real channels" do
    assert PhoenixLog.log_level(:warn, :info) == :warning

    start_socket_logger()
    start_channel_logger(topic_patterns: ["warn-room:*"], events: ["new_message"])

    socket_log =
      capture_log(fn ->
        :telemetry.execute(
          [:phoenix, :socket_connected],
          %{duration: 1},
          %{
            log: :warn,
            params: %{},
            result: :ok,
            serializer: Phoenix.Socket.V2.JSONSerializer,
            transport: :websocket,
            user_socket: UserSocket
          }
        )
      end)

    socket = socket(UserSocket, nil, %{})

    channel_log =
      capture_log(fn ->
        assert {:ok, %{}, joined_socket} =
                 subscribe_and_join(socket, WarnChannel, "warn-room:42", %{})

        ref = push(joined_socket, "new_message", %{})
        assert_reply(ref, :ok)
      end)

    assert socket_log =~ "CONNECTED TO Obscura.Phoenix.RealtimeLoggerTest.UserSocket"
    assert channel_log =~ "JOINED warn-room:*"
    assert channel_log =~ "HANDLED new_message ON warn-room:*"
  end

  test "channel correlation emits only a validated UUID socket assign as metadata" do
    chat_id = "43ad7b8f-b62c-4e1b-8349-8c8ea0a72362"

    start_channel_logger(
      topic_patterns: ["room:*"],
      events: ["new_message"],
      correlation: {:socket_assign, :chat_id, :uuid}
    )

    filter_id = unique_name(:correlation_capture)

    :ok =
      :logger.add_primary_filter(
        filter_id,
        {&__MODULE__.capture_logger_event/2, self()}
      )

    on_exit(fn -> :logger.remove_primary_filter(filter_id) end)

    socket = socket(UserSocket, nil, %{chat_id: chat_id})

    capture_log(fn ->
      assert {:ok, %{}, %Phoenix.Socket{}} =
               subscribe_and_join(socket, RoomChannel, "room:42", %{})
    end)

    assert_receive {:logger_event, %{meta: %{chat_id: ^chat_id}}}

    {:ok, correlation} = PhoenixLog.prepare_correlation({:socket_assign, :chat_id, :uuid})

    assert PhoenixLog.correlation_metadata(
             %{assigns: %{chat_id: "not-a-uuid"}},
             correlation,
             true
           ) ==
             []

    assert PhoenixLog.correlation_metadata(%{assigns: %{chat_id: chat_id}}, correlation, false) ==
             []
  end

  test "join correlation uses the pre-join socket and later events use join assigns" do
    chat_id = "43ad7b8f-b62c-4e1b-8349-8c8ea0a72362"

    start_channel_logger(
      topic_patterns: ["join-assign:*"],
      events: ["new_message"],
      correlation: {:socket_assign, :chat_id, :uuid}
    )

    filter_id = unique_name(:join_assign_correlation_capture)

    :ok =
      :logger.add_primary_filter(
        filter_id,
        {&__MODULE__.capture_logger_event/2, self()}
      )

    on_exit(fn -> :logger.remove_primary_filter(filter_id) end)

    socket = socket(UserSocket, nil, %{})

    token = make_ref()

    capture_log(fn ->
      send(
        self(),
        {token, subscribe_and_join(socket, JoinAssignChannel, "join-assign:42", %{})}
      )
    end)

    assert_receive {:logger_event, %{meta: join_metadata}}
    refute Map.has_key?(join_metadata, :chat_id)
    assert_receive {^token, {:ok, %{}, %Phoenix.Socket{} = joined_socket}}

    capture_log(fn ->
      ref = push(joined_socket, "new_message", %{})
      assert_reply(ref, :ok)
    end)

    assert_receive {:logger_event, %{meta: %{chat_id: ^chat_id}}}
  end

  test "disabled channel events do not evaluate correlation metadata" do
    {:ok, correlation} =
      PhoenixLog.prepare_correlation({:socket_assign, :chat_id, :uuid})

    socket = %{
      topic: "room:42",
      channel: RoomChannel,
      private: %{log_handle_in: false},
      assigns: %{chat_id: "43ad7b8f-b62c-4e1b-8349-8c8ea0a72362"}
    }

    config = %{
      correlation: correlation,
      events: %{"new_message" => "new_message"},
      handle_in_params: %{mode: :omit},
      handler_id: make_ref(),
      join_params: %{mode: :omit},
      owner: self(),
      topic_patterns: [{:prefix, "room:", "room:*"}]
    }

    :erlang.trace(self(), true, [:call])
    :erlang.trace_pattern({PhoenixLog, :correlation_metadata, 3}, true, [:local])

    try do
      assert :ok =
               ChannelLogger.handle_event(
                 [:phoenix, :channel_handled_in],
                 %{duration: 1},
                 %{event: "new_message", params: %{}, socket: socket},
                 config
               )

      refute_receive {:trace, _, :call, {PhoenixLog, :correlation_metadata, _}}
    after
      :erlang.trace_pattern({PhoenixLog, :correlation_metadata, 3}, false, [:local])
      :erlang.trace(self(), false, [:call])
    end
  end

  test "real Phoenix channel messages allow configured events and omit payloads" do
    start_channel_logger(topic_patterns: ["room:*"], events: ["new_message"])
    socket = joined_socket()

    log =
      capture_log(fn ->
        ref = push(socket, "new_message", %{"email" => "message-secret@example.test"})
        assert_reply(ref, :ok)
      end)

    assert log =~ "HANDLED new_message ON room:*"
    assert log =~ "Parameters: [OMITTED]"
    refute log =~ "message-secret@example.test"
  end

  test "allow-listed event labels do not retain client-frame binaries" do
    configured_event = :binary.copy("e", 100)
    source = :binary.copy("x", 1_000_000) <> configured_event
    incoming_event = binary_part(source, 1_000_000, byte_size(configured_event))

    assert :binary.referenced_byte_size(incoming_event) > byte_size(incoming_event)

    start_channel_logger(topic_patterns: ["room:*"], events: [configured_event])

    filter_id = unique_name(:event_ownership_capture)

    :ok =
      :logger.add_primary_filter(
        filter_id,
        {&__MODULE__.capture_logger_event/2, self()}
      )

    on_exit(fn -> :logger.remove_primary_filter(filter_id) end)

    capture_log(fn ->
      :telemetry.execute(
        [:phoenix, :channel_handled_in],
        %{duration: 1},
        %{
          event: incoming_event,
          params: %{},
          socket: %{
            channel: RoomChannel,
            private: %{log_handle_in: :info},
            topic: "room:42"
          }
        }
      )
    end)

    assert_receive {:logger_event,
                    %{msg: {:string, ["HANDLED ", emitted_event | _message_segments]}}}

    assert emitted_event == configured_event
    refute :erts_debug.same(emitted_event, incoming_event)
    assert :binary.referenced_byte_size(emitted_event) == byte_size(emitted_event)
  end

  test "configured topic patterns do not retain larger source binaries" do
    pattern = "room:" <> String.duplicate("a", 94) <> "*"
    source = String.duplicate("x", 1_000_000) <> pattern
    borrowed_pattern = binary_part(source, 1_000_000, byte_size(pattern))

    assert :binary.referenced_byte_size(borrowed_pattern) > byte_size(borrowed_pattern)

    assert {:ok, [{:prefix, prefix, configured_pattern}] = patterns} =
             PhoenixLog.prepare_topic_patterns([borrowed_pattern])

    assert configured_pattern == pattern
    refute :erts_debug.same(configured_pattern, borrowed_pattern)
    assert :binary.referenced_byte_size(configured_pattern) == byte_size(configured_pattern)
    assert :binary.referenced_byte_size(prefix) <= byte_size(configured_pattern)
    assert PhoenixLog.safe_topic(String.trim_trailing(pattern, "*") <> "42", patterns) == pattern
  end

  test "unconfigured event names and topics fail closed" do
    start_channel_logger(topic_patterns: ["safe:*"], events: ["new_message"])
    socket = joined_socket("room:topic-secret@example.test")

    log =
      capture_log(fn ->
        ref = push(socket, "event-secret@example.test", %{})
        assert_reply(ref, :ok)
      end)

    assert log =~ "HANDLED [FILTERED EVENT] ON [FILTERED TOPIC]"
    refute log =~ "event-secret@example.test"
    refute log =~ "topic-secret@example.test"
  end

  test "oversized raw topics fail closed before configured pattern matching" do
    {:ok, patterns} = PhoenixLog.prepare_topic_patterns(["room:*"])
    oversized_topic = "room:" <> :binary.copy("x", 1_000_000)

    assert PhoenixLog.safe_topic("room:42", patterns) == "room:*"
    assert PhoenixLog.safe_topic(oversized_topic, patterns) == "[FILTERED TOPIC]"
  end

  test "channel payload redaction is explicit and bounded" do
    start_channel_logger(
      topic_patterns: ["room:*"],
      events: ["new_message"],
      join_params: {:redact, entities: [:email]},
      handle_in_params: {:redact, entities: [:email]}
    )

    socket = socket(UserSocket, nil, %{})
    token = make_ref()

    join_log =
      capture_log(fn ->
        result =
          subscribe_and_join(socket, RoomChannel, "room:42", %{
            "email" => "join-secret@example.test",
            "kind" => "support"
          })

        send(self(), {token, result})
      end)

    assert_receive {^token, {:ok, %{}, socket}}
    assert join_log =~ ~s("email" => "[EMAIL]")
    assert join_log =~ ~s("kind" => "support")
    refute join_log =~ "join-secret@example.test"

    log =
      capture_log(fn ->
        ref =
          push(socket, "new_message", %{
            "email" => "message-secret@example.test",
            "body" => "hello"
          })

        assert_reply(ref, :ok)
      end)

    assert log =~ ~s("email" => "[EMAIL]")
    assert log =~ ~s("body" => "hello")
    refute log =~ "message-secret@example.test"
  end

  test "channel payloads over the analysis-term limit fail closed" do
    start_channel_logger(
      topic_patterns: ["room:*"],
      events: ["new_message"],
      handle_in_params: {:redact, entities: [:email]}
    )

    socket = joined_socket()

    log =
      capture_log(fn ->
        ref = push(socket, "new_message", %{"values" => List.duplicate("value", 128)})
        assert_reply(ref, :ok)
      end)

    assert log =~ "Parameters: [FILTERED]"
    refute log =~ ~s("values")
  end

  test "dense channel payloads over the realtime analysis budget fail closed" do
    start_channel_logger(
      topic_patterns: ["room:*"],
      events: ["new_message"],
      handle_in_params: {:redact, entities: [:email]}
    )

    socket = joined_socket()
    dense = String.duplicate("person@example.test ", 400)

    log =
      capture_log(fn ->
        ref = push(socket, "new_message", %{"body" => dense})
        assert_reply(ref, :ok)
      end)

    assert log =~ "HANDLED new_message ON room:*"
    assert log =~ "Parameters: [FILTERED]"
    refute log =~ "person@example.test"
    refute log =~ "[EMAIL]"
  end

  test "real Phoenix channel treats struct parameters as opaque" do
    start_channel_logger(
      topic_patterns: ["room:*"],
      events: ["new_message"],
      handle_in_params: {:redact, entities: [:email]}
    )

    socket = joined_socket()
    secret = String.duplicate("x", 1_000_000) <> "protocol-secret@example.test"
    payload = %{"payload" => %ProtocolPayload{observer: self(), secret: secret}}

    log =
      capture_log(fn ->
        ref = push(socket, "new_message", payload)
        assert_reply(ref, :ok)
      end)

    assert log =~ ~s("payload" => "[FILTERED]")
    refute log =~ "protocol-secret@example.test"
    refute_receive {:redactable_called, _secret}
  end

  test "real Phoenix channel rejects keyword-list parameters before redaction" do
    start_channel_logger(
      topic_patterns: ["room:*"],
      events: ["new_message"],
      handle_in_params: {:redact, entities: [:email]}
    )

    socket = joined_socket()
    dense = String.duplicate("person@example.test ", 3_000)

    log =
      capture_log(fn ->
        ref = push(socket, "new_message", body: dense)
        assert_reply(ref, :ok)
      end)

    assert log =~ "Parameters: [FILTERED]"
    refute log =~ "person@example.test"
    refute log =~ "[EMAIL]"
  end

  test "realtime byte budget rejects dense payloads before structured analysis" do
    {:ok, policy} =
      PhoenixLog.prepare_params_policy(
        {:redact, entities: [:email]},
        limit: 50,
        printable_limit: 500
      )

    accepted = %{"body" => String.duplicate("x", 4_092)}
    rejected = %{"body" => String.duplicate("person@example.test ", 3_000)}
    worker = spawn_link(fn -> render_params_loop(policy) end)

    :erlang.trace(worker, true, [:call, {:tracer, self()}])
    :erlang.trace_pattern({Obscura.Structured, :redact, 2}, true, [])

    try do
      accepted_ref = make_ref()
      send(worker, {:render, self(), accepted_ref, accepted})

      assert_receive {:trace, ^worker, :call, {Obscura.Structured, :redact, _arguments}}
      assert_receive {^accepted_ref, accepted_rendering}
      refute accepted_rendering == "[FILTERED]"

      rejected_ref = make_ref()
      send(worker, {:render, self(), rejected_ref, rejected})

      assert_receive {^rejected_ref, "[FILTERED]"}
      refute_receive {:trace, ^worker, :call, {Obscura.Structured, :redact, _arguments}}

      for params <- [[body: rejected["body"]], %{"payload" => [body: rejected["body"]]}] do
        keyword_ref = make_ref()
        send(worker, {:render, self(), keyword_ref, params})

        assert_receive {^keyword_ref, "[FILTERED]"}
        refute_receive {:trace, ^worker, :call, {Obscura.Structured, :redact, _arguments}}
      end
    after
      :erlang.trace_pattern({Obscura.Structured, :redact, 2}, false, [])
      :erlang.trace(worker, false, [:call])
      send(worker, :stop)
    end
  end

  test "realtime redaction rejects opaque map keys before structured analysis" do
    {:ok, policy} =
      PhoenixLog.prepare_params_policy(
        {:redact, entities: [:email]},
        limit: 50,
        printable_limit: 500
      )

    worker = spawn_link(fn -> render_params_loop(policy) end)

    :erlang.trace(worker, true, [:call, {:tracer, self()}])
    :erlang.trace_pattern({Obscura.Structured, :redact, 2}, true, [])

    try do
      opaque_params = [
        %{{:opaque, "tuple-key-secret@example.test"} => "safe"},
        %{%ProtocolPayload{observer: self(), secret: "struct-key-secret@example.test"} => "safe"}
      ]

      for params <- opaque_params do
        render_ref = make_ref()
        send(worker, {:render, self(), render_ref, params})

        assert_receive {^render_ref, "[FILTERED]"}
        refute_receive {:trace, ^worker, :call, {Obscura.Structured, :redact, _arguments}}
      end
    after
      :erlang.trace_pattern({Obscura.Structured, :redact, 2}, false, [])
      :erlang.trace(worker, false, [:call])
      send(worker, :stop)
    end

    refute_receive {:redactable_called, _secret}
  end

  test "realtime redaction keeps structs opaque without protocol dispatch" do
    {:ok, policy} =
      PhoenixLog.prepare_params_policy(
        {:redact, entities: [:email]},
        limit: 50,
        printable_limit: 500
      )

    secret = String.duplicate("x", 1_000_000) <> "injected-secret@example.test"
    payload = %ProtocolPayload{observer: self(), secret: secret}

    assert PhoenixLog.render_params(%{"payload" => payload}, policy) ==
             ~s(%{"payload" => "[FILTERED]"})

    refute_receive {:redactable_called, _secret}
  end

  test "channel logging excludes metadata inherited from the channel process" do
    start_channel_logger(topic_patterns: ["room:*"], events: ["metadata_test"])
    socket = joined_socket()

    log =
      capture_log(fn ->
        ref = push(socket, "metadata_test", %{})
        assert_reply(ref, :ok)
      end)

    assert log =~ "HANDLED metadata_test ON room:*"
    refute log =~ "logger-metadata-secret@example.test"
    refute log =~ "request_id"
  end

  test "Phoenix internal topics and disabled channel levels remain silent" do
    start_channel_logger(topic_patterns: ["phoenix:*"], events: ["heartbeat"])

    log =
      capture_log(fn ->
        :telemetry.execute(
          [:phoenix, :channel_handled_in],
          %{duration: 10},
          %{
            event: "heartbeat",
            params: %{},
            socket: %{
              channel: RoomChannel,
              private: %{log_handle_in: :info},
              topic: "phoenix:heartbeat"
            }
          }
        )

        :telemetry.execute(
          [:phoenix, :channel_handled_in],
          %{duration: 10},
          %{
            event: "heartbeat",
            params: %{},
            socket: %{
              channel: RoomChannel,
              private: %{log_handle_in: false},
              topic: "room:42"
            }
          }
        )
      end)

    assert log == ""
  end

  test "malformed telemetry metadata cannot detach either handler" do
    start_socket_logger()
    start_channel_logger(topic_patterns: ["room:*"], events: ["new_message"])

    capture_log(fn ->
      :telemetry.execute(
        [:phoenix, :socket_connected],
        %{duration: "duration-secret@example.test"},
        %{params: fn -> "opaque-secret@example.test" end, log: :info}
      )

      :telemetry.execute(
        [:phoenix, :channel_handled_in],
        %{duration: :invalid},
        %{
          event: "event-secret@example.test",
          params: fn -> "opaque-secret@example.test" end,
          socket: %{private: %{log_handle_in: :info}, topic: <<255>>}
        }
      )
    end)

    log =
      capture_log(fn ->
        assert {:ok, %Phoenix.Socket{}} = connect(UserSocket, %{})
      end)

    assert log =~ "CONNECTED TO Obscura.Phoenix.RealtimeLoggerTest.UserSocket"
  end

  test "realtime payload policies reject model profiles and custom callbacks" do
    assert {:error, {:invalid_option, :params, :fast_profile_required}} =
             isolated_start(fn ->
               SocketLogger.start_link(
                 name: unique_name(:invalid_profile),
                 connect_params: {:redact, profile: :balanced}
               )
             end)

    assert {:error, {:invalid_option, :recognizers, :unsupported_realtime_redaction_option}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:invalid_recognizer),
                 join_params: {:redact, recognizers: [RoomChannel]}
               )
             end)

    assert {:error, {:invalid_option, :operators, :unsupported_realtime_redaction_option}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:invalid_operator),
                 handle_in_params: {:redact, operators: %{default: %{type: :custom}}}
               )
             end)
  end

  test "invalid Phoenix filter patterns fail startup without exposing their values" do
    secret = "filter-secret@example.test"
    Application.put_env(:phoenix, :filter_parameters, [secret, ""])

    results = [
      isolated_start(fn ->
        SocketLogger.start_link(
          name: unique_name(:invalid_socket_filter),
          connect_params: {:redact, entities: [:email]}
        )
      end),
      isolated_start(fn ->
        ChannelLogger.start_link(
          name: unique_name(:invalid_channel_filter),
          join_params: {:redact, entities: [:email]}
        )
      end)
    ]

    for result <- results do
      assert result ==
               {:error, {:invalid_option, :filter_parameters, :invalid_phoenix_configuration}}

      refute inspect(result, limit: :infinity) =~ secret
    end
  end

  test "unsafe configured topic patterns and event names are rejected" do
    assert {:error, {:invalid_option, :topic_patterns, :invalid_pattern}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:invalid_topic),
                 topic_patterns: ["room:secret@example.test"]
               )
             end)

    assert {:error, {:invalid_option, :topic_patterns, :invalid_pattern}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:multiple_wildcards),
                 topic_patterns: ["room:**"]
               )
             end)

    assert {:error, {:invalid_option, :events, :invalid_event}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:invalid_event),
                 events: ["secret@example.test"]
               )
             end)

    assert {:error, {:invalid_option, :events, :invalid_event}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:control_event),
                 events: [<<0xC2, 0x9B>>]
               )
             end)

    for {suffix, label} <- [
          newline: "safe\nINJECTED",
          carriage_return: "safe\rINJECTED",
          tab: "safe\tINJECTED",
          escape: "safe\e[31m",
          bidi_override: "safe\u202Etxt",
          zero_width: "safe\u200Btxt",
          line_separator: "safe\u2028txt"
        ] do
      assert {:error, {:invalid_option, :events, :invalid_event}} =
               isolated_start(fn ->
                 ChannelLogger.start_link(
                   name: unique_name(:"control_event_#{suffix}"),
                   events: [label]
                 )
               end)

      assert {:error, {:invalid_option, :topic_patterns, :invalid_pattern}} =
               isolated_start(fn ->
                 ChannelLogger.start_link(
                   name: unique_name(:"control_topic_#{suffix}"),
                   topic_patterns: [label]
                 )
               end)
    end

    assert {:error, {:invalid_option, :correlation, :expected_omit_or_socket_assign}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:invalid_correlation),
                 correlation: {:socket_assign, :chat_id, :text}
               )
             end)

    assert {:error, {:invalid_option, :correlation, :invalid_metadata_key}} =
             isolated_start(fn ->
               ChannelLogger.start_link(
                 name: unique_name(:reserved_correlation),
                 correlation: {:socket_assign, :gl, :uuid}
               )
             end)

    for key <- [
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
        ] do
      assert {:error, {:invalid_option, :correlation, :invalid_metadata_key}} =
               PhoenixLog.prepare_correlation({:socket_assign, key, :uuid})
    end

    assert {:error, {:invalid_option, :correlation, :invalid_metadata_key}} =
             PhoenixLog.prepare_correlation({:socket_assign, :"4111111111111111", :uuid})
  end

  test "startup refuses to coexist with Phoenix's raw socket logger" do
    event = [:phoenix, :socket_connected]
    handler_id = {Phoenix.Logger, event}
    :telemetry.detach(handler_id)

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.discard_telemetry_event/4,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, {:unsafe_phoenix_logger_attached, ^event}} =
             isolated_start(fn ->
               SocketLogger.start_link(name: unique_name(:unsafe_default_logger))
             end)
  end

  defp isolated_start(fun) do
    caller = self()
    token = make_ref()

    {_pid, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        send(caller, {token, fun.()})
      end)

    assert_receive {^token, result}
    assert_receive {:DOWN, ^monitor, :process, _pid, :normal}
    result
  end

  defp joined_socket(topic \\ "room:42", params \\ %{}) do
    socket = socket(UserSocket, nil, %{private_secret: "assign-secret@example.test"})
    token = make_ref()

    capture_log(fn ->
      send(self(), {token, subscribe_and_join(socket, RoomChannel, topic, params)})
    end)

    assert_receive {^token, {:ok, %{}, socket}}
    socket
  end

  defp start_socket_logger(opts \\ []) do
    name = unique_name(:socket_logger)
    start_supervised!({SocketLogger, Keyword.put(opts, :name, name)})
  end

  defp start_channel_logger(opts) do
    name = unique_name(:channel_logger)
    start_supervised!({ChannelLogger, Keyword.put(opts, :name, name)})
  end

  defp render_params_loop(policy) do
    receive do
      {:render, caller, reference, params} ->
        send(caller, {reference, PhoenixLog.render_params(params, policy)})
        render_params_loop(policy)

      :stop ->
        :ok
    end
  end

  defp unique_name(prefix),
    do: String.to_atom("#{prefix}_#{System.unique_integer([:positive])}")

  @doc false
  def discard_telemetry_event(_event, _measurements, _metadata, _config), do: :ok

  @doc "Forwards Logger events to the test process without modifying them."
  def capture_logger_event(event, test_pid) do
    send(test_pid, {:logger_event, event})
    event
  end
end
