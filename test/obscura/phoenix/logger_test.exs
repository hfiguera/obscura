defmodule Obscura.Phoenix.LoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias Obscura.Phoenix.Logger, as: ObscuraLogger
  alias Obscura.Phoenix.Plug, as: ObscuraPlug

  setup do
    name = :"obscura_phoenix_logger_#{System.unique_integer([:positive])}"
    start_supervised!({ObscuraLogger, name: name})
    :ok
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
end
