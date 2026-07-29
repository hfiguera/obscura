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

  setup do
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

  defp emit_router_dispatch(conn, route \\ "/users") do
    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      %{
        conn: conn,
        log: :warning,
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
end
