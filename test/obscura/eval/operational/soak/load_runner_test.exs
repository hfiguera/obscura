defmodule Obscura.Eval.Operational.Soak.LoadRunnerTest do
  use ExUnit.Case, async: false

  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.Soak.LoadRunner
  alias Obscura.Internal.StageDiagnostics
  alias Obscura.Profile.Runtime

  test "runs bounded long-lived workers without retaining source values" do
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

    samples = [
      %{id: "a", dataset_id: :generated_large_template_heldout, text: "private-a"},
      %{id: "b", dataset_id: :synth_dataset_v2_all, text: "private-b"},
      %{id: "c", dataset_id: :nemotron_pii_test_subset_all, text: "private-c"}
    ]

    report =
      LoadRunner.run(host, samples,
        duration_ms: 120,
        concurrency: 2,
        timeout: 1_000,
        gpu: false,
        sample_interval: 10,
        window_ms: 50,
        idle_ms: 1,
        gc_settle_ms: 1
      )

    assert report.elapsed_ms >= 120
    assert report.completed > 0
    assert report.worker_count == 2
    assert report.failed == 0
    assert report.rejected == 0
    assert report.timed_out == 0
    assert report.output_stability.stable
    assert report.output_stability.rechecks > 0
    assert report.resource_sample_count >= 2
    assert report.memory_analysis.metrics.os_rss.status == :measured
    assert Enum.all?(report.dataset_coverage, fn {_dataset, row} -> row.requests > 0 end)

    encoded = Jason.encode!(report)
    refute encoded =~ "private-a"
    refute encoded =~ "private-b"
    refute encoded =~ "private-c"
  end

  test "aggregates stage and environmental diagnostics without retaining requests" do
    runtime = %Runtime{
      profile: :balanced,
      implementation_profile: :hybrid_ner_tner_conservative,
      resources: %{},
      analyzer_options: [],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{}
    }

    analyzer = fn _text, _opts ->
      StageDiagnostics.metadata(:token_count, 4)
      StageDiagnostics.metadata(:window_count, 1)
      StageDiagnostics.metadata(:model_sequence_length, 128)
      StageDiagnostics.unavailable(:privacy_filter_attention, :not_privacy_filter_profile)
      StageDiagnostics.unavailable(:privacy_filter_moe, :not_privacy_filter_profile)
      StageDiagnostics.measure(:model_serving, fn -> Process.sleep(1) end)
      {:ok, []}
    end

    {:ok, host} =
      RuntimeHost.start_link(
        runtime: runtime,
        analyzer: analyzer,
        diagnostics: true,
        max_in_flight: 2
      )

    samples = [
      %{id: "a", dataset_id: :generated_large_template_heldout, text: "private-a"},
      %{id: "b", dataset_id: :synth_dataset_v2_all, text: "private-b"},
      %{id: "c", dataset_id: :nemotron_pii_test_subset_all, text: "private-c"}
    ]

    report =
      LoadRunner.run(host, samples,
        duration_ms: 120,
        concurrency: 2,
        timeout: 1_000,
        gpu: false,
        diagnostics: true,
        environmental: true,
        include_resource_series: true,
        sample_interval: 10,
        window_ms: 50,
        idle_ms: 1,
        gc_settle_ms: 1
      )

    assert report.diagnostics.status == :measured
    assert report.diagnostics.stages.model_serving.count > 0
    assert report.diagnostics.stages.queue_admission.count > 0
    assert report.diagnostics.input.input_bytes.count > 0
    assert report.diagnostics.input.token_count.count > 0
    assert report.diagnostics.model_shapes.tracked_shape_count == 1
    assert report.diagnostics.model_shapes.first_seen_requests == 1
    assert report.diagnostics.model_shapes.repeated_requests > 0
    assert is_list(report.resource_series)
    assert Enum.all?(report.resource_series, &is_map(&1.system))

    encoded = Jason.encode!(report)
    refute encoded =~ "private-a"
    refute encoded =~ "private-b"
    refute encoded =~ "private-c"
  end
end
