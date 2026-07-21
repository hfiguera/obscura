defmodule Obscura.Vault.TelemetryTest do
  use ExUnit.Case, async: false

  alias Obscura.Vault
  alias Obscura.Vault.Memory

  test "vault telemetry omits raw values" do
    test_pid = self()
    handler_id = "obscura-vault-test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:obscura, :vault, :token, :stop],
      fn _event, _measurements, metadata, _config -> send(test_pid, {:metadata, metadata}) end,
      nil
    )

    assert {:ok, vault} = Memory.start_link()
    assert {:ok, _token} = Vault.get_or_create(vault, :email, "jane@example.com")
    assert_receive {:metadata, metadata}
    refute inspect(metadata) =~ "jane@example.com"

    :telemetry.detach(handler_id)
  end
end
