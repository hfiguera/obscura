defmodule Mix.Tasks.Obscura.Openmed.Optimize do
  @moduledoc false

  use Mix.Task

  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Eval.Operational.OpenMedOptimization

  @shortdoc "Runs an isolated OpenMed optimization experiment"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse(args)

    case OpenMedOptimization.run(opts) do
      {:ok, report} ->
        path = output_path(opts)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Jason.encode!(report, pretty: true) <> "\n")
        Mix.shell().info("Wrote #{path}")

      {:error, reason} ->
        Mix.raise("OpenMed optimization experiment failed: #{inspect(reason)}")
    end
  end

  defp parse(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          variant: :string,
          dataset: :string,
          repetition: :integer,
          sample_count: :integer,
          concurrency: :integer,
          bucket_threshold: :integer,
          request_timeout: :integer,
          privacy_filter_checkpoint: :string,
          output_root: :string
        ]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid OpenMed optimization options.")

    [
      variant: parse_variant(Keyword.get(parsed, :variant)),
      dataset: parse_dataset(Keyword.get(parsed, :dataset)),
      repetition: positive!(parsed, :repetition, 1),
      sample_count: positive!(parsed, :sample_count, 32),
      concurrency: positive!(parsed, :concurrency, 4),
      bucket_threshold: positive!(parsed, :bucket_threshold, 129),
      request_timeout: positive!(parsed, :request_timeout, 300_000),
      privacy_filter_checkpoint:
        Keyword.get(parsed, :privacy_filter_checkpoint) ||
          System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT"),
      output_root: Keyword.get(parsed, :output_root, "eval/reports/openmed-optimization")
    ]
  end

  defp parse_variant(nil), do: Mix.raise("Expected --variant.")

  defp parse_variant(value) do
    Enum.find(OpenMedOptimization.variants(), &(Atom.to_string(&1) == value)) ||
      Mix.raise("Unknown OpenMed optimization variant.")
  end

  defp parse_dataset(nil), do: Mix.raise("Expected --dataset.")

  defp parse_dataset(value) do
    Enum.find(Dataset.names(), &(Atom.to_string(&1) == value)) ||
      Mix.raise("Unknown OpenMed optimization dataset.")
  end

  defp positive!(parsed, key, default) do
    case Keyword.get(parsed, key, default) do
      value when is_integer(value) and value > 0 -> value
      _other -> Mix.raise("--#{String.replace(Atom.to_string(key), "_", "-")} must be positive.")
    end
  end

  defp output_path(opts) do
    filename =
      [
        opts[:variant],
        opts[:dataset],
        "r#{opts[:repetition]}"
      ]
      |> Enum.join("__")

    Path.join(opts[:output_root], filename <> ".json")
  end
end
