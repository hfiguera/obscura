defmodule Mix.Tasks.Obscura.Benchmarks.Promote do
  @moduledoc """
  Promotes a validated report pair into the authoritative benchmark manifest.

      mix obscura.benchmarks.promote \
        --report eval/reports/report.json \
        --profile fast \
        --command "mix obscura.eval ..."
  """

  use Mix.Task

  alias Obscura.CLI
  alias Obscura.Eval.AuthoritativeManifest

  @shortdoc "Promotes an authoritative benchmark report"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse_args(args)
    report = Keyword.fetch!(opts, :report)

    result =
      if Keyword.has_key?(opts, :baseline_id),
        do: AuthoritativeManifest.promote_external(report, opts),
        else: AuthoritativeManifest.promote(report, opts)

    case result do
      {:ok, entry} -> Mix.shell().info(Jason.encode!(entry, pretty: true))
      {:error, reason} -> Mix.raise("Benchmark promotion failed: #{CLI.format_error(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, _remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          report: :string,
          profile: :string,
          external_baseline: :string,
          command: :string,
          model_revisions: :string,
          asset_hashes: :string,
          repetition_reports: :string,
          hardware_label: :string,
          os_version: :string,
          cpu: :string,
          memory_bytes: :string,
          accelerator: :string,
          compile_batch_size: :integer,
          compile_sequence_length: :integer,
          warmup: :integer,
          concurrency: :integer,
          force: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("Invalid options.")

    promotion_opts =
      case Keyword.get(parsed, :external_baseline) do
        nil -> [stable_profile: parsed |> Keyword.get(:profile) |> parse_profile!()]
        baseline_id -> [baseline_id: baseline_id]
      end

    [
      report: Keyword.get(parsed, :report),
      command: Keyword.get(parsed, :command),
      model_revisions: parsed |> Keyword.get(:model_revisions, "{}") |> parse_map!(),
      asset_hashes: parsed |> Keyword.get(:asset_hashes, "{}") |> parse_map!(),
      repetition_reports: parsed |> Keyword.get(:repetition_reports, "") |> parse_report_paths(),
      hardware_label: Keyword.get(parsed, :hardware_label, "unspecified"),
      os_version: Keyword.get(parsed, :os_version, "unspecified"),
      cpu: Keyword.get(parsed, :cpu, "unspecified"),
      memory_bytes: Keyword.get(parsed, :memory_bytes, "unspecified"),
      accelerator: Keyword.get(parsed, :accelerator, "unspecified"),
      compile_batch_size: Keyword.get(parsed, :compile_batch_size),
      compile_sequence_length: Keyword.get(parsed, :compile_sequence_length),
      warmup: Keyword.get(parsed, :warmup, 0),
      concurrency: Keyword.get(parsed, :concurrency, 1),
      force: Keyword.get(parsed, :force, false)
    ]
    |> Keyword.merge(promotion_opts)
    |> validate_required!()
  end

  defp parse_profile!(nil), do: Mix.raise("Expected --profile")

  defp parse_profile!(profile) do
    case Obscura.Profile.fetch(profile) do
      {:ok, descriptor} -> descriptor.name
      {:error, _reason} -> Mix.raise("Invalid stable profile.")
    end
  end

  defp parse_map!(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _other -> Mix.raise("Expected a JSON object for revision/hash metadata")
    end
  end

  defp parse_report_paths(""), do: []

  defp parse_report_paths(paths) do
    paths
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp validate_required!(opts) do
    for key <- [:report, :command], is_nil(opts[key]) do
      Mix.raise("Expected --#{key |> Atom.to_string() |> String.replace("_", "-")}")
    end

    opts
  end
end
