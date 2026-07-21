defmodule Mix.Tasks.Obscura.Presidio.Prepare do
  @moduledoc """
  Prepares a privacy-safe, fingerprinted Presidio comparison selection.
  """

  use Mix.Task

  alias Obscura.Eval.ComparisonProtocol
  alias Obscura.Eval.PresidioResearchLoader

  @shortdoc "Prepares an authoritative Presidio comparison selection"

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [dataset: :string, protocol: :string, out: :string]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid options.")

    dataset = opts |> Keyword.fetch!(:dataset) |> dataset!()
    out = Keyword.fetch!(opts, :out)
    protocol = Keyword.get(opts, :protocol)
    prepare_opts = if protocol, do: [protocol_path: protocol], else: []

    case ComparisonProtocol.write_selection(dataset, out, prepare_opts) do
      :ok -> Mix.shell().info("Comparison selection written to #{out}")
      {:error, reason} -> Mix.raise("Comparison selection failed: #{inspect(reason)}")
    end
  end

  defp dataset!(name) do
    Enum.find(
      PresidioResearchLoader.known_datasets(),
      &(Atom.to_string(&1) == name)
    ) || Mix.raise("Unknown dataset.")
  end
end
