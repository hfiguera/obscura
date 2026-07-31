defmodule Obscura.Phoenix.PlugTest do
  use ExUnit.Case, async: true

  alias Obscura.Phoenix.Plug, as: ObscuraPlug

  import Plug.Test

  test "assign mode stores redacted params without mutating original params" do
    conn =
      :post
      |> conn("/", %{email: "jane@example.com"})
      |> ObscuraPlug.call(fields: [:params], entities: [:email])

    assert conn.params["email"] == "jane@example.com"
    assert conn.assigns.obscura_redacted.params["email"] == "[EMAIL]"
  end

  test "replace mode replaces configured fields" do
    conn =
      :post
      |> conn("/", %{email: "jane@example.com"})
      |> ObscuraPlug.call(fields: [:params], mode: :replace, entities: [:email])

    assert conn.params["email"] == "[EMAIL]"
  end

  test "init normalizes integration defaults and direct calls remain compatible" do
    opts = ObscuraPlug.init(entities: [:email], telemetry: false)

    assert opts[:mode] == :assign_redacted
    assert opts[:fields] == [:params]
    assert opts[:assign] == :obscura_redacted
    assert opts[:telemetry] == false

    conn =
      :post
      |> conn("/", %{email: "jane@example.com"})
      |> ObscuraPlug.call(entities: [:email], telemetry: false)

    assert conn.assigns.obscura_redacted.params["email"] == "[EMAIL]"
  end

  test "init rejects invalid integration configuration before requests run" do
    invalid_options = [
      [mode: :typo],
      [fields: :params],
      [fields: [:unsupported]],
      [assign: "obscura_redacted"],
      [telemetry: :enabled]
    ]

    for opts <- invalid_options do
      assert_raise ArgumentError, ~r/invalid Obscura.Phoenix.Plug option/, fn ->
        ObscuraPlug.init(opts)
      end
    end
  end

  test "init removes duplicate fields while preserving their order" do
    opts = ObscuraPlug.init(fields: [:req_headers, :params, :req_headers])

    assert opts[:fields] == [:req_headers, :params]
  end

  test "init validates redaction configuration without running a request" do
    assert_raise ArgumentError,
                 "invalid Obscura.Phoenix.Plug option :redaction: contains invalid redaction options",
                 fn ->
                   ObscuraPlug.init(max_depth: -1)
                 end

    assert_raise ArgumentError,
                 "invalid Obscura.Phoenix.Plug option :redaction: contains invalid redaction options",
                 fn ->
                   ObscuraPlug.init(profile: :unknown_profile)
                 end
  end

  test "request headers use the same initialized redaction configuration" do
    conn =
      :get
      |> conn("/")
      |> Plug.Conn.put_req_header("x-contact", "jane@example.com")
      |> ObscuraPlug.call(fields: [:req_headers], entities: [:email])

    assert conn.req_headers == [{"x-contact", "jane@example.com"}]
    assert conn.assigns.obscura_redacted.req_headers["x-contact"] == "[EMAIL]"
  end
end
