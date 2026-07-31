defmodule Obscura.Phoenix.LoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias Obscura.Phoenix.Logger, as: ObscuraLogger
  alias Obscura.Phoenix.Plug, as: ObscuraPlug

  defmodule Controller do
    import Plug.Conn

    def init(action), do: action
    def call(conn, :create), do: send_resp(conn, 204, "")
  end

  defmodule Router do
    use Phoenix.Router

    post("/users/:id", Controller, :create)
    match(:*, "/any", Controller, :create, log: :warning)
  end

  defmodule Pipeline do
    use Plug.Builder

    plug(Plug.Parsers, parsers: [:urlencoded])

    plug(Obscura.Phoenix.Plug,
      mode: :assign_redacted,
      fields: [:params],
      entities: [:email]
    )

    plug(Router)
  end

  def disabled_log_level(_conn), do: false

  def failing_log_level(conn) do
    raise "log level failed for #{conn.request_path}"
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

    name = :"obscura_phoenix_logger_#{System.unique_integer([:positive])}"
    pid = start_supervised!({ObscuraLogger, name: name})
    %{logger_name: name, logger_pid: pid}
  end

  test "logs only the pre-redacted assign without mutating controller params" do
    conn =
      :post
      |> conn("/users", %{
        "email" => "jane@example.com",
        "password" => "secret-marker"
      })
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        entities: [:email]
      )

    assert conn.params["email"] == "jane@example.com"
    assert conn.params["password"] == "secret-marker"

    log =
      capture_log(fn ->
        emit_router_dispatch(conn)
      end)

    assert log =~ ~s("email" => "[EMAIL]")
    assert log =~ ~s("password" => "[REDACTED]")
    refute log =~ "jane@example.com"
    refute log =~ "secret-marker"
  end

  test "fails closed when the redacted assign is missing" do
    conn = conn(:post, "/users", %{"email" => "jane@example.com"})

    log =
      capture_log(fn ->
        emit_router_dispatch(conn)
      end)

    assert log =~ "Parameters: \"[FILTERED]\""
    refute log =~ "jane@example.com"
  end

  test "uses the route template instead of the raw request path" do
    conn =
      :get
      |> conn("/users/jane@example.com")
      |> assign(:obscura_redacted, %{params: %{"id" => "[EMAIL]"}})

    log =
      capture_log(fn ->
        emit_router_dispatch(conn, "/users/:id")
      end)

    assert log =~ "Processing GET with /users/:id"
    refute log =~ "/users/jane@example.com"
  end

  test "does not log exception reasons" do
    log =
      capture_log(fn ->
        :telemetry.execute(
          [:phoenix, :error_rendered],
          %{duration: 10},
          %{
            kind: :error,
            reason: RuntimeError.exception("jane@example.com"),
            status: 500,
            log: :warning
          }
        )
      end)

    assert log =~ "Converted error to 500 response"
    refute log =~ "jane@example.com"
  end

  test "filters opaque multipart upload structs before inspecting params" do
    upload = %Plug.Upload{
      path: "/tmp/jane@example.com",
      filename: "jane@example.com.pdf",
      content_type: "application/pdf"
    }

    conn =
      :post
      |> conn("/upload", %{"document" => upload})
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        entities: [:email]
      )

    log = capture_log(fn -> emit_router_dispatch(conn, "/upload") end)

    assert log =~ ~s("document" => "[FILTERED]")
    refute log =~ "jane@example.com"
    refute log =~ "/tmp/"
    refute log =~ "%Plug.Upload{"
  end

  test "filters opaque tuples and character lists left unchanged by structured redaction" do
    params = %{
      "charlist" => ~c"charlist-secret@example.com",
      "domain_charlist" => ~c"private.example",
      "tuple" => {"tuple-secret@example.com"}
    }

    conn =
      :post
      |> conn("/users", params)
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        profile: :fast,
        entities: [:email]
      )

    assert conn.assigns.obscura_redacted.params == params

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ ~s("charlist" => "[FILTERED]")
    assert log =~ ~s("domain_charlist" => "[FILTERED]")
    assert log =~ ~s("tuple" => "[FILTERED]")
    refute log =~ "charlist-secret@example.com"
    refute log =~ "private.example"
    refute log =~ "tuple-secret@example.com"
  end

  test "preserves ordinary integer arrays for the configured inspect policy" do
    params = %{"ids" => [101, 102, 103], "ports" => [80, 443]}

    conn =
      :post
      |> conn("/users", params)
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        profile: :fast,
        entities: [:email]
      )

    name = :"integer_array_logger_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      ObscuraLogger.start_link(
        name: name,
        inspect_opts: [charlists: :as_lists, limit: :infinity]
      )

    try do
      log = capture_log(fn -> emit_router_dispatch(conn) end)

      assert log =~ ~s("ids" => [101, 102, 103])
      assert log =~ ~s("ports" => [80, 443])
      refute log =~ ~s("ids" => "[FILTERED]")
      refute log =~ ~s("ports" => "[FILTERED]")
    after
      GenServer.stop(pid)
    end
  end

  test "filters PII-bearing scalar values and keys while preserving ordinary scalars" do
    card_number = 4_111_111_111_111_111
    email_atom = :"secret@example.com"

    params = %{
      "card_number" => card_number,
      "count" => 42,
      "email_atom" => email_atom,
      "status" => :approved,
      card_number => "numeric-key-value",
      email_atom => "atom-key-value"
    }

    conn =
      :post
      |> conn("/users", params)
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        profile: :fast,
        entities: [:credit_card, :email]
      )

    assert conn.assigns.obscura_redacted.params["card_number"] == card_number
    assert conn.assigns.obscura_redacted.params["email_atom"] == email_atom

    conn = assign(conn, :obscura_redacted, %{params: params})

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ ~s("card_number" => "[FILTERED]")
    assert log =~ ~s("count" => 42)
    assert log =~ ~s("email_atom" => "[FILTERED]")
    assert log =~ ~s("status" => :approved)
    assert log =~ "numeric-key-value"
    assert log =~ "atom-key-value"
    refute log =~ "4111111111111111"
    refute log =~ "secret@example.com"
  end

  test "does not inherit request-process Logger metadata" do
    previous_metadata = Logger.metadata()

    :ok =
      :logger.set_process_metadata(%{
        user_email: "metadata-secret@example.com",
        request_id: "request-123"
      })

    conn =
      :get
      |> conn("/users")
      |> assign(:obscura_redacted, %{params: %{}})

    try do
      log =
        capture_log(
          [format: "$metadata$message", metadata: [:request_id, :user_email]],
          fn -> emit_router_dispatch(conn) end
        )

      assert log =~ "Processing GET with /users"
      refute log =~ "metadata-secret@example.com"
      refute log =~ "request-123"

      assert Logger.metadata()[:user_email] == "metadata-secret@example.com"
      assert Logger.metadata()[:request_id] == "request-123"
    after
      Logger.reset_metadata(previous_metadata)
    end
  end

  test "checks custom methods from real Phoenix router events" do
    pii_conn =
      "4111111111111111"
      |> conn("/any")
      |> assign(:obscura_redacted, %{params: %{}})

    safe_conn =
      "PROPFIND"
      |> conn("/any")
      |> assign(:obscura_redacted, %{params: %{}})

    extension_conn =
      "M-SEARCH"
      |> conn("/any")
      |> assign(:obscura_redacted, %{params: %{}})

    injected_conn =
      "PROPFIND\nINJECTED"
      |> conn("/any")
      |> assign(:obscura_redacted, %{params: %{}})

    terminal_conn =
      "\e[31mPROPFIND"
      |> conn("/any")
      |> assign(:obscura_redacted, %{params: %{}})

    log =
      capture_log(fn ->
        assert Router.call(pii_conn, Router.init([])).status == 204
        assert Router.call(safe_conn, Router.init([])).status == 204
        assert Router.call(extension_conn, Router.init([])).status == 204
        assert Router.call(injected_conn, Router.init([])).status == 204
        assert Router.call(terminal_conn, Router.init([])).status == 204
      end)

    assert Enum.count(Regex.scan(~r/Processing \[FILTERED METHOD\] with \/any/, log)) == 3
    assert log =~ "Processing PROPFIND with /any"
    assert log =~ "Processing M-SEARCH with /any"
    refute log =~ "4111111111111111"
    refute log =~ "INJECTED"
    refute log =~ "\e[31m"
  end

  test "contains dynamic log-level failures without leaking or detaching the handler", %{
    logger_name: name
  } do
    conn =
      :get
      |> conn("/users/path-secret@example.com")
      |> assign(:obscura_redacted, %{params: %{}})

    previous_metadata = Logger.metadata()
    :ok = :logger.set_process_metadata(%{user_email: "metadata-secret@example.com"})

    try do
      log =
        capture_log(fn ->
          emit_router_dispatch(conn, "/users/:id", {__MODULE__, :failing_log_level, []})
        end)

      assert log == ""
      assert handler_count(name) == 1

      recovered_log = capture_log(fn -> emit_router_dispatch(conn, "/users/:id") end)

      assert recovered_log =~ "Processing GET with /users/:id"
      refute recovered_log =~ "path-secret@example.com"
      refute recovered_log =~ "metadata-secret@example.com"
    after
      Logger.reset_metadata(previous_metadata)
    end
  end

  test "fails closed before key analysis when parameter budgets are exceeded" do
    oversized_integer = String.to_integer(String.duplicate("9", 1_000))

    scenarios = [
      Map.new(1..65, fn index -> {"field_#{index}", "value"} end),
      %{String.duplicate("k", 4_097) => "oversized-key"},
      %{"values" => List.duplicate("value", 128)},
      %{"values" => List.duplicate("value", 1_024)},
      %{"value" => String.duplicate("v", 65_537)},
      %{"value" => oversized_integer},
      %{oversized_integer => "value"},
      %{"values" => List.duplicate(42.0, 128)}
    ]

    parent = self()
    tracer = spawn(fn -> forward_trace(parent) end)

    :erlang.trace(self(), true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Obscura, :redact, 2}, true, [])

    try do
      Enum.each(scenarios, fn params ->
        conn =
          :post
          |> conn("/users", params)
          |> assign(:obscura_redacted, %{params: params})

        log = capture_log(fn -> emit_router_dispatch(conn) end)

        assert log =~ "Parameters: \"[FILTERED]\""
      end)

      refute_receive {:trace, _pid, :call, {Obscura, :redact, _arguments}}, 20
    after
      :erlang.trace_pattern({Obscura, :redact, 2}, false, [])
      :erlang.trace(self(), false, [:call])
      Process.exit(tracer, :kill)
    end
  end

  test "accepts a parameter graph at the key-count boundary" do
    params = Map.new(1..64, fn index -> {"field_#{index}", "value"} end)

    conn =
      :post
      |> conn("/users", params)
      |> assign(:obscura_redacted, %{params: params})

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ "Parameters: %{"
    refute log =~ "Parameters: \"[FILTERED]\""
  end

  test "filters supported PII in parameter keys without changing request data" do
    params = %{
      "jane@example.com" => "first",
      "support@example.com" => "second",
      "nested" => %{"privacy@example.com" => "third"}
    }

    conn =
      :post
      |> conn("/users", params)
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        entities: [:email]
      )

    assert conn.params == params
    assert conn.assigns.obscura_redacted.params == params

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ ~s("[FILTERED KEY )
    assert log =~ ~s("nested" => %{"[FILTERED KEY )
    assert log =~ "first"
    assert log =~ "second"
    assert log =~ "third"
    assert Enum.count(Regex.scan(~r/\[FILTERED KEY \d+\]/, log)) == 3
    refute log =~ "jane@example.com"
    refute log =~ "support@example.com"
    refute log =~ "privacy@example.com"
  end

  test "uses the fast profile key taxonomy without filtering dotted field names" do
    params = %{
      "Address: 123 Main Street" => "address-key",
      "Reviewed on 2026-07-29" => "date-key",
      "api.version" => "version-field",
      "profile.url" => "url-field",
      "user.name" => "name-field"
    }

    conn =
      :post
      |> conn("/users", params)
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        profile: :fast,
        entities: [:street_address, :date_time]
      )

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ ~s("api.version" => "version-field")
    assert log =~ ~s("profile.url" => "url-field")
    assert log =~ ~s("user.name" => "name-field")
    assert log =~ "address-key"
    assert log =~ "date-key"
    refute log =~ "Address: 123 Main Street"
    refute log =~ "Reviewed on 2026-07-29"
  end

  test "does not analyze parameter keys when a dynamic log level returns false" do
    conn =
      :post
      |> conn("/users", %{"jane@example.com" => "safe"})
      |> assign(:obscura_redacted, %{params: %{"jane@example.com" => "safe"}})

    parent = self()
    tracer = spawn(fn -> forward_trace(parent) end)

    :erlang.trace(self(), true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Obscura, :redact, 2}, true, [])

    try do
      log =
        capture_log(fn ->
          emit_router_dispatch(conn, "/users", {__MODULE__, :disabled_log_level, []})
        end)

      assert log == ""
      refute_receive {:trace, _pid, :call, {Obscura, :redact, _arguments}}, 20
    after
      :erlang.trace_pattern({Obscura, :redact, 2}, false, [])
      :erlang.trace(self(), false, [:call])
      Process.exit(tracer, :kill)
    end
  end

  test "applies Phoenix discard filtering after Obscura redaction" do
    Application.put_env(:phoenix, :filter_parameters, ["security_answer"])

    conn =
      :post
      |> conn("/users", %{
        "email" => "jane@example.com",
        "security_answer" => "first-pet-name"
      })
      |> ObscuraPlug.call(
        mode: :assign_redacted,
        fields: [:params],
        entities: [:email]
      )

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ ~s("email" => "[EMAIL]")
    assert log =~ ~s("security_answer" => "[FILTERED]")
    refute log =~ "jane@example.com"
    refute log =~ "first-pet-name"
  end

  test "supports Phoenix keep filtering" do
    Application.put_env(:phoenix, :filter_parameters, {:keep, ["request_id"]})

    conn =
      :post
      |> conn("/users", %{
        "request_id" => "visible-id",
        "security_answer" => "first-pet-name"
      })
      |> ObscuraPlug.call(mode: :assign_redacted, fields: [:params])

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ ~s("request_id" => "visible-id")
    assert log =~ ~s("security_answer" => "[FILTERED]")
    refute log =~ "first-pet-name"
  end

  test "fails closed when Phoenix filter configuration is invalid" do
    Application.put_env(:phoenix, :filter_parameters, {:keep, :invalid})

    conn =
      :post
      |> conn("/users", %{"security_answer" => "first-pet-name"})
      |> ObscuraPlug.call(mode: :assign_redacted, fields: [:params])

    log = capture_log(fn -> emit_router_dispatch(conn) end)

    assert log =~ "Parameters: \"[FILTERED]\""
    refute log =~ "first-pet-name"
  end

  test "a supervised restart replaces the stale telemetry handler", %{
    logger_name: name,
    logger_pid: original_pid
  } do
    assert handler_count(name) == 1

    Process.exit(original_pid, :kill)

    replacement_pid =
      eventually(fn ->
        case Process.whereis(name) do
          pid when is_pid(pid) and pid != original_pid -> {:ok, pid}
          _missing -> :retry
        end
      end)

    assert Process.alive?(replacement_pid)
    assert handler_count(name) == 1

    conn =
      :get
      |> conn("/users")
      |> assign(:obscura_redacted, %{params: %{}})

    log = capture_log(fn -> emit_router_dispatch(conn) end)
    assert [_one_log_entry] = Regex.scan(~r/Processing GET with \/users/, log)
  end

  test "a handler self-detaches when its owner terminates without a restart" do
    name = :"temporary_obscura_logger_#{System.unique_integer([:positive])}"

    child = %{
      id: name,
      start: {ObscuraLogger, :start_link, [[name: name]]},
      restart: :temporary
    }

    {:ok, supervisor} = Supervisor.start_link([child], strategy: :one_for_one)
    pid = Process.whereis(name)
    assert handler_count(name) == 1

    Process.exit(pid, :kill)
    eventually(fn -> if Process.alive?(pid), do: :retry, else: {:ok, :stopped} end)

    conn =
      :get
      |> conn("/users")
      |> assign(:obscura_redacted, %{params: %{}})

    _log = capture_log(fn -> emit_router_dispatch(conn) end)
    assert handler_count(name) == 0

    Supervisor.stop(supervisor)
  end

  test "logs redacted params from a real Phoenix router event" do
    conn =
      :post
      |> conn(
        "/users/jane@example.com",
        "email=jane%40example.com&password=secret-marker"
      )
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    log =
      capture_log(fn ->
        response = Pipeline.call(conn, Pipeline.init([]))
        assert response.status == 204
      end)

    assert log =~ "Processing POST with /users/:id"
    assert log =~ ~s("email" => "[EMAIL]")
    assert log =~ ~s("password" => "[REDACTED]")
    refute log =~ "jane@example.com"
    refute log =~ "secret-marker"
  end

  test "rejects invalid stable options during startup" do
    invalid_assign_name = :"invalid_assign_#{System.unique_integer([:positive])}"
    invalid_inspect_name = :"invalid_inspect_#{System.unique_integer([:positive])}"
    unknown_name = :"unknown_option_#{System.unique_integer([:positive])}"
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      assert {:error, {:invalid_option, :assign, :expected_atom}} =
               ObscuraLogger.start_link(name: invalid_assign_name, assign: "redacted")

      assert {:error, {:invalid_option, :inspect_opts, :expected_keyword_list}} =
               ObscuraLogger.start_link(name: invalid_inspect_name, inspect_opts: :invalid)

      assert {:error, {:invalid_option, :unknown, :unknown_option}} =
               ObscuraLogger.start_link(name: unknown_name, unknown: true)
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  defp emit_router_dispatch(conn, route \\ "/users", log_level \\ :warning) do
    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      %{
        conn: conn,
        log: log_level,
        pipe_through: [:api],
        plug: __MODULE__,
        plug_opts: :index,
        route: route
      }
    )
  end

  defp handler_count(name) do
    [:phoenix, :router_dispatch, :start]
    |> :telemetry.list_handlers()
    |> Enum.count(fn
      %{id: {ObscuraLogger, ^name, _generation}} -> true
      _handler -> false
    end)
  end

  defp eventually(fun, attempts \\ 50)

  defp eventually(fun, attempts) when attempts > 0 do
    case fun.() do
      {:ok, result} ->
        result

      :retry ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: flunk("condition did not become true")

  defp forward_trace(parent) do
    receive do
      message -> send(parent, message)
    end
  end
end
