defmodule Obscura.Eval.Operational.SystemProbeTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.SystemProbe

  test "reports measured or explicit unavailable host signals without command output" do
    snapshot = SystemProbe.capture()
    capabilities = SystemProbe.capabilities()

    assert is_number(snapshot.process_cpu_percent) or is_nil(snapshot.process_cpu_percent)
    assert is_integer(snapshot.beam_runtime.process_count)
    assert is_integer(snapshot.beam_runtime.reductions)
    assert snapshot.power.status in [:measured, :unavailable]
    assert snapshot.thermal.status in [:measured, :unavailable]
    assert snapshot.gpu_activity.status in [:measured, :unavailable]
    assert capabilities.gpu_activity.status in [:available, :unavailable]
    refute inspect(snapshot) =~ System.user_home!()
  end
end
