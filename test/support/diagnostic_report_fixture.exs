defmodule Obscura.Test.DiagnosticReportFixture do
  @moduledoc false

  def valid_report do
    %{
      "schema_version" => 1,
      "status" => "complete",
      "profile" => "balanced",
      "experiment" => %{
        "id" => "balanced_canonical_r1",
        "kind" => "instrumented",
        "repetition" => 1,
        "diagnostics_enabled" => true,
        "sample_mode" => "mixed",
        "behavior_changes_allowed" => false
      },
      "datasets" => datasets(),
      "workload" => workload(),
      "stage_diagnostics" => diagnostics(),
      "diagnostic_analysis" => analysis(),
      "instrumentation_overhead" => %{
        "status" => "measured",
        "same_source_commit" => true,
        "same_profile" => true,
        "same_concurrency" => true,
        "same_duration" => true,
        "same_sample_mode" => true,
        "output_probe_match" => true,
        "throughput_delta_ratio" => 0.01,
        "p95_latency_delta_ratio" => 0.01
      },
      "resource_series" => [resource()],
      "resilience" => resilience(),
      "runtime_reuse" => %{
        "normal_runtime_builds" => 1,
        "per_request_rebuild_detected" => false,
        "lifecycle_stage_counts" => %{"model_load" => 1}
      },
      "environment" => %{
        "requested_backend" => "emily",
        "requested_device" => "gpu",
        "emily_fallback" => "raise",
        "backend_proven" => true,
        "fallback_occurred" => false,
        "platform" => "apple_emily"
      },
      "asset_evidence" => assets(),
      "source" => %{"source_commit" => String.duplicate("a", 40), "dirty_worktree" => false}
    }
  end

  defp datasets do
    Enum.map(
      ~w(generated_large_template_heldout synth_dataset_v2_all nemotron_pii_test_subset_all),
      fn id ->
        %{
          "id" => id,
          "sample_count" => 1,
          "sha256" => sha(),
          "sample_ids_sha256" => sha(),
          "selection_sha256" => sha(),
          "entity_policy_sha256" => sha(),
          "scoring_sha256" => sha()
        }
      end
    )
  end

  defp workload do
    %{
      "stop_reason" => "duration",
      "elapsed_ms" => 600_001,
      "requested_duration_ms" => 600_000,
      "concurrency" => 4,
      "completed" => 1,
      "failed" => 0,
      "rejected" => 0,
      "timed_out" => 0,
      "resource_sample_count" => 1,
      "resource_sampling_coverage" => 1.0,
      "dataset_coverage" =>
        Map.new(
          ~w(generated_large_template_heldout synth_dataset_v2_all nemotron_pii_test_subset_all),
          &{&1, %{"requests" => 1}}
        ),
      "output_stability" => %{"stable" => true, "mismatches" => 0},
      "windows" => [%{"index" => 0}]
    }
  end

  defp diagnostics do
    stages =
      Map.new(
        ~w(queue_admission service_total recognizer_execution model_serving conflict_resolution final_assembly),
        &{&1, summary()}
      )

    %{
      "status" => "measured",
      "request_count" => 1,
      "stages" => stages,
      "input" => %{
        "input_bytes" => summary(),
        "token_count" => summary(),
        "model_sequence_length" => summary()
      },
      "model_shapes" => %{
        "tracked_shape_count" => 1,
        "tracking_overflow" => false,
        "sequence_lengths" => [128],
        "first_seen_requests" => 1,
        "repeated_requests" => 1,
        "first_seen_model_ms" => summary(),
        "repeated_model_ms" => summary()
      },
      "unavailable_stages" => %{
        "privacy_filter_attention" => "not_privacy_filter_profile",
        "privacy_filter_moe" => "not_privacy_filter_profile"
      }
    }
  end

  defp analysis do
    %{
      "timeline" => [%{"index" => 0}],
      "correlations" => %{},
      "first_middle_last" => %{"status" => "measured"},
      "observability" => %{},
      "hypotheses" => []
    }
  end

  defp resource do
    %{
      "elapsed_ms" => 0,
      "scheduler_utilization" => 0.1,
      "run_queue" => 0,
      "beam_memory" => %{},
      "gpu_memory" => %{},
      "host" => %{},
      "system" => %{}
    }
  end

  defp resilience do
    %{
      "timeout" => %{"status" => "passed"},
      "overload" => %{"status" => "passed"},
      "serving_crash_recovery" => %{"status" => "passed"},
      "privacy_check" => %{"status" => "passed"}
    }
  end

  defp assets do
    Map.new(
      ~w(generated_large_template_heldout synth_dataset_v2_all nemotron_pii_test_subset_all),
      fn id ->
        {id, %{"source_manifest_sha256" => sha(), "models" => %{}, "asset_hashes" => %{}}}
      end
    )
  end

  defp summary do
    %{"count" => 1, "mean" => 1.0, "p50" => 1.0, "p95" => 1.0, "p99" => 1.0, "max" => 1.0}
  end

  defp sha, do: String.duplicate("a", 64)
end
