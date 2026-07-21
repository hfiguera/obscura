defmodule Obscura.Eval.AuthoritativeManifestTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.AuthoritativeManifest

  setup do
    root =
      Path.join(System.tmp_dir!(), "obscura-authoritative-#{System.unique_integer([:positive])}")

    reports_dir = Path.join(root, "reports")
    source_dir = Path.join(root, "source")
    manifest_path = Path.join(root, "manifest.json")
    dataset_path = Path.join(root, "dataset.json")

    File.mkdir_p!(source_dir)
    File.write!(dataset_path, "[]\n")

    File.write!(
      manifest_path,
      Jason.encode!(
        %{
          "schema_version" => 1,
          "status" => "active",
          "policy" => "test",
          "reports" => []
        },
        pretty: true
      )
    )

    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      reports_dir: reports_dir,
      source_dir: source_dir,
      manifest_path: manifest_path,
      dataset_path: dataset_path
    }
  end

  test "project authoritative manifest starts valid" do
    assert {:ok, %{"schema_version" => 1}} = AuthoritativeManifest.load()
    assert :ok = AuthoritativeManifest.verify()
  end

  test "promotes and verifies a deterministic report", context do
    report_path = write_report(context, "deterministic_plus", "Obscura.Deterministic")
    repetition_path = write_report(context, "deterministic_plus", "Obscura.Deterministic", "r1")

    assert {:ok, entry} =
             AuthoritativeManifest.promote(report_path,
               stable_profile: :fast,
               command: "mix obscura.eval --profile fast",
               repetition_reports: [repetition_path],
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir,
               hardware_label: "test-host",
               os_version: "test-os",
               cpu: "test-cpu",
               memory_bytes: "1024",
               accelerator: "none"
             )

    assert entry["id"] == "fast:generated_large:template_heldout"
    assert entry["dataset"]["sha256"] =~ ~r/^[0-9a-f]{64}$/
    assert entry["files"]["json_sha256"] =~ ~r/^[0-9a-f]{64}$/
    assert entry["repetitions"]["measured_runs"] == 2
    assert [_, _] = entry["repetitions"]["runs"]
    assert entry["metrics"]["per_entity"] == %{}
    assert entry["environment"]["cpu"] == "test-cpu"
    assert entry["dependencies"]["mix_lock_sha256"] =~ ~r/^[0-9a-f]{64}$/
    assert :ok = AuthoritativeManifest.verify(context.manifest_path)

    assert {:ok, manifest} = AuthoritativeManifest.load(context.manifest_path)
    assert [promoted] = manifest["reports"]
    assert promoted["stable_profile"] == "fast"
  end

  test "rejects repetition reports with different accuracy contracts", context do
    report_path = write_report(context, "deterministic_plus", "Obscura.Deterministic")
    repetition_path = write_report(context, "deterministic_plus", "Obscura.Deterministic", "r1")

    report = repetition_path |> File.read!() |> Jason.decode!()
    changed = put_in(report, ["metrics", "false_positives"], 1)
    File.write!(repetition_path, Jason.encode!(changed, pretty: true))

    assert {:error, {:invalid_repetition_report, ^repetition_path, :repetition_contract_mismatch}} =
             AuthoritativeManifest.promote(report_path,
               stable_profile: :fast,
               command: "mix obscura.eval --profile fast",
               repetition_reports: [repetition_path],
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )
  end

  test "rejects fake and skipped reports", context do
    fake_path = write_report(context, "nlp", "Obscura Fake Serving", "fake")

    assert {:error, :fake_or_gold_derived_report_not_authoritative} =
             AuthoritativeManifest.promote(fake_path,
               stable_profile: :fast,
               command: "fake",
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )

    skipped_path = write_report(context, "deterministic_plus", "Obscura", "skipped")
    body = skipped_path |> File.read!() |> Jason.decode!() |> Map.put("skip_reason", "missing")
    File.write!(skipped_path, Jason.encode!(body, pretty: true))

    assert {:error, {:skipped_report_not_authoritative, "missing"}} =
             AuthoritativeManifest.promote(skipped_path,
               stable_profile: :fast,
               command: "skipped",
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )
  end

  test "requires revision and hash evidence for model-backed profiles", context do
    report_path =
      write_report(
        context,
        "hybrid_ner_tner_conservative",
        "Obscura.Deterministic+Obscura.Recognizer.NER.Serving"
      )

    report = report_path |> File.read!() |> Jason.decode!()

    File.write!(
      report_path,
      Jason.encode!(Map.put(report, "model", %{"model_id" => "test/model"}))
    )

    assert {:error, :missing_immutable_model_revisions} =
             AuthoritativeManifest.promote(report_path,
               stable_profile: :balanced,
               command: "model benchmark",
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )
  end

  test "rejects requested-only backend metadata for model-backed profiles", context do
    report_path =
      write_report(
        context,
        "hybrid_ner_tner_conservative",
        "Obscura.Deterministic+Obscura.Recognizer.NER.Serving"
      )

    report =
      report_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("model", %{"model_id" => "test/model"})
      |> Map.put("runtime_backend", %{"requested_backend" => "emily"})

    File.write!(report_path, Jason.encode!(report))

    assert {:error, :missing_actual_backend_metadata} =
             AuthoritativeManifest.promote(report_path,
               stable_profile: :balanced,
               command: "model benchmark",
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )
  end

  test "uses dependency versions captured by the source report", context do
    report_path = write_report(context, "deterministic_plus", "Obscura.Deterministic")

    report =
      report_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("dependencies", %{
        "emily" => "0.6.1",
        "mix_lock_sha256" => String.duplicate("a", 64)
      })

    File.write!(report_path, Jason.encode!(report))

    assert {:ok, entry} =
             AuthoritativeManifest.promote(report_path,
               stable_profile: :fast,
               command: "deterministic benchmark",
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )

    assert entry["dependencies"] == report["dependencies"]
  end

  test "promotes a compact canonical report while retaining source-run hashes", context do
    report_path = write_report(context, "deterministic_plus", "Obscura.Deterministic")

    report =
      report_path
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["metrics", "model_errors"], List.duplicate(%{"value" => "[omitted]"}, 100))
      |> put_in(
        ["metrics", "span_iou", "examples"],
        List.duplicate(%{"value" => "[omitted]"}, 100)
      )
      |> Map.put("internal_experiment_state", List.duplicate("not authoritative", 100))

    File.write!(report_path, Jason.encode!(report, pretty: true))
    source_hash = sha256(report_path)

    assert {:ok, entry} =
             AuthoritativeManifest.promote(report_path,
               stable_profile: :fast,
               command: "deterministic benchmark",
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )

    promoted_path = Path.join(context.reports_dir, "fast__generated_large__template_heldout.json")
    promoted = promoted_path |> File.read!() |> Jason.decode!()

    refute Map.has_key?(promoted, "internal_experiment_state")
    refute Map.has_key?(promoted["metrics"], "model_errors")
    assert promoted["metrics"]["f1"] == 1.0
    assert get_in(entry, ["repetitions", "runs", Access.at(0), "json_sha256"]) == source_hash

    repetition_iou =
      get_in(entry, ["repetitions", "runs", Access.at(0), "metrics", "span_iou"])

    refute Map.has_key?(repetition_iou, "examples")

    assert entry["files"]["json_sha256"] == sha256(promoted_path)
    refute entry["files"]["json_sha256"] == source_hash
  end

  test "retains OpenMed output fingerprints in the manifest and canonical report", context do
    fingerprint = String.duplicate("f", 64)
    report_path = write_report(context, "privacy_filter_native", "Obscura.PrivacyFilter")

    report =
      report_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("model", %{"model_id" => "test/openmed"})
      |> Map.put("source", %{"source_commit" => "abcdef0", "dirty_worktree" => false})
      |> put_in(["metrics", "output_fingerprint_sha256"], fingerprint)

    File.write!(report_path, Jason.encode!(report, pretty: true))

    assert {:ok, entry} =
             AuthoritativeManifest.promote(report_path,
               stable_profile: :openmed_pii,
               command: "mix obscura.eval --profile openmed_pii",
               model_revisions: %{"test/openmed" => "revision"},
               asset_hashes: %{"model.safetensors" => String.duplicate("a", 64)},
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )

    assert entry["metrics"]["output_fingerprint_sha256"] == fingerprint
    assert entry["source_commit"] == "abcdef0"
    assert entry["dirty_worktree"] == false

    promoted_path =
      Path.join(context.reports_dir, "openmed_pii__generated_large__template_heldout.json")

    assert promoted_path
           |> File.read!()
           |> Jason.decode!()
           |> get_in(["metrics", "output_fingerprint_sha256"]) == fingerprint
  end

  test "rejects non-omitted report values", context do
    canary = "authoritative-report-canary-93871"
    report_path = write_report(context, "deterministic_plus", "Obscura.Deterministic", "raw")

    report = report_path |> File.read!() |> Jason.decode!() |> Map.put("value", canary)

    File.write!(report_path, Jason.encode!(report, pretty: true))

    result =
      AuthoritativeManifest.promote(report_path,
        stable_profile: :fast,
        command: "unsafe",
        manifest_path: context.manifest_path,
        reports_dir: context.reports_dir
      )

    assert {:error, :report_contains_raw_values} = result
    refute inspect(result) =~ canary
  end

  test "promotes an external baseline without a stable profile", context do
    report_path = write_external_report(context, "external")
    repetition_path = write_external_report(context, "external-r2")

    assert {:ok, entry} =
             AuthoritativeManifest.promote_external(report_path,
               baseline_id: "presidio_spacy_en_core_web_lg",
               command: "python authoritative reference",
               repetition_reports: [repetition_path],
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir,
               warmup: 1
             )

    assert entry["entry_type"] == "external_baseline"
    assert entry["system"] == "presidio"
    refute Map.has_key?(entry, "stable_profile")
    assert entry["repetitions"]["measured_runs"] == 2
    assert :ok = AuthoritativeManifest.verify(context.manifest_path)
  end

  test "external promotion rejects one run and mismatched protocol evidence", context do
    report_path = write_external_report(context, "external")

    assert {:error, :insufficient_external_repetitions} =
             AuthoritativeManifest.promote_external(report_path,
               baseline_id: "presidio",
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )

    repetition_path = write_external_report(context, "external-r2")

    repetition =
      repetition_path
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["comparison_protocol", "sample_ids_sha256"], String.duplicate("b", 64))

    File.write!(repetition_path, Jason.encode!(repetition))

    assert {:error,
            {:invalid_repetition_report, ^repetition_path, :external_repetition_contract_mismatch}} =
             AuthoritativeManifest.promote_external(report_path,
               baseline_id: "presidio",
               repetition_reports: [repetition_path],
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )
  end

  test "external promotion rejects machine-specific command paths", context do
    report_path = write_external_report(context, "external-absolute-command")

    report =
      report_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("command", "/Users/example/.venv/bin/python benchmark.py")

    File.write!(report_path, Jason.encode!(report))

    assert {:error, :report_command_contains_absolute_path} =
             AuthoritativeManifest.promote_external(report_path,
               baseline_id: "presidio",
               repetition_reports: [report_path],
               manifest_path: context.manifest_path,
               reports_dir: context.reports_dir
             )
  end

  defp write_report(context, profile, adapter, suffix \\ "report") do
    report_path = Path.join(context.source_dir, "#{suffix}.json")
    markdown_path = Path.rootname(report_path) <> ".md"

    report = %{
      "adapter" => adapter,
      "profile" => profile,
      "git_sha" => "abcdef0",
      "timestamp" => "2026-07-14T00:00:00Z",
      "skip_reason" => nil,
      "dataset" => %{
        "name" => "generated_large",
        "version" => "test",
        "sample_count" => 1,
        "source" => context.dataset_path,
        "requested_entities" => ["email"],
        "template_split" => %{"name" => "template_heldout"}
      },
      "metrics" => %{
        "precision" => 1.0,
        "recall" => 1.0,
        "f1" => 1.0,
        "f2" => 1.0,
        "true_positives" => 1,
        "false_positives" => 0,
        "false_negatives" => 0,
        "wrong_entity_type" => 0,
        "offset_mismatches" => 0,
        "unsupported_expected_spans" => 0,
        "span_iou" => %{"f1" => 1.0}
      },
      "latency" => %{"mean_ms" => 1.0, "p95_ms" => 1.0},
      "runtime_backend" => %{
        "requested_backend" => "binary",
        "actual_backend" => "binary",
        "actual_device" => "cpu"
      },
      "limitations" => [],
      "example" => %{"value" => "[omitted]"}
    }

    File.write!(report_path, Jason.encode!(report, pretty: true))
    File.write!(markdown_path, "| F1 | 1.0000 |\n")
    report_path
  end

  defp write_external_report(context, suffix) do
    report_path = Path.join(context.source_dir, "#{suffix}.json")
    markdown_path = Path.rootname(report_path) <> ".md"
    hash = String.duplicate("a", 64)

    report = %{
      "run_id" => suffix,
      "phase" => "authoritative_presidio_comparison",
      "status" => "complete",
      "adapter" => "Presidio.AnalyzerEngine",
      "profile" => "presidio_spacy_en_core_web_lg",
      "external_baseline" => true,
      "gold_derived" => false,
      "git_sha" => "abcdef0",
      "timestamp" => "2026-07-17T00:00:00Z",
      "command" => "python authoritative reference",
      "model" => %{"id" => "en_core_web_lg", "version" => "3.8.0"},
      "dependencies" => %{
        "python" => "3.11.15",
        "lock_sha256" => hash,
        "packages" => %{
          "presidio-analyzer" => "2.2.363",
          "presidio-evaluator" => "0.2.5",
          "spacy" => "3.8.14",
          "en_core_web_lg" => "3.8.0"
        }
      },
      "environment" => %{
        "hardware_label" => "test-host",
        "os" => "macOS",
        "architecture" => "arm64",
        "cpu" => "test-cpu",
        "memory_bytes" => "1024",
        "accelerator" => "not used"
      },
      "runtime_backend" => %{
        "actual_backend" => "spacy_cpu",
        "actual_device" => "cpu"
      },
      "dataset" => %{
        "name" => "generated_large",
        "version" => "test",
        "sample_count" => 1,
        "source" => context.dataset_path,
        "sha256" => hash,
        "sample_ids_sha256" => hash,
        "requested_entities" => ["email"],
        "template_split" => %{"name" => "template_heldout"}
      },
      "comparison_protocol" => %{
        "id" => "test_protocol",
        "selection_sha256" => hash,
        "protocol_sha256" => hash,
        "sample_ids_sha256" => hash,
        "entity_policy_sha256" => hash,
        "scoring_sha256" => hash
      },
      "entity_mapping" => %{"entities" => ["email"], "sha256" => hash},
      "metrics" => %{
        "precision" => 1.0,
        "recall" => 1.0,
        "f1" => 1.0,
        "f2" => 1.0,
        "true_positives" => 1,
        "false_positives" => 0,
        "false_negatives" => 0,
        "wrong_entity_type" => 0,
        "offset_mismatches" => 0,
        "unsupported_expected_spans" => 0,
        "span_iou" => %{"f1" => 1.0}
      },
      "per_entity" => %{},
      "latency" => %{"mean_ms" => 1.0, "p50_ms" => 1.0, "p95_ms" => 1.0},
      "limitations" => [],
      "artifacts" => %{"predictions_sha256" => hash}
    }

    File.write!(report_path, Jason.encode!(report, pretty: true))
    File.write!(markdown_path, "| F1 | 1.0000 |\n")
    report_path
  end

  defp sha256(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
