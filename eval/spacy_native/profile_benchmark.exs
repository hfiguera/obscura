defmodule Obscura.SpacyProfileBenchmark do
  @moduledoc false
  alias Obscura.Eval.{ComparisonProtocol, Metrics, PresidioResearchLoader}
  alias Obscura.Spacy.{Assets, Serving}

  def main do
    root = Path.expand("../..", __DIR__)
    baseline_path = Path.join(__DIR__, "results/comparison.json")
    baseline = read(baseline_path)

    model_dir =
      System.get_env("OBSCURA_SPACY_MODEL_DIR") ||
        Path.join(root, ".cache/spacy_cpu/en_core_web_lg-3.8.0")

    started = System.monotonic_time()
    {:ok, runtime} = Obscura.Profile.prepare(:spacy_cpu, model_dir: model_dir, workers: 1)
    prepare_ms = elapsed(started)

    try do
      datasets =
        Enum.map(baseline["datasets"], fn reference ->
          dataset =
            Enum.find(
              PresidioResearchLoader.known_datasets(),
              &(to_string(&1) == reference["name"])
            )

          {:ok, selection} = ComparisonProtocol.prepare(dataset)

          selection_name =
            if dataset == :generated_large,
              do: "generated_large_template_heldout",
              else: "#{dataset}_all"

          selection_path = Path.join(root, "eval/authoritative/selections/#{selection_name}.json")
          true = sha(selection_path) == reference["selection_sha256"]
          true = selection == read(selection_path)
          split = String.to_existing_atom(selection["dataset"]["template_split"]["name"])

          {:ok, loaded} =
            PresidioResearchLoader.load(
              dataset: dataset,
              profile: :regex_only,
              invalid_span: :drop_sample,
              template_split: split,
              template_train_ratio: 0.7
            )

          true = loaded.sha256 == selection["dataset"]["sha256"]
          true = Enum.map(loaded.samples, & &1.id) == selection["dataset"]["ordered_sample_ids"]
          entities = Enum.map(selection["entity_policy"]["entities"], &String.to_existing_atom/1)
          opts = [profile: runtime, entities: entities, include_text: false]

          runs =
            Enum.map(1..2, fn repetition ->
              Enum.each(Enum.take(loaded.samples, 5), &analyze(&1, opts))
              rows = Enum.map(loaded.samples, &analyze(&1, opts))

              predictions =
                Enum.map(rows, fn r ->
                  %{
                    sample_id: r.sample.id,
                    predictions:
                      Enum.map(r.predicted, &Map.take(&1, [:entity, :byte_start, :byte_end]))
                  }
                end)

              fingerprint = ComparisonProtocol.canonical_sha256(predictions)
              true = fingerprint == reference["modes"]["native"]["output_fingerprint_sha256"]

              metrics =
                Metrics.score_results(rows, :regex_only,
                  supported_entities: entities,
                  iou_threshold: 0.9
                )

              strict = %{
                true_positives: metrics.true_positives,
                false_positives: metrics.total_predicted_spans - metrics.true_positives,
                false_negatives: metrics.total_supported_expected_spans - metrics.true_positives
              }

              strict = Map.merge(strict, Metrics.ratios(strict))
              true = strict.f1 == reference["modes"]["native"]["strict_exact"]["f1"]

              %{
                repetition: repetition,
                output_fingerprint_sha256: fingerprint,
                shared_f1: metrics.f1,
                strict_exact: strict,
                latency: metrics.latency
              }
            end)

          IO.puts(
            Jason.encode!(%{
              dataset: dataset,
              profile: :spacy_cpu,
              identical_predictions: true,
              repetitions: 2
            })
          )

          %{
            name: dataset,
            documents: length(loaded.samples),
            selection_sha256: sha(selection_path),
            identical_to_native_prototype: true,
            runs: runs
          }
        end)

      source_files =
        [
          __ENV__.file,
          "mix.exs",
          "mix.lock",
          "lib/mix/tasks/obscura.spacy.build.ex",
          "lib/obscura/profile.ex",
          "lib/obscura/profile/preflight.ex",
          "lib/obscura/profile/runtime.ex",
          "lib/obscura/profile/preparation.ex",
          "lib/obscura/profile/preparer.ex",
          "lib/obscura/recognizer/spacy.ex",
          "native/spacy_cpu/build.rs",
          "native/spacy_cpu/Cargo.toml",
          "native/spacy_cpu/Cargo.lock"
        ] ++
          Path.wildcard("lib/obscura/spacy/*.ex") ++ Path.wildcard("native/spacy_cpu/src/*.rs")

      result = %{
        schema_version: 1,
        status: :experimental_unpromoted,
        profile: :spacy_cpu,
        created_at: DateTime.utc_now(),
        baseline_sha256: sha(baseline_path),
        preparation_including_hash_verification_ms: prepare_ms,
        runtime: Serving.status(runtime.resources.spacy),
        asset_hashes: Assets.hashes(),
        binary_sha256: sha(Assets.paths([]).native_binary),
        code_sha256: Map.new(source_files, &{Path.relative_to(Path.expand(&1), root), sha(&1)}),
        elixir: System.version(),
        otp: to_string(:erlang.system_info(:otp_release)),
        platform: to_string(:erlang.system_info(:system_architecture)),
        measurement:
          "live Obscura.analyze with :spacy_cpu runtime; includes bounded reservation, IPC, JSON, native inference, deterministic recognition and conflict handling; startup excluded",
        datasets: datasets
      }

      output = System.get_env("OBSCURA_SPACY_RESULTS_DIR") || Path.join(__DIR__, "results")
      File.mkdir_p!(output)
      path = Path.join(output, "profile.json")
      File.write!(path, Jason.encode!(result, pretty: true) <> "\n")
      render(result, output)
    after
      Serving.stop(runtime.resources.spacy)
    end
  end

  defp analyze(sample, opts) do
    start = System.monotonic_time()
    {:ok, predicted} = Obscura.analyze(sample.text, opts)
    %{sample: sample, expected: sample.spans, predicted: predicted, latency_ms: elapsed(start)}
  end

  defp render(result, output) do
    rows =
      Enum.map(result.datasets, fn d ->
        [first | _] = d.runs
        mean = Enum.sum(Enum.map(d.runs, & &1.latency.mean_ms)) / 2
        p95 = Enum.sum(Enum.map(d.runs, & &1.latency.p95_ms)) / 2

        "| #{d.name} | #{d.documents} | #{fmt(first.strict_exact.f1, 4)} | #{fmt(mean, 3)} ms | #{fmt(p95, 3)} ms |"
      end)

    report =
      [
        "# Experimental :spacy_cpu profile validation",
        "",
        "The packaged native runtime and public profile reproduce every final prediction from the measured native prototype on all 2,648 documents, in two repetitions. This check covers the profile's final detections after label filtering and conflict handling. No model or threshold changes were made.",
        "",
        "| Dataset | Documents | Strict F1 | Mean latency | p95 latency |",
        "|---|---:|---:|---:|---:|" | rows
      ] ++
        [
          "",
          "Latency wraps live Obscura.analyze using the prepared :spacy_cpu runtime: pool reservation, IPC/JSON, native inference, deterministic recognizers, and conflict handling. The table averages two runs; p95 is the mean of run p95s. Five warmup documents precede each run, with one native worker and one in-flight request. Platform: #{result.platform}; backend: #{result.runtime.backend}. Docker/emulation timings are validation measurements, not a deployment SLO or a hardware speed comparison.",
          "",
          "Preparation including verification of every pinned model file: #{fmt(result.preparation_including_hash_verification_ms, 1)} ms on a warm filesystem cache. Native worker peak RSS: #{fmt(result.runtime.sum_peak_worker_rss_bytes / 1_048_576, 1)} MiB. Worker RSS excludes BEAM memory and grows as mapped vector pages are touched; total assets remain about 408 MiB.",
          "",
          "The profile adds explicit ownership, bounded admission without a text queue, per-request deadlines, native response validation, and limited worker recovery. Saturation and failures return errors; analysis never prepares assets or downloads models.",
          "",
          "Accuracy remains below balanced, including Nemotron strict F1 0.5403 versus 0.5659. This is an experimental CPU option; balanced remains the general accuracy recommendation. No authoritative profile is promoted.",
          "",
          "Portable protocol tests exercise saturation, caller death, expiry, crashes, malformed responses, cleanup, and sanitized status. Opt-in real-model tests exercise UTF-8 offsets, analyze/redact/analyze_many, concurrency, ownership, worker loss, and corrupt assets. See [setup and lifecycle](../../../docs/spacy-cpu.md).",
          "",
          "Run from the repository root after building/exporting: `mix run --no-start eval/spacy_native/profile_benchmark.exs`. [profile.json](profile.json) records source, model, binary and baseline hashes. The original [feasibility results](RESULTS.md) remain available.",
          ""
        ]

    File.write!(Path.join(output, "PROFILE.md"), Enum.join(report, "\n"))
  end

  defp fmt(value, decimals), do: :erlang.float_to_binary(value * 1.0, decimals: decimals)

  defp elapsed(start),
    do: System.convert_time_unit(System.monotonic_time() - start, :native, :microsecond) / 1000

  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp sha(path), do: path |> Assets.sha256() |> then(fn {:ok, digest} -> digest end)
end

Obscura.SpacyProfileBenchmark.main()
