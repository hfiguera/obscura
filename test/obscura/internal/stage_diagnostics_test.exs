defmodule Obscura.Internal.StageDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Obscura.Internal.StageDiagnostics

  test "captures bounded aggregates and approved numeric metadata only" do
    {result, snapshot} =
      StageDiagnostics.capture(true, fn ->
        StageDiagnostics.measure(:model_serving, fn -> :ok end)
        StageDiagnostics.record(:model_serving, 2.5)
        StageDiagnostics.metadata(:input_bytes, 42)
        StageDiagnostics.unavailable(:privacy_filter_moe, :fused_compiled_device_graph)
        :result
      end)

    assert result == :result
    assert snapshot.status == :measured
    assert snapshot.stages.model_serving.count == 2
    assert snapshot.stages.model_serving.total_ms >= 2.5
    assert snapshot.metadata == %{input_bytes: 42}
    assert snapshot.unavailable == %{privacy_filter_moe: :fused_compiled_device_graph}
    refute inspect(snapshot) =~ "private-value"
  end

  test "disabled capture adds no diagnostics" do
    assert {:ok, %{status: :disabled, stages: %{}}} =
             StageDiagnostics.capture(false, fn -> :ok end)
  end
end
