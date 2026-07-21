defmodule Mix.Tasks.Obscura.Operational.Cold do
  @moduledoc false

  use Mix.Task

  alias Obscura.Eval.Operational.Benchmark
  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Profile

  @impl true
  def run(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args, strict: [profile: :string, dataset: :string, out: :string])

    if remaining != [] or invalid != [], do: Mix.raise("Invalid cold benchmark options.")

    profiles = Profile.names() ++ Profile.experimental_names()
    profile = existing(Keyword.fetch!(parsed, :profile), profiles, "profile")
    dataset = existing(Keyword.fetch!(parsed, :dataset), Dataset.names(), "dataset")
    output = Keyword.fetch!(parsed, :out)

    case Benchmark.cold(profile, dataset) do
      {:ok, report} -> File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
      {:error, reason} -> Mix.raise("Cold benchmark failed: #{inspect(reason)}")
    end
  end

  defp existing(value, allowed, kind) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      Mix.raise("Unknown #{kind}.")
  end
end
