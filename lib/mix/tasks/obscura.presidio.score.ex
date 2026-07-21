defmodule Mix.Tasks.Obscura.Presidio.Score do
  @moduledoc """
  Scores Presidio prediction JSONL with Obscura's authoritative evaluator.
  """

  use Mix.Task

  alias Obscura.Eval.ComparisonProtocol

  @shortdoc "Scores an authoritative Presidio prediction export"

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          selection: :string,
          predictions: :string,
          reference_report: :string,
          run_id: :string,
          out_dir: :string
        ]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid options.")

    required = [:selection, :predictions, :reference_report, :run_id]

    Enum.each(required, fn key ->
      if is_nil(opts[key]),
        do: Mix.raise("Expected --#{key |> to_string() |> String.replace("_", "-")}")
    end)

    out_dir = Keyword.get(opts, :out_dir, "eval/reports")

    case ComparisonProtocol.write_external_report(
           opts[:selection],
           opts[:predictions],
           out_dir,
           reference_report: opts[:reference_report],
           run_id: opts[:run_id]
         ) do
      {:ok, paths} ->
        Mix.shell().info("Presidio report written to #{paths.json}")

      {:error, reason} ->
        Mix.raise("Presidio scoring failed: #{inspect(reason)}")
    end
  end
end
