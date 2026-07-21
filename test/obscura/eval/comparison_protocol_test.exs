defmodule Obscura.Eval.ComparisonProtocolTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.ComparisonProtocol

  setup do
    root =
      Path.join(System.tmp_dir!(), "obscura-comparison-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "scores external predictions with one fingerprinted ordered selection", %{root: root} do
    selection_path = Path.join(root, "selection.json")
    predictions_path = Path.join(root, "predictions.jsonl")
    reference_path = Path.join(root, "reference.json")

    assert :ok =
             ComparisonProtocol.write_selection(:generated_large, selection_path)

    selection = selection_path |> File.read!() |> Jason.decode!()
    rows = prediction_rows(get_in(selection, ["dataset", "ordered_sample_ids"]))
    write_jsonl(predictions_path, rows)
    write_reference(reference_path, selection, predictions_path)

    assert {:ok, report} =
             ComparisonProtocol.score_external(selection_path, predictions_path,
               reference_report: reference_path,
               run_id: "comparison-test"
             )

    assert report["status"] == "complete"
    assert report["external_baseline"]
    assert report["metrics"]["true_positives"] == 0
    assert report["metrics"]["false_positives"] == 0
    assert report["metrics"]["false_negatives"] > 0
    assert report["metrics"]["span_iou"]["iou_threshold"] == 0.9
    assert report["dataset"]["sample_count"] == 648
  end

  test "rejects reordered prediction rows", %{root: root} do
    selection_path = Path.join(root, "selection.json")
    predictions_path = Path.join(root, "predictions.jsonl")
    reference_path = Path.join(root, "reference.json")

    :ok = ComparisonProtocol.write_selection(:generated_large, selection_path)
    selection = selection_path |> File.read!() |> Jason.decode!()

    rows =
      selection
      |> get_in(["dataset", "ordered_sample_ids"])
      |> prediction_rows()
      |> Enum.reverse()

    write_jsonl(predictions_path, rows)
    write_reference(reference_path, selection, predictions_path)

    assert {:error, :prediction_ordered_sample_ids_mismatch} =
             ComparisonProtocol.score_external(selection_path, predictions_path,
               reference_report: reference_path,
               run_id: "comparison-test"
             )
  end

  test "rejects a changed entity policy fingerprint", %{root: root} do
    selection_path = Path.join(root, "selection.json")
    predictions_path = Path.join(root, "predictions.jsonl")
    reference_path = Path.join(root, "reference.json")

    :ok = ComparisonProtocol.write_selection(:generated_large, selection_path)

    selection =
      selection_path
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["entity_policy", "entities"], ["email"])

    File.write!(selection_path, Jason.encode!(selection))
    File.write!(predictions_path, "")
    write_reference(reference_path, selection, predictions_path)

    assert {:error, :comparison_entity_policy_fingerprint_mismatch} =
             ComparisonProtocol.score_external(selection_path, predictions_path,
               reference_report: reference_path,
               run_id: "comparison-test"
             )
  end

  test "annotates dependency-light reports with proven BEAM CPU runtime", %{root: root} do
    selection_path = Path.join(root, "selection.json")
    report_path = Path.join(root, "source.json")
    out_path = Path.join(root, "annotated.json")

    :ok = ComparisonProtocol.write_selection(:generated_large, selection_path)
    selection = selection_path |> File.read!() |> Jason.decode!()

    report = %{
      "profile" => "deterministic_plus",
      "skip_reason" => nil,
      "dataset" => %{
        "name" => get_in(selection, ["dataset", "name"]),
        "sample_ids" => get_in(selection, ["dataset", "ordered_sample_ids"]),
        "sample_count" => get_in(selection, ["dataset", "sample_count"]),
        "requested_entities" => get_in(selection, ["entity_policy", "entities"])
      },
      "metrics" => %{"f1" => 1.0},
      "latency" => %{"mean_ms" => 1.0}
    }

    File.write!(report_path, Jason.encode!(report))
    File.write!(Path.rootname(report_path) <> ".md", "# Source\n")

    assert {:ok, %{json: ^out_path}} =
             ComparisonProtocol.annotate_obscura_report(
               selection_path,
               report_path,
               out_path
             )

    annotated = out_path |> File.read!() |> Jason.decode!()

    assert annotated["runtime_backend"] == %{
             "actual_backend" => "beam",
             "actual_device" => "cpu",
             "backend_proven" => true,
             "fallback_occurred" => false
           }
  end

  defp prediction_rows(ids) do
    Enum.map(ids, &%{"sample_id" => &1, "predictions" => [], "latency_ms" => 1.0})
  end

  defp write_jsonl(path, rows) do
    body = Enum.map_join(rows, &(Jason.encode!(&1) <> "\n"))
    File.write!(path, body)
  end

  defp write_reference(path, selection, predictions_path) do
    reference = %{
      "status" => "complete",
      "adapter" => "Presidio.AnalyzerEngine",
      "gold_derived" => false,
      "command" => "python reference",
      "model" => %{"id" => "en_core_web_lg", "version" => "3.8.0"},
      "dependencies" => %{},
      "environment" => %{},
      "runtime_backend" => %{
        "actual_backend" => "spacy_cpu",
        "actual_device" => "cpu"
      },
      "limitations" => [],
      "predictions_sha256" => sha256(predictions_path),
      "fingerprints" => %{
        "dataset_sha256" => get_in(selection, ["dataset", "sha256"]),
        "sample_ids_sha256" => get_in(selection, ["dataset", "sample_ids_sha256"]),
        "entity_policy_sha256" => get_in(selection, ["entity_policy", "sha256"]),
        "scoring_sha256" => get_in(selection, ["scoring", "sha256"])
      }
    }

    File.write!(path, Jason.encode!(reference))
  end

  defp sha256(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
