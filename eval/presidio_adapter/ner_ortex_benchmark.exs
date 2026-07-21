defmodule Obscura.Eval.NEROrtexBenchmark do
  @moduledoc false

  alias Obscura.Conflict
  alias Obscura.Eval.Metrics
  alias Obscura.Eval.PresidioResearchLoader
  alias Obscura.Eval.Profile
  alias Obscura.Eval.Report
  alias Obscura.Recognizer.NER.Ortex

  @openmed_model_profile :ner_ortex_openmed_superclinical_small
  @openmed_hybrid_profile :hybrid_ner_ortex_openmed_superclinical_small
  @piiranha_model_profile :ner_ortex_piiranha_v1
  @piiranha_hybrid_profile :hybrid_ner_ortex_piiranha_v1
  @model_profiles [@openmed_model_profile, @piiranha_model_profile]
  @hybrid_profiles [@openmed_hybrid_profile, @piiranha_hybrid_profile]
  @supported_profiles @model_profiles ++ @hybrid_profiles
  @structured_recognizers [
    Obscura.Recognizer.Email,
    Obscura.Recognizer.Phone,
    Obscura.Recognizer.CreditCard,
    Obscura.Recognizer.USSSN,
    Obscura.Recognizer.IBAN,
    Obscura.Recognizer.IPAddress,
    Obscura.Recognizer.Domain,
    Obscura.Recognizer.URL,
    Obscura.Recognizer.DateTime,
    Obscura.Recognizer.Address,
    Obscura.Recognizer.PersonName,
    Obscura.Recognizer.Location,
    Obscura.Recognizer.Title
  ]

  def main(argv) do
    opts = parse_args(argv)
    dataset = Keyword.fetch!(opts, :dataset)
    template_split = Keyword.get(opts, :template_split, :all)
    run_suffix = Keyword.get(opts, :run_suffix, "ner_ortex")
    model_dir = Keyword.fetch!(opts, :model_dir)
    profile = Keyword.fetch!(opts, :profile)
    execution_providers = Keyword.fetch!(opts, :execution_providers)
    max_length = max_length(profile, Keyword.get(opts, :max_length))
    score_threshold = Keyword.get(opts, :score_threshold, 0.0)

    with {:ok, serving} <-
           Ortex.build(
             model_dir: model_dir,
             execution_providers: execution_providers,
             max_length: max_length
           ),
         {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: profile,
             template_split: template_split,
             invalid_span: :drop_sample
           ) do
      results = Enum.map(loaded.samples, &run_sample(profile, serving, &1, score_threshold))

      metrics =
        Metrics.score_results(results, profile,
          supported_entities: Profile.supported_entities(profile)
        )

      report =
        report(
          loaded,
          metrics,
          dataset,
          template_split,
          run_suffix,
          model_dir,
          profile,
          execution_providers,
          score_threshold,
          max_length
        )

      write_predictions(results, report.run_id)

      :ok =
        Report.write_pair(
          report,
          "eval/reports/#{report.run_id}.json",
          "eval/reports/#{report.run_id}.md"
        )

      IO.puts(
        Jason.encode!(%{
          run_id: report.run_id,
          samples: loaded.sample_count,
          metrics: Map.take(report.metrics, [:precision, :recall, :f1, :f2])
        })
      )
    else
      {:error, reason} ->
        IO.puts(:stderr, "NER Ortex benchmark failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp parse_args(argv) do
    {parsed, _rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          dataset: :string,
          template_split: :string,
          profile: :string,
          execution_providers: :string,
          max_length: :integer,
          score_threshold: :float,
          model_dir: :string,
          run_suffix: :string
        ]
      )

    if invalid != [], do: raise("invalid arguments: #{inspect(invalid)}")

    parsed
    |> Keyword.update(:dataset, :generated_large, &parse_dataset/1)
    |> Keyword.update(:template_split, :all, &parse_template_split/1)
    |> Keyword.update(:profile, @openmed_model_profile, &parse_profile/1)
    |> Keyword.update(:execution_providers, [:cpu], &parse_execution_providers/1)
    |> Keyword.put_new(:model_dir, System.get_env("OBSCURA_NER_ORTEX_MODEL_DIR"))
  end

  defp parse_dataset("generated_large"), do: :generated_large
  defp parse_dataset("generated_small"), do: :generated_small
  defp parse_dataset("synth_dataset_v2"), do: :synth_dataset_v2
  defp parse_dataset("nemotron_pii_test_subset"), do: :nemotron_pii_test_subset
  defp parse_dataset(dataset), do: raise("unsupported dataset: #{dataset}")

  defp parse_template_split("all"), do: :all
  defp parse_template_split("template_train"), do: :template_train
  defp parse_template_split("template_heldout"), do: :template_heldout

  defp parse_template_split(template_split),
    do: raise("unsupported template split: #{template_split}")

  defp parse_profile(profile) do
    with {:ok, parsed} <- Profile.from_string(profile),
         true <- parsed in @supported_profiles do
      parsed
    else
      _other -> raise("unsupported NER Ortex profile: #{profile}")
    end
  end

  defp parse_execution_providers(providers) do
    providers
    |> String.split(",", trim: true)
    |> Enum.map(&parse_execution_provider/1)
  end

  defp parse_execution_provider("cpu"), do: :cpu
  defp parse_execution_provider("coreml"), do: :coreml
  defp parse_execution_provider("cuda"), do: :cuda
  defp parse_execution_provider("tensorrt"), do: :tensorrt
  defp parse_execution_provider("acl"), do: :acl
  defp parse_execution_provider("dnnl"), do: :dnnl
  defp parse_execution_provider("onednn"), do: :onednn
  defp parse_execution_provider("directml"), do: :directml
  defp parse_execution_provider("rocm"), do: :rocm

  defp parse_execution_provider(provider),
    do: raise("unsupported NER Ortex execution provider: #{provider}")

  defp max_length(profile, nil)
       when profile in [@piiranha_model_profile, @piiranha_hybrid_profile],
       do: 256

  defp max_length(_profile, value), do: value

  defp run_sample(profile, serving, sample, score_threshold) do
    start = System.monotonic_time()

    predicted =
      case analyze(profile, serving, sample.text, score_threshold) do
        {:ok, results} ->
          Enum.map(results, &result_to_span/1)

        {:error, reason} ->
          raise("NER Ortex sample #{inspect(sample.id)} failed: #{inspect(reason)}")
      end

    latency_ms =
      System.monotonic_time()
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel.-(System.convert_time_unit(start, :native, :microsecond))
      |> Kernel./(1000)

    %{
      sample_id: sample.id,
      template_id: sample.template_id,
      expected: sample.spans,
      predicted: predicted,
      latency_ms: latency_ms
    }
  end

  defp analyze(profile, serving, text, score_threshold) when profile in @model_profiles do
    Ortex.analyze(serving, text,
      label_map: label_map(profile),
      score_threshold: score_threshold,
      include_text: false
    )
  end

  defp analyze(profile, serving, text, score_threshold) when profile in @hybrid_profiles do
    with {:ok, model_results} <-
           Ortex.analyze(serving, text,
             label_map: label_map(profile),
             score_threshold: score_threshold,
             include_text: false
           ),
         {:ok, structured_results} <- structured_results(profile, text) do
      model_results = filter_hybrid_model_results(profile, model_results)

      results =
        (structured_results ++ model_results)
        |> Conflict.resolve(:default)
        |> Enum.sort_by(&{&1.start, &1.end, &1.entity})

      {:ok, results}
    end
  end

  defp label_map(profile)
       when profile in [@openmed_model_profile, @openmed_hybrid_profile],
       do: :openmed_pii_superclinical_small

  defp label_map(profile) when profile in [@piiranha_model_profile, @piiranha_hybrid_profile],
    do: :piiranha_v1

  defp filter_hybrid_model_results(@piiranha_hybrid_profile, results),
    do: Enum.filter(results, &(&1.entity in [:person, :location]))

  defp filter_hybrid_model_results(_profile, results), do: results

  defp structured_results(profile, text) do
    @structured_recognizers
    |> Enum.reduce_while({:ok, []}, fn recognizer, {:ok, acc} ->
      case recognizer.analyze(text,
             profile: structured_profile(profile),
             entities: Profile.supported_entities(profile),
             include_text: false
           ) do
        {:ok, results} -> {:cont, {:ok, acc ++ results}}
        results when is_list(results) -> {:cont, {:ok, acc ++ results}}
        {:error, reason} -> {:halt, {:error, {:structured_recognizer_failed, recognizer, reason}}}
      end
    end)
  end

  defp structured_profile(@piiranha_hybrid_profile), do: :deterministic_plus
  defp structured_profile(profile), do: profile

  defp result_to_span(result) do
    %{
      entity: result.entity,
      byte_start: result.byte_start,
      byte_end: result.byte_end,
      char_start: result.start,
      char_end: result.end,
      source_entity: result.source_entity,
      score: result.score,
      value: result.text,
      metadata: result.metadata
    }
  end

  defp report(
         loaded,
         metrics,
         dataset,
         template_split,
         run_suffix,
         model_dir,
         profile,
         execution_providers,
         score_threshold,
         max_length
       ) do
    run_id = run_id(dataset, profile, template_split, run_suffix)

    Report.build(
      run_id: run_id,
      phase: "ner_ortex_compatibility",
      adapter: adapter(profile),
      profile: profile,
      dataset: %{
        name: loaded.name,
        source: loaded.source,
        version: loaded.version,
        sample_count: loaded.sample_count,
        original_sample_count: loaded.original_sample_count,
        invalid_sample_count: loaded.invalid_sample_count,
        template_split: loaded.template_split,
        scope: scope(template_split)
      },
      offset_mode: %{
        input: "tokenizer offsets",
        internal: "character",
        scoring: "byte",
        conversion: "ModelOutput.normalize/3"
      },
      metrics: metrics,
      limitations: limitations(profile, model_dir, execution_providers)
    )
    |> Map.put(:runtime_backend, %{
      adapter: :ortex,
      execution_providers: execution_providers,
      gpu_proof:
        if(:coreml in execution_providers,
          do:
            "ONNX Runtime CoreML execution provider requested; this is the Apple acceleration path for Ortex, not Emily.",
          else: "ONNX Runtime CPU execution provider requested."
        )
    })
    |> Map.put(:policy, %{score_threshold: score_threshold, max_length: max_length})
  end

  defp adapter(profile) when profile in @model_profiles, do: "Obscura.Recognizer.NER.Ortex"

  defp adapter(profile) when profile in @hybrid_profiles,
    do: "Obscura.StructuredDeterministic+Obscura.Recognizer.NER.Ortex"

  defp limitations(profile, model_dir, execution_providers) when profile in @model_profiles do
    [
      "Experimental local ONNX/Ortex token-classification adapter.",
      "Model profile: #{profile}; label map: #{label_map(profile)}.",
      "Model assets are local and ignored; model_dir=#{model_dir}.",
      "Execution providers requested: #{inspect(execution_providers)}.",
      "Tokenizer and ONNX export must remain pinned before any production recommendation.",
      "Boundary trimming is enabled in the adapter because the Python pipeline includes leading separators for this model."
    ]
  end

  defp limitations(profile, model_dir, execution_providers) when profile in @hybrid_profiles do
    [
      "Experimental opt-in hybrid profile: #{profile}; label map: #{label_map(profile)}.",
      "Model assets are local and ignored; model_dir=#{model_dir}.",
      "Execution providers requested: #{inspect(execution_providers)}.",
      "Structured PII is combined with model-backed token-classification spans.",
      hybrid_ownership_limitation(profile),
      "Default conflict handling lets deterministic structured spans win over overlapping model spans.",
      "This profile does not include privacy_filter_native."
    ]
  end

  defp hybrid_ownership_limitation(@piiranha_hybrid_profile),
    do: "Piiranha contributes only person/location; deterministic recognizers own structured PII."

  defp hybrid_ownership_limitation(_profile),
    do: "Model spans use the profile's documented OpenMed label policy."

  defp run_id(dataset, profile, :all, run_suffix),
    do: "presidio_compatibility_#{dataset}_#{profile}_full_#{run_suffix}"

  defp run_id(dataset, profile, template_split, run_suffix),
    do: "presidio_compatibility_#{dataset}_#{profile}_#{template_split}_full_#{run_suffix}"

  defp scope(:all), do: "full"
  defp scope(template_split), do: "#{template_split}_full"

  defp write_predictions(results, run_id) do
    path = "eval/predictions/#{run_id}.jsonl"
    File.mkdir_p!(Path.dirname(path))

    rows =
      Enum.map(results, fn result ->
        Jason.encode!(%{
          sample_id: result.sample_id,
          template_id: result.template_id,
          latency_ms: result.latency_ms,
          predictions: sanitize(result.predicted)
        })
      end)

    File.write!(path, Enum.join(rows, "\n") <> "\n")
  end

  defp sanitize(rows) do
    Enum.map(rows, fn row ->
      row
      |> Map.put(:value, "[omitted]")
      |> update_in([:metadata], &Map.drop(&1, [:output]))
    end)
  end
end

Obscura.Eval.NEROrtexBenchmark.main(System.argv())
