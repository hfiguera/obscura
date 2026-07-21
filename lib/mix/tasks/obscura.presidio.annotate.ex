defmodule Mix.Tasks.Obscura.Presidio.Annotate do
  @moduledoc """
  Adds verified comparison protocol fingerprints to an Obscura report.
  """

  use Mix.Task

  alias Obscura.Eval.ComparisonProtocol

  @shortdoc "Annotates an Obscura report for authoritative comparison"

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [selection: :string, report: :string, out: :string]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid options.")
    Enum.each([:selection, :report, :out], &require!(opts, &1))

    case ComparisonProtocol.annotate_obscura_report(
           opts[:selection],
           opts[:report],
           opts[:out]
         ) do
      {:ok, paths} -> Mix.shell().info("Annotated report written to #{paths.json}")
      {:error, reason} -> Mix.raise("Report annotation failed: #{inspect(reason)}")
    end
  end

  defp require!(opts, key) do
    if is_nil(opts[key]),
      do: Mix.raise("Expected --#{key |> to_string() |> String.replace("_", "-")}")
  end
end
