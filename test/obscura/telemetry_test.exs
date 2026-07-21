defmodule Obscura.TelemetryTest do
  use ExUnit.Case, async: false

  test "analyze emits telemetry without raw PII" do
    test_pid = self()
    handler_id = "obscura-test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:obscura, :analyze, :stop],
      fn _event, _measurements, metadata, _config -> send(test_pid, {:metadata, metadata}) end,
      nil
    )

    assert {:ok, _results} = Obscura.analyze("Contact jane@example.com", entities: [:email])
    assert_receive {:metadata, metadata}
    refute Map.has_key?(metadata, :text)
    refute inspect(metadata) =~ "jane@example.com"

    :telemetry.detach(handler_id)
  end
end
