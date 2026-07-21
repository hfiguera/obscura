defmodule Obscura.Eval.Operational.ManifestTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Manifest

  test "promotes complete clean reports and verifies copied hashes" do
    root = tmp_dir!()
    report_path = Path.join(root, "fast-generated.json")
    markdown_path = Path.rootname(report_path) <> ".md"
    manifest_path = Path.join(root, "manifest.json")
    reports_dir = Path.join(root, "reports")

    File.write!(report_path, Jason.encode!(valid_report(), pretty: true))
    File.write!(markdown_path, "# Safe operational report\n")

    assert {:ok, entry} =
             Manifest.promote(report_path,
               manifest_path: manifest_path,
               reports_dir: reports_dir
             )

    assert entry["id"] == "fast-generated_large_template_heldout-apple_emily"
    assert :ok = Manifest.verify(manifest_path)

    File.write!(Path.join(reports_dir, entry["id"] <> ".md"), "tampered")

    assert {:error, {:operational_report_hash_mismatch, _id}} =
             Manifest.verify(manifest_path)
  end

  test "rejects dirty source evidence" do
    root = tmp_dir!()
    report_path = Path.join(root, "dirty.json")

    File.write!(
      report_path,
      Jason.encode!(put_in(valid_report(), ["source", "dirty_worktree"], true))
    )

    File.write!(Path.rootname(report_path) <> ".md", "# Report\n")

    assert {:error, :dirty_operational_source} =
             Manifest.promote(report_path,
               manifest_path: Path.join(root, "manifest.json"),
               reports_dir: Path.join(root, "reports")
             )
  end

  defp valid_report do
    rows =
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
      "generated_at" => "2026-01-01T00:00:00Z",
      "dataset" => %{
        "id" => "generated_large_template_heldout",
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
      "warm_load" => %{"concurrency_results" => rows},
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
        "source_manifest_sha256" => hash("e"),
        "models" => %{"profile" => "fast"},
        "asset_hashes" => %{}
      },
      "environment" => %{
        "platform" => "apple_emily",
        "requested_backend" => "beam_cpu"
      },
      "source" => %{
        "dirty_worktree" => false,
        "source_commit" => hash("d")
      }
    }
  end

  defp tmp_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-operational-manifest-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp hash(character), do: String.duplicate(character, 64)
end
