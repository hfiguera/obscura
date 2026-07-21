defmodule Mix.Tasks.Obscura.Profile.Check do
  @moduledoc """
  Checks whether an Obscura product profile is ready.

      mix obscura.profile.check --profile fast
      mix obscura.profile.check --profile balanced --backend emily --prepare --allow-download
  """

  use Mix.Task

  alias Mix.Tasks.Obscura.Profile.Options
  alias Obscura.Diagnostic
  alias Obscura.Profile

  @shortdoc "Checks product profile readiness"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse_args(args)
    profile = Keyword.fetch!(opts, :profile)

    case Profile.preflight(profile, opts) do
      {:ok, report} ->
        render(report, opts)

      {:error, diagnostic, report} ->
        render(report, opts)
        Mix.raise(Diagnostic.format(diagnostic))
    end
  end

  defp parse_args(args) do
    {parsed, _remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          profile: :string,
          json: :boolean,
          prepare: :boolean,
          allow_download: :boolean,
          offline: :boolean,
          timeout: :integer,
          inactivity_timeout: :integer,
          checkpoint: :string,
          backend: :string,
          emily_fallback: :string,
          emily_device: :string,
          compile_batch_size: :integer,
          compile_sequence_length: :integer
        ]
      )

    if invalid != [], do: Mix.raise("Invalid options.")
    if is_nil(parsed[:profile]), do: Mix.raise("Expected --profile")

    Options.put_runtime_options(parsed)
  end

  defp render(report, opts) do
    if Keyword.get(opts, :json, false) do
      Mix.shell().info(Jason.encode!(report, pretty: true))
    else
      Mix.shell().info(human_report(report))
    end
  end

  defp human_report(report) do
    models = report.requirements.default_models |> Enum.map_join(", ", &to_string/1)
    warnings = Enum.map_join(report.warnings, "\n", &"warning: #{&1}")

    [
      "profile=#{report.profile} stability=#{report.stability} status=#{report.status}",
      "implementation=#{report.implementation_profile}",
      "models=#{if(models == "", do: "none", else: models)}",
      diagnostic_line(report.diagnostic),
      warnings
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp diagnostic_line(nil), do: nil

  defp diagnostic_line(diagnostic) do
    "diagnostic=#{diagnostic.code}: #{diagnostic.message} remediation=#{diagnostic.remediation}"
  end
end
