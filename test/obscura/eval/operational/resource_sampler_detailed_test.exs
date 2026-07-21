defmodule Obscura.Eval.Operational.ResourceSamplerDetailedTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.ResourceSampler
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Profile.Runtime

  test "captures detailed BEAM and bounded-host state without request values" do
    runtime = %Runtime{
      profile: :fast,
      implementation_profile: :deterministic_plus,
      resources: %{},
      analyzer_options: [],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{}
    }

    {:ok, host} =
      RuntimeHost.start_link(runtime: runtime, analyzer: fn _text, _opts -> {:ok, []} end)

    {:ok, sampler} =
      ResourceSampler.start_link(
        host: host,
        gpu: false,
        detailed: true,
        interval: 5
      )

    Process.sleep(15)
    [sample | _rest] = ResourceSampler.series(sampler)

    assert is_integer(sample.beam_memory.total)
    assert is_integer(sample.rss_bytes)
    assert sample.host.in_flight == 0
    assert sample.host.message_queue_len >= 0
    refute inspect(sample) =~ "private"
  end
end
