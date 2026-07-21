defmodule Obscura.Eval.Smoke do
  @moduledoc """
  Presidio-Research smoke evaluation.
  """

  alias Obscura.Eval.Metrics
  alias Obscura.Eval.ModelOutputs
  alias Obscura.Eval.PresidioResearchLoader
  alias Obscura.Eval.Profile
  alias Obscura.Eval.Report
  alias Obscura.Fixtures.ObscuraAnalyzerAdapter
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.FakeServing

  @doc """
  Runs a smoke evaluation against the committed Presidio-Research dataset.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    profile = Keyword.get(opts, :profile, :regex_only)
    limit = Keyword.get(opts, :limit, 25)

    with {:ok, dataset} <- PresidioResearchLoader.load(profile: profile),
         samples <- PresidioResearchLoader.smoke_subset(dataset.samples, profile, limit),
         results <- run_samples(samples, profile),
         metrics <- metrics(results, profile),
         report <- build_report(dataset, samples, metrics, profile) do
      {:ok, report}
    end
  end

  @doc """
  Runs smoke evaluation and writes reports.
  """
  @spec write_report(keyword()) :: :ok | {:error, term()}
  def write_report(opts \\ []) do
    case run(opts) do
      {:ok, report} ->
        Report.write_pair(
          report,
          "eval/reports/#{report.run_id}.json",
          "eval/reports/#{report.run_id}.md"
        )

      {:error, {:missing_presidio_research_dataset, path, reason}} ->
        write_missing_dataset_report(path, reason)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_samples(samples, profile) do
    Enum.map(samples, fn sample ->
      start = System.monotonic_time()

      {:ok, predictions} =
        ObscuraAnalyzerAdapter.analyze(sample.text, analyzer_opts(sample, profile))

      elapsed = elapsed_ms(start)

      %{
        sample: sample,
        expected: sample.spans,
        predicted: predictions,
        latency_ms: elapsed
      }
    end)
  end

  defp metrics(results, profile) do
    Metrics.score_results(results, profile)
  end

  defp build_report(dataset, samples, metrics, profile) do
    Report.build(
      run_id: "phase_4_presidio_research_smoke",
      phase: "phase_4",
      adapter: "Obscura.Fixtures.ObscuraAnalyzerAdapter",
      profile: profile,
      dataset: %{
        name: dataset.name,
        source: dataset.source,
        version: dataset.version,
        sample_count: length(samples),
        full_sample_count: dataset.sample_count,
        smoke: true
      },
      offset_mode: %{
        input: "character",
        internal: "byte",
        scoring: "byte",
        conversion: "validated"
      },
      metrics: metrics,
      limitations: [
        "Results include deterministic recognizers.",
        "The nlp profile uses deterministic fake NER outputs derived from gold spans for Phase 4 behavior checks, not real model accuracy.",
        "Remote recognizers, image redaction, document redaction, and production model serving are not evaluated."
      ]
    )
  end

  defp analyzer_opts(sample, :nlp) do
    [
      profile: :nlp,
      entities: Profile.supported_entities(:nlp),
      recognizers: [
        :default,
        {NER, serving: FakeServing.new(%{sample.text => ModelOutputs.from_sample(sample)})}
      ]
    ]
  end

  defp analyzer_opts(_sample, profile), do: [profile: profile]

  defp write_missing_dataset_report(path, _reason) do
    metrics =
      Metrics.score([], [], :regex_only,
        total_samples: 0,
        latency_ms: []
      )

    report =
      Report.build(
        run_id: "phase_3_presidio_research_smoke",
        phase: "phase_3",
        adapter: "Obscura.Fixtures.ObscuraAnalyzerAdapter",
        profile: :regex_only,
        dataset: %{
          name: "synth_dataset_v2",
          source: path,
          version: "presidio-research-snapshot",
          sample_count: 0,
          smoke: true
        },
        offset_mode: %{
          input: "character",
          internal: "byte",
          scoring: "byte",
          conversion: "not_run"
        },
        metrics: metrics,
        limitations: [
          "Presidio-Research dataset was not available for smoke scoring.",
          "Restore the committed benchmark snapshots to enable dataset smoke scoring."
        ]
      )

    Report.write_pair(
      report,
      "eval/reports/phase_3_presidio_research_smoke.json",
      "eval/reports/phase_3_presidio_research_smoke.md"
    )
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end
end
