defmodule Obscura.Eval.Operational.OpenMedOptimization do
  @moduledoc false

  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Eval.Operational.Metadata
  alias Obscura.Eval.Operational.ResourceSampler
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.StageTracker
  alias Obscura.Eval.Operational.Statistics
  alias Obscura.PrivacyFilter.Tokenization

  @variants [:baseline, :bucketing, :raw_logits, :combined]
  @default_buckets [192, 256, 384, 512, 768]
  @default_bucket_threshold 129

  @spec variants() :: [atom()]
  def variants, do: @variants

  @spec default_buckets() :: [pos_integer()]
  def default_buckets, do: @default_buckets

  @spec default_bucket_threshold() :: pos_integer()
  def default_bucket_threshold, do: @default_bucket_threshold

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) do
    variant = Keyword.fetch!(opts, :variant)
    dataset_name = Keyword.fetch!(opts, :dataset)

    with :ok <- validate_variant(variant),
         {:ok, dataset} <- Dataset.load(dataset_name, profile: :openmed_pii),
         {:ok, tracker} <- StageTracker.start_link(),
         {:ok, runtime, preparation_ms} <-
           Common.prepare_runtime(:openmed_pii, tracker, runtime_options(variant, opts)),
         {:ok, samples, selection} <- select_samples(dataset, runtime, opts),
         {:ok, host} <- start_host(runtime, Keyword.get(opts, :concurrency, 4)) do
      try do
        cold = run_pass(host, samples, opts)
        :ok = RuntimeHost.reset_diagnostic_shapes(host)
        warm_1 = run_pass(host, samples, opts)
        :ok = RuntimeHost.reset_diagnostic_shapes(host)
        warm_2 = run_pass(host, samples, opts)

        {:ok,
         %{
           schema_version: 1,
           status: :exploratory,
           generated_at: DateTime.utc_now(),
           experiment: %{
             variant: variant,
             repetition: Keyword.get(opts, :repetition, 1),
             buckets: buckets_for(variant, opts),
             bucket_threshold: bucket_threshold_for(variant, opts),
             logprob_conversion: logprob_conversion_for(variant)
           },
           dataset: Common.dataset_metadata(dataset),
           sample_selection: selection,
           preparation_ms: preparation_ms,
           backend: Common.environment(:openmed_pii, runtime.backend_metadata),
           cold_pass: cold,
           warm_passes: [warm_1, warm_2],
           source: Metadata.git()
         }}
      after
        GenServer.stop(host)
        if Process.alive?(tracker), do: Agent.stop(tracker)
      end
    end
  end

  defp runtime_options(variant, opts) do
    [
      privacy_filter_checkpoint: Keyword.get(opts, :privacy_filter_checkpoint),
      sequence_length_buckets: buckets_for(variant, opts),
      sequence_length_bucket_threshold: bucket_threshold_for(variant, opts),
      logprob_conversion: logprob_conversion_for(variant)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp buckets_for(variant, opts) when variant in [:bucketing, :combined],
    do: Keyword.get(opts, :buckets, @default_buckets)

  defp buckets_for(_variant, _opts), do: nil

  defp bucket_threshold_for(variant, opts) when variant in [:bucketing, :combined],
    do: Keyword.get(opts, :bucket_threshold, @default_bucket_threshold)

  defp bucket_threshold_for(_variant, _opts), do: nil

  defp logprob_conversion_for(:raw_logits), do: :raw_logits
  defp logprob_conversion_for(:combined), do: :raw_logits

  defp logprob_conversion_for(_variant), do: :reference

  defp validate_variant(variant) when variant in @variants, do: :ok

  defp validate_variant(variant),
    do: {:error, {:unsupported_openmed_optimization_variant, variant}}

  defp select_samples(dataset, runtime, opts) do
    count = min(Keyword.get(opts, :sample_count, 32), length(dataset.samples))
    serving = runtime.resources.privacy_filter

    rows =
      Enum.map(dataset.samples, fn sample ->
        {:ok, tokenization} = Tokenization.from_config(serving.config, sample.text)
        {length(tokenization.token_ids), sample}
      end)
      |> Enum.sort_by(fn {length, sample} -> {length, to_string(sample.id)} end)

    samples =
      for index <- 0..(count - 1) do
        {_length, sample} = Enum.at(rows, round(index * (length(rows) - 1) / max(count - 1, 1)))
        sample
      end

    ids = Enum.map(samples, & &1.id)
    length_by_sample = Map.new(rows, fn {length, sample} -> {sample, length} end)
    lengths = Enum.map(samples, &Map.fetch!(length_by_sample, &1))

    selection = %{
      method: :token_length_stratified,
      count: length(samples),
      sample_ids_sha256: hash(ids),
      token_length: Statistics.summarize(lengths)
    }

    {:ok, samples, selection}
  rescue
    _error -> {:error, :openmed_optimization_sample_selection_failed}
  end

  defp start_host(runtime, concurrency) do
    RuntimeHost.start_link(
      runtime: runtime,
      max_in_flight: concurrency,
      diagnostics: true
    )
  end

  defp run_pass(host, samples, opts) do
    concurrency = Keyword.get(opts, :concurrency, 4)
    timeout = Keyword.get(opts, :request_timeout, 300_000)

    {:ok, sampler} = ResourceSampler.start_link(gpu: true, interval: 50)
    started = System.monotonic_time()

    rows =
      samples
      |> Task.async_stream(
        &run_sample(host, &1, timeout),
        max_concurrency: concurrency,
        ordered: false,
        timeout: timeout + 2_000,
        on_timeout: :kill_task
      )
      |> Enum.map(&normalize_row/1)

    elapsed_ms = elapsed_ms(started)
    resources = ResourceSampler.snapshot(sampler)
    GenServer.stop(sampler)

    completed = Enum.filter(rows, &(&1.status == :completed))

    %{
      elapsed_ms: elapsed_ms,
      concurrency: concurrency,
      completed: length(completed),
      failed: Enum.count(rows, &(&1.status == :failed)),
      timed_out: Enum.count(rows, &(&1.status == :timed_out)),
      throughput_rps: Statistics.throughput(length(completed), elapsed_ms),
      latency_ms: completed |> Enum.map(& &1.latency_ms) |> Statistics.summarize(),
      service_ms: completed |> Enum.map(& &1.service_ms) |> Statistics.summarize(),
      stages: summarize_stages(completed),
      padding: summarize_padding(completed),
      shapes: summarize_shapes(completed),
      output_fingerprint: output_fingerprint(completed),
      resources: resources
    }
  end

  defp run_sample(host, sample, timeout) do
    started = System.monotonic_time()

    case RuntimeHost.analyze(host, sample.text, timeout: timeout, include_text: false) do
      {:ok, results, service} ->
        %{
          status: :completed,
          sample_id: sample.id,
          latency_ms: elapsed_ms(started),
          service_ms: service.service_ms,
          diagnostics: service.diagnostics,
          model_shape: service.model_shape,
          output: safe_output(results)
        }

      {:error, %{code: code}} when code in [:request_timeout, :caller_timeout] ->
        %{status: :timed_out}

      {:error, _reason} ->
        %{status: :failed}
    end
  end

  defp normalize_row({:ok, row}), do: row
  defp normalize_row({:exit, _reason}), do: %{status: :failed}

  defp summarize_stages(rows) do
    rows
    |> Enum.flat_map(fn row ->
      Enum.map(row.diagnostics.stages, fn {stage, summary} -> {stage, summary.total_ms} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {stage, values} -> {stage, Statistics.summarize(values)} end)
  end

  defp summarize_padding(rows) do
    metadata = Enum.map(rows, & &1.diagnostics.metadata)

    %{
      packed_tokens:
        metadata
        |> Enum.map(&Map.get(&1, :model_packed_tokens))
        |> numbers()
        |> Statistics.summarize(),
      padding_tokens:
        metadata
        |> Enum.map(&Map.get(&1, :model_padding_tokens))
        |> numbers()
        |> Statistics.summarize(),
      padding_ratio:
        metadata
        |> Enum.map(&Map.get(&1, :model_padding_ratio))
        |> numbers()
        |> Statistics.summarize()
    }
  end

  defp summarize_shapes(rows) do
    shapes = Enum.map(rows, & &1.model_shape)
    measured = Enum.filter(shapes, &match?(%{sequence_length: _}, &1))
    first = Enum.filter(measured, & &1.first_seen)
    repeated = Enum.reject(measured, & &1.first_seen)

    %{
      distinct: measured |> Enum.map(& &1.sequence_length) |> MapSet.new() |> MapSet.size(),
      first_seen: length(first),
      repeated: length(repeated),
      first_seen_model_ms:
        first |> Enum.map(& &1.model_ms) |> numbers() |> Statistics.summarize(),
      repeated_model_ms:
        repeated |> Enum.map(& &1.model_ms) |> numbers() |> Statistics.summarize()
    }
  end

  defp output_fingerprint(rows) do
    rows
    |> Enum.sort_by(&to_string(&1.sample_id))
    |> Enum.map(&{&1.sample_id, &1.output})
    |> hash()
  end

  defp safe_output(results) do
    Enum.map(results, fn result ->
      %{
        entity: result.entity,
        byte_start: result.byte_start,
        byte_end: result.byte_end
      }
    end)
  end

  defp numbers(values), do: Enum.filter(values, &is_number/1)

  defp hash(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
