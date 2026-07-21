defmodule Obscura.Eval.Operational.LoadRunnerTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Result
  alias Obscura.Eval.Operational.LoadRunner
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Profile.Runtime

  test "reports bounded repetitions and fingerprints without retaining values" do
    runtime = %Runtime{
      profile: :fast,
      implementation_profile: :deterministic_plus,
      resources: %{},
      analyzer_options: [],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{}
    }

    analyzer = fn _input, _opts ->
      {:ok,
       [
         %Result{
           entity: :email,
           start: 0,
           end: 4,
           byte_start: 0,
           byte_end: 4,
           score: 1.0,
           text: "secret@example.com"
         }
       ]}
    end

    {:ok, host} = RuntimeHost.start_link(runtime: runtime, analyzer: analyzer)
    samples = [%{id: 1, text: "secret@example.com"}, %{id: 2, text: "other-secret"}]

    report = LoadRunner.run(host, samples, concurrency: 2, repetitions: 2)
    encoded = Jason.encode!(report)

    assert report.repetition_count == 2
    assert report.completed == 4
    assert report.stable_output
    assert report.latency_ms.p99 > 0
    refute encoded =~ "secret"
    refute encoded =~ "example.com"
  end

  test "sustained load uses a fixed bounded worker set" do
    runtime = %Runtime{
      profile: :fast,
      implementation_profile: :deterministic_plus,
      resources: %{},
      analyzer_options: [],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{}
    }

    {:ok, host} =
      RuntimeHost.start_link(runtime: runtime, analyzer: fn _input, _opts -> {:ok, []} end)

    report =
      LoadRunner.sustained(host, [%{id: 1, text: "private"}],
        concurrency: 2,
        duration_ms: 100
      )

    assert report.worker_count == 2
    assert report.completed > 0
    assert report.failed == 0
    assert report.elapsed_ms >= 100
    refute Jason.encode!(report) =~ "private"

    capped =
      LoadRunner.sustained(host, [%{id: 1, text: "private"}],
        concurrency: 2,
        duration_ms: 1_000,
        request_count: 2
      )

    assert capped.completed == 2
    assert capped.stop_reason == :request_limit
  end
end
