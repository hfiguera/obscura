defmodule Obscura.Eval.Operational.Diagnostic.ManifestTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Diagnostic.Manifest
  alias Obscura.Test.DiagnosticReportFixture

  test "promotes complete diagnostics and detects artifact tampering" do
    root = tmp_dir!()
    report_path = Path.join(root, "diagnostic.json")
    markdown_path = Path.rootname(report_path) <> ".md"
    manifest_path = Path.join(root, "manifest.json")
    reports_dir = Path.join(root, "reports")

    File.write!(report_path, Jason.encode!(DiagnosticReportFixture.valid_report(), pretty: true))
    File.write!(markdown_path, "# Diagnostic\n")

    assert {:ok, entry} =
             Manifest.promote(report_path,
               manifest_path: manifest_path,
               reports_dir: reports_dir
             )

    assert entry["id"] == "balanced-balanced_canonical_r1-apple_emily"
    assert :ok = Manifest.verify(manifest_path)

    File.write!(Path.join(reports_dir, entry["id"] <> ".md"), "tampered")
    assert {:error, {:diagnostic_report_hash_mismatch, _id}} = Manifest.verify(manifest_path)
  end

  defp tmp_dir! do
    path =
      Path.join(System.tmp_dir!(), "obscura-diagnostic-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
