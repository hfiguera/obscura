defmodule Obscura.Eval.GLiNERUrchadeProviderComparison do
  alias Obscura.Recognizer.GLiNER.Ortex

  @texts [
    "Rachel works at Google in Paris.",
    "José Álvarez joined Acme GmbH in München.",
    "Contact Dr. Rachel Green at Northwest Memorial Hospital in New York City about patient Maria Garcia."
  ]

  def run do
    model_dir =
      System.get_env("OBSCURA_GLINER_URCHADE_MODEL_DIR") ||
        raise "OBSCURA_GLINER_URCHADE_MODEL_DIR is required"

    output =
      System.get_env("OBSCURA_GLINER_PROVIDER_COMPARISON_OUTPUT") ||
        "eval/reports/urchade-gliner-coreml-comparison.json"

    repetitions =
      System.get_env("OBSCURA_GLINER_PROVIDER_COMPARISON_REPETITIONS", "10")
      |> String.to_integer()

    cpu = measure(:cpu, model_dir, repetitions)
    coreml = measure(:coreml, model_dir, repetitions)
    profile = model_dir |> profile_coreml() |> Map.delete(:profile_path)

    report = %{
      schema_version: 1,
      generated_at: DateTime.utc_now(),
      model: %{
        id: "urchade/gliner_multi_pii-v1",
        revision: "1fcf13e85f4eef5394e1fcd406cf2ca9ea82351d",
        onnx_sha256: "da317b3dafb6ea26c19bc8725d3c969f788a4669e52e080cf5f56a4e057581b5"
      },
      host: %{
        os: :os.type() |> inspect(),
        architecture: :erlang.system_info(:system_architecture) |> List.to_string(),
        logical_processors: :erlang.system_info(:logical_processors_available)
      },
      settings: %{
        texts: length(@texts),
        repetitions: repetitions,
        warmup_rounds: 2,
        coreml: %{
          model_format: :ml_program,
          compute_units: :cpu_and_gpu,
          require_static_input_shapes: false,
          enable_on_subgraphs: false
        }
      },
      cpu: Map.delete(cpu, :outputs),
      coreml: Map.delete(coreml, :outputs),
      parity: parity(cpu.outputs, coreml.outputs),
      provider_evidence: profile,
      conclusion: conclusion(cpu, coreml, profile),
      limitations: [
        :dynamic_onnx_dimensions,
        :unsupported_coreml_matmul_shapes,
        :cpu_fallback_observed,
        :coreml_has_no_gpu_only_compute_unit
      ]
    }

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode_to_iodata!(report, pretty: true))
    IO.puts(output)
  end

  defp measure(provider, model_dir, repetitions) do
    {build_us, serving} =
      timed(fn ->
        {:ok, serving} =
          Ortex.build(
            model: :urchade_gliner_multi_pii_v1,
            model_dir: model_dir,
            execution_providers: [provider]
          )

        serving
      end)

    {first_us, _first} = timed(fn -> run!(serving, hd(@texts)) end)

    Enum.each(1..2, fn _round -> Enum.each(@texts, &run!(serving, &1)) end)

    measurements =
      for _round <- 1..repetitions, text <- @texts do
        {elapsed_us, _spans} = timed(fn -> run!(serving, text) end)
        elapsed_us
      end

    outputs = Enum.map(@texts, &(run!(serving, &1) |> normalize_spans()))
    total_us = Enum.sum(measurements)

    %{
      provider: provider,
      build_ms: build_us / 1_000,
      first_inference_ms: first_us / 1_000,
      warm_latency_ms: statistics(measurements),
      sequential_throughput_requests_per_second: length(measurements) * 1_000_000 / total_us,
      outputs: outputs
    }
  end

  defp profile_coreml(model_dir) do
    profile_prefix =
      Path.expand(
        System.get_env(
          "OBSCURA_GLINER_PROVIDER_PROFILE_PREFIX",
          ".cache/ortex-profiles/urchade-coreml-comparison"
        )
      )

    {:ok, serving} =
      Ortex.build(
        model: :urchade_gliner_multi_pii_v1,
        model_dir: model_dir,
        execution_providers: [:coreml],
        profile_prefix: profile_prefix
      )

    Enum.each(@texts, &run!(serving, &1))

    case Ortex.finish_profiling(serving) do
      {:ok, summary} -> summary
      {:error, reason} -> %{status: :profile_failed, error: inspect(reason)}
    end
  end

  defp run!(serving, text) do
    {:ok, spans} = Ortex.run(serving, text)
    spans
  end

  defp normalize_spans(spans) do
    spans
    |> Enum.map(fn span ->
      %{
        entity: span.entity,
        byte_start: span.byte_start,
        byte_end: span.byte_end,
        text: span.text,
        score: span.score
      }
    end)
    |> Enum.sort_by(&{&1.byte_start, &1.byte_end, &1.entity})
  end

  defp parity(cpu_outputs, coreml_outputs) do
    pairs = Enum.zip(List.flatten(cpu_outputs), List.flatten(coreml_outputs))

    span_fields_match =
      Enum.map(cpu_outputs, &Enum.map(&1, fn span -> Map.drop(span, [:score]) end)) ==
        Enum.map(coreml_outputs, &Enum.map(&1, fn span -> Map.drop(span, [:score]) end))

    score_differences =
      Enum.map(pairs, fn {cpu, coreml} -> abs(cpu.score - coreml.score) end)

    %{
      exact_span_fields_match: span_fields_match,
      compared_scores: length(score_differences),
      max_absolute_score_difference: Enum.max(score_differences, fn -> 0.0 end),
      mean_absolute_score_difference:
        if(score_differences == [],
          do: 0.0,
          else: Enum.sum(score_differences) / length(score_differences)
        )
    }
  end

  defp conclusion(cpu, coreml, profile) do
    speedup = cpu.warm_latency_ms.mean / coreml.warm_latency_ms.mean

    %{
      coreml_participation_verified: profile[:coreml_participated] == true,
      cpu_fallback_observed: profile[:cpu_fallback_observed] == true,
      coreml_warm_latency_speedup: speedup,
      coreml_warm_latency_slowdown: 1.0 / speedup,
      latency_improved: speedup > 1.0,
      gpu_only_proven: false,
      promotion_decision: if(speedup > 1.0, do: :eligible_for_review, else: :rejected)
    }
  end

  defp statistics(values_us) do
    sorted = Enum.sort(values_us)

    %{
      count: length(sorted),
      mean: Enum.sum(sorted) / length(sorted) / 1_000,
      p50: percentile(sorted, 0.50) / 1_000,
      p95: percentile(sorted, 0.95) / 1_000,
      p99: percentile(sorted, 0.99) / 1_000,
      min: hd(sorted) / 1_000,
      max: List.last(sorted) / 1_000
    }
  end

  defp percentile(sorted, percentile) do
    index = ceil(percentile * length(sorted)) - 1
    Enum.at(sorted, max(index, 0))
  end

  defp timed(fun) do
    started = System.monotonic_time()
    value = fun.()

    elapsed =
      System.monotonic_time()
      |> Kernel.-(started)
      |> System.convert_time_unit(:native, :microsecond)

    {elapsed, value}
  end
end

Obscura.Eval.GLiNERUrchadeProviderComparison.run()
