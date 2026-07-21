defmodule Obscura.Eval.Operational.Diagnostic.Manifest do
  @moduledoc """
  Promotion and integrity checks for sustained-latency diagnostics.
  """

  alias Obscura.Eval.Operational.Diagnostic.Schema
  alias Obscura.Eval.Operational.ManifestSupport

  @schema_version 1

  @spec path() :: Path.t()
  def path, do: Path.expand("eval/operational/diagnostic-manifest.json")

  @spec init(Path.t()) :: :ok | {:error, term()}
  def init(path \\ path()), do: ManifestSupport.init(path, @schema_version)

  @spec load(Path.t()) :: {:ok, map()} | {:error, term()}
  def load(path \\ path()), do: ManifestSupport.load(path, &validate_manifest/1)

  @spec promote(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def promote(report_path, opts \\ []) do
    manifest_path = Keyword.get(opts, :manifest_path, path())

    reports_dir =
      Keyword.get(opts, :reports_dir, Path.expand("eval/operational/diagnostic-reports"))

    markdown_path = Path.rootname(report_path) <> ".md"

    with {:ok, body} <- File.read(report_path),
         {:ok, report} <- Jason.decode(body),
         true <- File.regular?(markdown_path),
         :ok <- Schema.validate(report),
         :ok <- init(manifest_path),
         {:ok, manifest} <- load(manifest_path) do
      id = report_id(report)
      File.mkdir_p!(reports_dir)
      json_destination = Path.join(reports_dir, id <> ".json")
      markdown_destination = Path.join(reports_dir, id <> ".md")
      File.cp!(report_path, json_destination)
      File.cp!(markdown_path, markdown_destination)

      entry = %{
        "id" => id,
        "profile" => report["profile"],
        "experiment" => report["experiment"],
        "instrumentation_overhead" => report["instrumentation_overhead"],
        "workload" =>
          Map.take(report["workload"], [
            "requested_duration_ms",
            "elapsed_ms",
            "concurrency",
            "completed",
            "throughput_rps"
          ]),
        "environment" => report["environment"],
        "source" => report["source"],
        "generated_at" => report["generated_at"],
        "files" => %{
          "json" => ManifestSupport.relative(json_destination),
          "json_sha256" => ManifestSupport.sha256_file(json_destination),
          "markdown" => ManifestSupport.relative(markdown_destination),
          "markdown_sha256" => ManifestSupport.sha256_file(markdown_destination)
        }
      }

      reports = [entry | Enum.reject(manifest["reports"], &(&1["id"] == id))]

      next = %{
        "schema_version" => @schema_version,
        "reports" => Enum.sort_by(reports, & &1["id"])
      }

      File.write!(manifest_path, Jason.encode!(next, pretty: true) <> "\n")
      {:ok, entry}
    else
      false -> {:error, {:missing_diagnostic_markdown_report, markdown_path}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec verify(Path.t()) :: :ok | {:error, term()}
  def verify(path \\ path()) do
    with {:ok, manifest} <- load(path) do
      ManifestSupport.verify_reports(manifest["reports"], &verify_entry/1)
    end
  end

  defp report_id(report) do
    experiment = get_in(report, ["experiment", "id"])
    profile = report["profile"]
    platform = get_in(report, ["environment", "platform"])
    "#{profile}-#{experiment}-#{platform}"
  end

  defp validate_manifest(%{"schema_version" => @schema_version, "reports" => reports})
       when is_list(reports) do
    ids = Enum.map(reports, & &1["id"])
    if length(ids) == MapSet.size(MapSet.new(ids)), do: :ok, else: {:error, :duplicate_ids}
  end

  defp validate_manifest(_manifest), do: {:error, :invalid_diagnostic_manifest}

  defp verify_entry(%{"files" => files, "id" => id}) do
    checks = [
      {files["json"], files["json_sha256"]},
      {files["markdown"], files["markdown_sha256"]}
    ]

    if Enum.all?(checks, fn {path, hash} ->
         File.regular?(path) and ManifestSupport.sha256_file(path) == hash
       end),
       do: :ok,
       else: {:error, {:diagnostic_report_hash_mismatch, id}}
  end

  defp verify_entry(_entry), do: {:error, :invalid_diagnostic_manifest_entry}
end
