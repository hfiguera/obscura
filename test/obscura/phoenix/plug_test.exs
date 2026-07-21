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
end
