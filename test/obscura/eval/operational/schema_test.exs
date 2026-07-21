defmodule Obscura.Eval.Operational.SchemaTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Schema
  alias Obscura.PrivacyFilter.OpenMedPolicy

  test "accepts complete fast evidence and rejects raw-value keys" do
    report = valid_report()
    assert :ok = Schema.validate(report)

    assert {:error, {:sensitive_operational_report_key, "text"}} =
             report
             |> Map.put("debug", %{"text" => "private"})
             |> Schema.validate()
  end

  test "rejects incomplete concurrency and accelerator fallback" do
    assert {:error, :incomplete_concurrency_matrix} =
             valid_report()
             |> put_in(["warm_load", "concurrency_results"], [])
             |> Schema.validate()

    balanced =
      valid_report()
      |> Map.put("profile", "balanced")
      |> put_model_assets()
      |> put_in(["environment", "requested_backend"], "emily")
      |> put_in(["environment", "requested_device"], "gpu")
      |> put_in(["environment", "emily_fallback"], "raise")
      |> put_in(["environment", "backend_proven"], true)
      |> put_in(["environment", "fallback_occurred"], true)

    assert {:error, :accelerator_not_proven} = Schema.validate(balanced)
  end

  test "accepts separately proven Linux EXLA evidence" do
    report =
      valid_report()
      |> Map.put("profile", "balanced")
      |> put_model_assets()
      |> put_in(["environment", "requested_backend"], "exla")
      |> put_in(["environment", "backend_proven"], true)
      |> put_in(["environment", "fallback_occurred"], false)

    assert :ok = Schema.validate(report)
  end

  test "requires the exact effective OpenMed optimization policy" do
    report =
      valid_report()
      |> Map.put("profile", "openmed_pii")
      |> put_model_assets()
      |> put_in(["environment", "requested_backend"], "emily")
      |> put_in(["environment", "requested_device"], "gpu")
      |> put_in(["environment", "emily_fallback"], "raise")
      |> put_in(["environment", "backend_proven"], true)
      |> put_in(["environment", "fallback_occurred"], false)
      |> put_in(
        ["environment", "actual"],
        %{
          "openmed_optimization" =>
            OpenMedPolicy.default_metadata()
            |> Jason.encode!()
            |> Jason.decode!()
        }
      )

    assert :ok = Schema.validate(report)

    assert {:error, :openmed_optimization_policy_drift} =
             report
             |> put_in(
               [
                 "environment",
                 "actual",
                 "openmed_optimization",
                 "sequence_length_bucket_threshold"
               ],
               128
             )
             |> Schema.validate()

    assert {:error, :missing_openmed_optimization_policy} =
             report
             |> update_in(["environment", "actual"], &Map.delete(&1, "openmed_optimization"))
             |> Schema.validate()
  end

  defp valid_report do
    concurrency_results =
      Enum.map([1, 2, 4, 8, 16], fn concurrency ->
        %{
          "concurrency" => concurrency,
          "repetition_count" => 2,
          "stable_output" => true,
          "failed" => 0,
          "timed_out" => 0
        }
      end)

    %{
      "schema_version" => 1,
      "status" => "complete",
      "profile" => "fast",
      "dataset" => %{
        "sample_count" => 10,
        "sha256" => hash("a"),
        "sample_ids_sha256" => hash("b"),
        "selection_sha256" => hash("c")
      },
      "cold_lifecycle" => %{
        "status" => "measured",
        "fresh_os_process" => true,
        "assets_preprovisioned" => true,
        "network_downloads_allowed" => false
      },
      "warm_load" => %{"concurrency_results" => concurrency_results},
      "sustained_load" => %{
        "status" => "measured",
        "stop_reason" => "duration",
        "elapsed_ms" => 60_001,
        "requested_duration_ms" => 60_000
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
        "anti_pattern" => %{"status" => "measured"}
      },
      "resources" => %{},
      "asset_evidence" => %{
        "source_manifest_sha256" => hash("d"),
        "models" => %{"profile" => "fast"},
        "asset_hashes" => %{}
      },
      "environment" => %{"requested_backend" => "beam_cpu"},
      "source" => %{"dirty_worktree" => false}
    }
  end

  defp hash(character), do: String.duplicate(character, 64)

  defp put_model_assets(report) do
    report
    |> put_in(["asset_evidence", "models"], %{"model" => "revision"})
    |> put_in(["asset_evidence", "asset_hashes"], %{"model" => hash("f")})
  end
end
