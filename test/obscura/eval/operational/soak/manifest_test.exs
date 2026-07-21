defmodule Obscura.Eval.Operational.Soak.ManifestTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Soak.Manifest
  alias Obscura.Test.SoakReportFixture

  test "promotes validated soak evidence separately and detects tampering" do
    root = tmp_dir!()
    report_path = Path.join(root, "fast-soak.json")
    markdown_path = Path.rootname(report_path) <> ".md"
    manifest_path = Path.join(root, "soak-manifest.json")
    reports_dir = Path.join(root, "reports")

    File.write!(report_path, Jason.encode!(SoakReportFixture.valid_report(), pretty: true))
    File.write!(markdown_path, "# Safe soak report\n")

    assert {:ok, entry} =
             Manifest.promote(report_path,
               manifest_path: manifest_path,
               reports_dir: reports_dir
             )

    assert entry["id"] == "fast-c4-600000-apple_emily"
    assert :ok = Manifest.verify(manifest_path)

    File.write!(Path.join(reports_dir, entry["id"] <> ".md"), "tampered")

    assert {:error, {:soak_report_hash_mismatch, _id}} = Manifest.verify(manifest_path)
  end

  test "rejects reports containing absolute local paths" do
    root = tmp_dir!()
    report_path = Path.join(root, "unsafe.json")

    report =
      SoakReportFixture.valid_report()
      |> Map.put("debug_location", "/Users/developer/private")

    File.write!(report_path, Jason.encode!(report))
    File.write!(Path.rootname(report_path) <> ".md", "# Report\n")

    assert {:error, :soak_report_contains_absolute_path} =
             Manifest.promote(report_path,
               manifest_path: Path.join(root, "manifest.json"),
               reports_dir: Path.join(root, "reports")
             )
  end

  defp tmp_dir! do
    path =
      Path.join(System.tmp_dir!(), "obscura-soak-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
