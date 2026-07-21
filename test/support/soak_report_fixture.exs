defmodule Obscura.Test.SoakReportFixture do
  @moduledoc false

  def valid_report do
    datasets =
      Enum.with_index(
        ~w(generated_large_template_heldout synth_dataset_v2_all nemotron_pii_test_subset_all)
      )
      |> Enum.map(fn {id, index} ->
        %{
          "id" => id,
          "sample_count" => 10,
          "sha256" => hash(Integer.to_string(index + 1)),
          "sample_ids_sha256" => hash("a"),
          "selection_sha256" => hash("b"),
          "entity_policy_sha256" => hash("c"),
          "scoring_sha256" => hash("d")
        }
      end)

    coverage =
      Map.new(datasets, fn dataset ->
        {dataset["id"], %{"configured_samples" => 10, "requests" => 20}}
      end)

    %{
      "schema_version" => 1,
      "status" => "complete",
      "profile" => "fast",
      "generated_at" => "2026-01-01T00:00:00Z",
      "datasets" => datasets,
      "workload" => %{
        "stop_reason" => "duration",
        "elapsed_ms" => 600_001,
        "requested_duration_ms" => 600_000,
        "sample_interval_ms" => 1_000,
        "concurrency" => 4,
        "worker_count" => 4,
        "completed" => 60,
        "failed" => 0,
        "rejected" => 0,
        "timed_out" => 0,
        "resource_sample_count" => 600,
        "resource_sampling_coverage" => 1.0,
        "windows" => [%{"index" => 0}],
        "dataset_coverage" => coverage,
        "output_stability" => %{
          "stable" => true,
          "mismatches" => 0,
          "probe" => %{"stable" => true}
        }
      },
      "memory_analysis" => %{
        "sample_count" => 600,
        "metrics" => metrics(),
        "request_correlations" => correlations()
      },
      "memory_classification" => %{
        "classification" => "stable_plateau",
        "reasons" => ["rss_and_live_allocator_plateau"]
      },
      "post_soak" => %{
        "before_idle" => %{"rss_bytes" => 1},
        "after_idle" => %{"rss_bytes" => 1},
        "after_gc" => %{"rss_bytes" => 1},
        "after_cache_clear" => %{"rss_bytes" => 1}
      },
      "resilience" => %{
        "timeout" => %{"status" => "passed"},
        "overload" => %{"status" => "passed"},
        "serving_crash_recovery" => %{"status" => "passed"},
        "privacy_check" => %{"status" => "passed"}
      },
      "runtime_reuse" => %{
        "normal_runtime_builds" => 1,
        "per_request_rebuild_detected" => false,
        "lifecycle_stage_counts" => %{}
      },
      "environment" => %{
        "requested_backend" => "beam_cpu",
        "backend_proven" => true,
        "fallback_occurred" => false,
        "platform" => "apple_emily"
      },
      "asset_evidence" =>
        Map.new(datasets, fn dataset ->
          {dataset["id"],
           %{
             "source_manifest_sha256" => hash("e"),
             "models" => %{},
             "asset_hashes" => %{}
           }}
        end),
      "source" => %{
        "dirty_worktree" => false,
        "source_commit" => hash("f")
      }
    }
  end

  defp metrics do
    Map.new(
      ~w(beam_total os_rss emily_active emily_cache in_flight mailbox_length),
      &{&1, measured_metric()}
    )
  end

  defp measured_metric do
    %{
      "status" => "measured",
      "baseline" => 1,
      "final" => 1,
      "absolute_growth" => 0,
      "full_regression" => %{"status" => "measured"},
      "final_half_regression" => %{"status" => "measured"},
      "rolling_median" => %{"count" => 1}
    }
  end

  defp correlations do
    Map.new(~w(beam_total os_rss emily_active emily_cache), fn metric ->
      {metric, %{"status" => "measured", "coefficient" => 0.1}}
    end)
  end

  defp hash(character), do: String.duplicate(character, 64)
end
