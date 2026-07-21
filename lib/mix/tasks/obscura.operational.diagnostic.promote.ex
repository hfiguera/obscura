defmodule Mix.Tasks.Obscura.Operational.Diagnostic.Promote do
  @moduledoc """
  Promotes one complete sustained-latency diagnostic report.
  """

  use Mix.Task

  alias Obscura.Eval.Operational.Diagnostic.Manifest

  @shortdoc "Promotes authoritative sustained-latency evidence"

  @impl true
  def run(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [report: :string, manifest: :string, reports_dir: :string]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid diagnostic promotion options.")
    report = Keyword.get(parsed, :report) || Mix.raise("Expected --report.")

    opts =
      []
      |> maybe_put(:manifest_path, Keyword.get(parsed, :manifest))
      |> maybe_put(:reports_dir, Keyword.get(parsed, :reports_dir))

    case Manifest.promote(report, opts) do
      {:ok, entry} -> Mix.shell().info(Jason.encode!(entry, pretty: true))
      {:error, reason} -> Mix.raise("Diagnostic promotion failed: #{inspect(reason)}")
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
