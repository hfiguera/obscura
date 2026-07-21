defmodule Obscura.Eval.PredictionExport do
  @moduledoc """
  Presidio-compatible JSONL prediction export.

  The export intentionally omits source text and detected values by default. Offsets
  are converted from Obscura's internal byte offsets to character offsets because
  Presidio evaluator tooling expects character positions.
  """

  alias Obscura.Eval.Offset
  alias Obscura.Eval.PresidioResearchLoader
  alias Obscura.Eval.Profile
  alias Obscura.Fixtures.ObscuraAnalyzerAdapter
  alias Obscura.Telemetry

  @default_out "eval/predictions/obscura_regex_only.jsonl"

  @doc """
  Runs prediction export and returns export metadata plus JSONL lines.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    profile = Keyword.get(opts, :profile, :regex_only)
    limit = Keyword.get(opts, :limit, 25)

    with {:ok, dataset} <- PresidioResearchLoader.load(profile: profile),
         samples <- PresidioResearchLoader.smoke_subset(dataset.samples, profile, limit),
         {:ok, rows} <- rows(samples, profile, opts) do
      {:ok,
       %{
         dataset: dataset.name,
         profile: profile,
         sample_count: length(samples),
         rows: rows,
         lines: Enum.map(rows, &Jason.encode!/1)
       }}
    end
  end

  @doc """
  Runs prediction export and writes a JSONL file.
  """
  @spec write(keyword()) :: :ok | {:error, term()}
  def write(opts \\ []) do
    out = Keyword.get(opts, :out, @default_out)

    with {:ok, export} <- run(opts),
         :ok <- File.mkdir_p(Path.dirname(out)) do
      emit(opts, export)
      File.write(out, Enum.map(export.lines, &[&1, ?\n]))
    end
  end

  defp rows(samples, profile, opts) do
    Enum.reduce_while(samples, {:ok, []}, fn sample, {:ok, acc} ->
      case row(sample, profile, opts) do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp row(sample, profile, opts) do
    start = System.monotonic_time()

    analyzer_opts =
      opts
      |> Keyword.get(:analyzer_opts, [])
      |> Keyword.put_new(:profile, profile)
      |> Keyword.put_new(:entities, Profile.supported_entities(profile))
      |> Keyword.put_new(:include_text, false)

    with {:ok, predictions} <- ObscuraAnalyzerAdapter.analyze(sample.text, analyzer_opts),
         {:ok, exported_predictions} <- export_predictions(sample.text, predictions) do
      {:ok,
       %{
         sample_id: sample.id,
         predictions: exported_predictions,
         latency_ms: elapsed_ms(start),
         profile: Atom.to_string(profile)
       }}
    end
  end

  defp export_predictions(text, predictions) do
    Enum.reduce_while(predictions, {:ok, []}, fn prediction, {:ok, acc} ->
      with {:ok, start_position} <- Offset.byte_to_char(text, prediction.byte_start),
           {:ok, end_position} <- Offset.byte_to_char(text, prediction.byte_end) do
        exported = %{
          entity_type: source_entity(prediction),
          start_position: start_position,
          end_position: end_position,
          score: prediction.score
        }

        {:cont, {:ok, [exported | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, predictions} -> {:ok, Enum.reverse(predictions)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp source_entity(%{source_entity: source_entity}) when is_binary(source_entity),
    do: source_entity

  defp source_entity(%{entity: entity}) when is_atom(entity),
    do: entity |> Atom.to_string() |> String.upcase()

  defp emit(opts, export) do
    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :eval, :prediction_export, :stop],
      %{sample_count: export.sample_count},
      %{
        status: :ok,
        profile: export.profile,
        dataset: export.dataset,
        sample_count: export.sample_count
      }
    )
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end
end
