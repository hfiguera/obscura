defmodule Mix.Tasks.Obscura.Export.Predictions do
  @moduledoc """
  Exports Obscura predictions in Presidio-compatible JSONL.
  """

  use Mix.Task

  alias Obscura.CLI
  alias Obscura.Eval.PredictionExport
  alias Obscura.Eval.Profile

  @shortdoc "Exports Presidio-compatible Obscura predictions"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    case PredictionExport.write(opts) do
      :ok ->
        Mix.shell().info("Prediction export written to #{Keyword.fetch!(opts, :out)}")

      {:error, reason} ->
        Mix.raise("Prediction export failed: #{CLI.format_error(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, _remaining, invalid} =
      OptionParser.parse(args,
        strict: [dataset: :string, profile: :string, limit: :integer, out: :string]
      )

    if invalid != [], do: Mix.raise("Invalid options.")

    dataset = Keyword.get(parsed, :dataset, "synth_dataset_v2")
    if dataset != "synth_dataset_v2", do: Mix.raise("Unsupported dataset.")

    profile =
      parsed
      |> Keyword.get(:profile, "regex_only")
      |> profile!()

    [
      dataset: dataset,
      profile: profile,
      limit: Keyword.get(parsed, :limit, 25),
      out: Keyword.get(parsed, :out, "eval/predictions/obscura_#{profile}.jsonl")
    ]
  end

  defp profile!(profile) do
    case Profile.from_string(profile) do
      {:ok, profile} -> profile
      {:error, {:unknown_profile, _other}} -> Mix.raise("Unknown profile.")
    end
  end
end
