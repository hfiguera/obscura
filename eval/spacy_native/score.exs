defmodule Obscura.SpacyNative.Score do
  @moduledoc false
  alias Obscura.Eval.{ComparisonProtocol, Metrics, PresidioResearchLoader}
  alias Obscura.SpacyNative.{Recognizer, Worker}
  @structured [:email, :phone, :url, :ip_address, :credit_card, :us_ssn]
  @metric_keys [
    :precision,
    :recall,
    :f1,
    :f2,
    :true_positives,
    :false_positives,
    :false_negatives,
    :offset_mismatches,
    :wrong_entity_type,
    :total_supported_expected_spans,
    :total_predicted_spans,
    :total_samples,
    :unsupported_expected_spans,
    :span_iou,
    :per_entity,
    :latency
  ]

  def main([path]) do
    experiment = read(path)
    root = Path.expand("../..", __DIR__)

    binary =
      Path.expand(
        "../../native/spacy_cpu/target/aarch64-apple-darwin/release/obscura-spacy-native-prototype",
        __DIR__
      )

    true = sha(binary) == experiment["binary_sha256"]
    true = sha(Path.join(__DIR__, "assets/model.json")) == experiment["model_sha256"]
    {:ok, native} = Worker.start_link()

    {:ok, python} =
      Worker.start_link(
        binary: Path.join(root, ".presidio-authoritative-venv/bin/python"),
        args: [Path.join(__DIR__, "python_worker.py")]
      )

    workers = %{native: native, python: python, fast: nil}

    try do
      datasets =
        Enum.map(experiment["datasets"], fn entry ->
          {samples, entities} = load(entry)
          options = [profile: :deterministic_plus, entities: entities, include_text: false]

          runs =
            Enum.flat_map(1..experiment["repetitions"], fn repetition ->
              modes =
                if rem(repetition, 2) == 1,
                  do: [:fast, :python, :native],
                  else: [:native, :python, :fast]

              measured =
                Map.new(modes, fn mode ->
                  worker = workers[mode]
                  Enum.each(Enum.take(samples, 5), &analyze(&1, worker, options))
                  rows = Enum.map(samples, &analyze(&1, worker, options))

                  if mode != :fast do
                    saved =
                      Enum.find(
                        entry["runs"],
                        &(&1["mode"] == to_string(mode) and &1["repetition"] == repetition)
                      )

                    true = sha(saved["path"]) == saved["sha256"]
                    reference = read(saved["path"])
                    true = Enum.map(samples, & &1.id) == Enum.map(reference, & &1["sample_id"])

                    Enum.zip(rows, reference)
                    |> Enum.each(fn {row, previous} ->
                      true =
                        canonical(row.stats["predictions"]) == canonical(previous["predictions"])
                    end)
                  end

                  {mode, rows}
                end)

              true = fingerprints(measured.native) == fingerprints(measured.python)

              for mode <- [:native, :python] do
                true = structured(measured[mode]) == structured(measured.fast)
              end

              Enum.map(modes, fn mode ->
                summarize(
                  measured[mode],
                  mode,
                  repetition,
                  entities,
                  Path.dirname(path),
                  entry["name"]
                )
              end)
            end)

          for {_mode, rows} <- Enum.group_by(runs, & &1.mode) do
            true =
              rows |> Enum.map(& &1.output_fingerprint_sha256) |> Enum.uniq() |> length() == 1
          end

          concurrency =
            if entry["name"] == "nemotron_pii_test_subset",
              do: concurrency(samples, options, experiment["repetitions"]),
              else: []

          native_fingerprint = Enum.find(runs, &(&1.mode == :native)).output_fingerprint_sha256
          true = Enum.all?(concurrency, &(&1.output_fingerprint_sha256 == native_fingerprint))

          IO.puts(
            Jason.encode!(%{
              phase: :live_scoring,
              dataset: entry["name"],
              native_python_equal: true,
              structured_unchanged: true
            })
          )

          Map.merge(entry, %{live_runs: runs, concurrency: concurrency})
        end)

      result =
        experiment
        |> Map.put("datasets", datasets)
        |> Map.put("live_workers", Map.new([:native, :python], &{&1, Worker.ready(workers[&1])}))
        |> Map.put("elixir", System.version())
        |> Map.put("otp", to_string(:erlang.system_info(:otp_release)))
        |> Map.put("scoring_code_sha256", sha(__ENV__.file))
        |> Map.put("worker_code_sha256", sha(Path.join(__DIR__, "native.exs")))
        |> Map.put("python_control_code_sha256", sha(Path.join(__DIR__, "python_worker.py")))
        |> Map.put(
          "measurement",
          "serial live Obscura.analyze including Port IPC, JSON, normal deterministic recognizers and conflict resolution; startup excluded"
        )

      File.write!(
        Path.join(Path.dirname(path), "results.json"),
        Jason.encode!(result, pretty: true) <> "\n"
      )
    after
      GenServer.stop(native)
      GenServer.stop(python)
    end
  end

  defp load(entry) do
    dataset =
      Enum.find(PresidioResearchLoader.known_datasets(), &(to_string(&1) == entry["name"]))

    true = not is_nil(dataset)
    selection = read(entry["selection_path"])
    true = sha(entry["selection_path"]) == entry["selection_sha256"]
    {:ok, prepared} = ComparisonProtocol.prepare(dataset)
    true = prepared == selection
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
    {loaded.samples, Enum.map(selection["entity_policy"]["entities"], &String.to_existing_atom/1)}
  end

  defp analyze(sample, worker, options) do
    opts =
      if worker,
        do:
          Keyword.put(options, :recognizers, [
            {Recognizer, worker: worker, stats_recipient: self()}
          ]),
        else: options

    started = System.monotonic_time()
    {:ok, predicted} = Obscura.analyze(sample.text, opts)
    ms = elapsed(started)

    stats =
      if worker do
        receive do
          {:spacy_native_stats, stats} -> stats
        after
          0 -> raise "missing native stats"
        end
      else
        %{}
      end

    %{sample: sample, expected: sample.spans, predicted: predicted, latency_ms: ms, stats: stats}
  end

  defp summarize(rows, mode, repetition, entities, out, dataset) do
    metrics =
      Metrics.score_results(rows, :regex_only, supported_entities: entities, iou_threshold: 0.9)

    strict = %{
      true_positives: metrics.true_positives,
      false_positives: metrics.total_predicted_spans - metrics.true_positives,
      false_negatives: metrics.total_supported_expected_spans - metrics.true_positives
    }

    predictions = fingerprints(rows)
    path = Path.join(out, "#{dataset}__live_#{mode}__r#{repetition}__predictions.json")
    File.write!(path, Jason.encode!(predictions) <> "\n")

    %{
      mode: mode,
      repetition: repetition,
      metrics:
        metrics |> Map.take(@metric_keys) |> Map.update!(:span_iou, &Map.delete(&1, :examples)),
      strict_exact: Map.merge(strict, Metrics.ratios(strict)),
      output_fingerprint_sha256: ComparisonProtocol.canonical_sha256(predictions),
      predictions_path: path,
      predictions_sha256: sha(path),
      latency: distribution(Enum.map(rows, & &1.latency_ms)),
      native_components:
        Map.new(
          ["native_ms", "tokenization_ms", "encoding_ms", "decoding_ms", "inference_ms"],
          fn key ->
            values =
              Enum.flat_map(rows, fn r -> if r.stats[key], do: [r.stats[key]], else: [] end)

            {key, if(values == [], do: nil, else: distribution(values))}
          end
        ),
      peak_worker_rss_bytes: Enum.max(Enum.map(rows, &Map.get(&1.stats, "peak_rss_bytes", 0)))
    }
  end

  defp concurrency(samples, options, repetitions) do
    Enum.flat_map([1, 2, 4], fn count ->
      workers =
        Enum.map(1..count, fn _ ->
          {:ok, pid} = Worker.start_link()
          pid
        end)

      try do
        Enum.each(workers, fn worker ->
          Enum.each(Enum.take(samples, 5), &analyze(&1, worker, options))
        end)

        Enum.map(1..repetitions, fn repetition ->
          started = System.monotonic_time()

          rows =
            samples
            |> Enum.with_index()
            |> Enum.group_by(fn {_, i} -> rem(i, count) end)
            |> Task.async_stream(
              fn {index, pairs} ->
                Enum.map(pairs, fn {sample, i} ->
                  {i, analyze(sample, Enum.at(workers, index), options)}
                end)
              end,
              max_concurrency: count,
              timeout: 120_000
            )
            |> Enum.flat_map(fn {:ok, rows} -> rows end)
            |> Enum.sort_by(&elem(&1, 0))
            |> Enum.map(&elem(&1, 1))

          wall_ms = elapsed(started)

          %{
            workers: count,
            repetition: repetition,
            documents: length(samples),
            wall_ms: wall_ms,
            documents_per_second: length(samples) * 1000 / wall_ms,
            latency: distribution(Enum.map(rows, & &1.latency_ms)),
            output_fingerprint_sha256: ComparisonProtocol.canonical_sha256(fingerprints(rows)),
            sum_peak_worker_rss_bytes:
              rows
              |> Enum.with_index()
              |> Enum.group_by(fn {_, i} -> rem(i, count) end)
              |> Enum.map(fn {_, rows} ->
                Enum.max(Enum.map(rows, fn {r, _} -> r.stats["peak_rss_bytes"] end))
              end)
              |> Enum.sum()
          }
        end)
      after
        Enum.each(workers, &GenServer.stop/1)
      end
    end)
  end

  defp canonical(predictions),
    do: Enum.map(predictions, &Map.take(&1, ["label", "byte_start", "byte_end"]))

  defp fingerprints(rows),
    do:
      Enum.map(rows, fn r ->
        %{
          sample_id: r.sample.id,
          predictions: Enum.map(r.predicted, &Map.take(&1, [:entity, :byte_start, :byte_end]))
        }
      end)

  defp structured(rows),
    do:
      Enum.map(rows, fn r ->
        r.predicted
        |> Enum.filter(&(&1.entity in @structured))
        |> Enum.map(&Map.take(&1, [:entity, :byte_start, :byte_end]))
      end)

  defp distribution(values) do
    sorted = Enum.sort(values)

    %{
      mean_ms: Enum.sum(values) / length(values),
      p50_ms: Enum.at(sorted, trunc(Float.ceil(length(values) * 0.5)) - 1),
      p95_ms: Enum.at(sorted, trunc(Float.ceil(length(values) * 0.95)) - 1),
      max_ms: List.last(sorted)
    }
  end

  defp elapsed(started),
    do: System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond) / 1000

  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp sha(path),
    do: path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
