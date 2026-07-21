defmodule Obscura.Eval.Operational.LoadRunner do
  @moduledoc """
  Bounded closed-loop load runner for prepared product-profile runtimes.
  """

  alias Obscura.Eval.Operational.ResourceSampler
  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.Statistics

  @spec run(pid(), [map()], keyword()) :: map()
  def run(host, samples, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 1)
    repetitions = Keyword.get(opts, :repetitions, 2)
    timeout = Keyword.get(opts, :timeout, 120_000)
    gpu? = Keyword.get(opts, :gpu, false)

    Enum.map(1..repetitions, fn repetition ->
      run_repetition(host, samples,
        concurrency: concurrency,
        repetition: repetition,
        timeout: timeout,
        gpu: gpu?
      )
    end)
    |> aggregate_repetitions(concurrency)
  end

  @spec sustained(pid(), [map()], keyword()) :: map()
  def sustained(host, samples, opts \\ []) do
    duration_ms = Keyword.get(opts, :duration_ms, 60_000)
    request_count = Keyword.get(opts, :request_count)
    concurrency = Keyword.get(opts, :concurrency, 4)
    timeout = Keyword.get(opts, :timeout, 120_000)
    started = monotonic_time()
    deadline = started + milliseconds_to_native(duration_ms)
    midpoint = started + milliseconds_to_native(duration_ms / 2)

    {:ok, sampler} =
      ResourceSampler.start_link(
        gpu: Keyword.get(opts, :gpu, false),
        interval: Keyword.get(opts, :sample_interval, 50)
      )

    sample_tuple = List.to_tuple(samples)
    budget = request_budget(request_count)

    worker_context = %{
      stride: concurrency,
      deadline: deadline,
      midpoint: midpoint,
      timeout: timeout,
      budget: budget
    }

    workers =
      0..(concurrency - 1)
      |> Task.async_stream(
        fn worker ->
          sustained_worker(host, sample_tuple, worker, worker_context, empty_worker_summary())
        end,
        max_concurrency: concurrency,
        ordered: true,
        timeout: duration_ms + timeout + 2_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, summary} -> summary
        {:exit, _reason} -> Map.put(empty_worker_summary(), :failed, 1)
      end)

    resources = ResourceSampler.snapshot(sampler)
    GenServer.stop(sampler)

    summarize_sustained(
      workers,
      elapsed_ms(started),
      duration_ms,
      request_count,
      concurrency,
      resources
    )
  end

  defp run_repetition(host, samples, opts) do
    {:ok, sampler} =
      ResourceSampler.start_link(
        gpu: Keyword.fetch!(opts, :gpu),
        interval: Keyword.get(opts, :sample_interval, 50)
      )

    started = monotonic_time()
    timeout = Keyword.fetch!(opts, :timeout)

    rows = run_requests(host, samples, Keyword.fetch!(opts, :concurrency), timeout)
    run_elapsed_ms = elapsed_ms(started)
    resources = ResourceSampler.snapshot(sampler)
    GenServer.stop(sampler)

    summarize_rows(
      rows,
      run_elapsed_ms,
      Keyword.fetch!(opts, :concurrency),
      Keyword.fetch!(opts, :repetition),
      resources
    )
  end

  defp run_requests(host, samples, concurrency, timeout) do
    Task.async_stream(
      samples,
      &run_sample(host, &1, timeout),
      max_concurrency: concurrency,
      ordered: false,
      timeout: timeout + 2_000,
      on_timeout: :kill_task
    )
    |> Enum.map(&normalize_task_result/1)
  end

  defp run_sample(host, sample, timeout) do
    started = monotonic_time()

    case RuntimeHost.analyze(host, sample.text,
           timeout: timeout,
           include_text: false
         ) do
      {:ok, results, service} ->
        %{
          status: :completed,
          sample_id: sample.id,
          latency_ms: elapsed_ms(started),
          service_ms: service.service_ms,
          output: safe_output(results)
        }

      {:error, %{code: :overloaded}} ->
        %{status: :rejected, sample_id: sample.id}

      {:error, %{code: code}} when code in [:request_timeout, :caller_timeout] ->
        %{status: :timed_out, sample_id: sample.id}

      {:error, error} ->
        %{status: :failed, sample_id: sample.id, error: Map.take(error, [:code, :retryable])}
    end
  end

  defp normalize_task_result({:ok, row}), do: row

  defp normalize_task_result({:exit, _reason}),
    do: %{status: :failed, error: %{code: :worker_exit, retryable: true}}

  defp summarize_rows(rows, elapsed_ms, concurrency, repetition, resources) do
    completed = Enum.filter(rows, &(&1.status == :completed))
    latencies = Enum.map(completed, & &1.latency_ms)
    service = Enum.map(completed, & &1.service_ms)

    %{
      repetition: repetition,
      concurrency: concurrency,
      elapsed_ms: elapsed_ms,
      throughput_rps: Statistics.throughput(length(completed), elapsed_ms),
      latency_ms: Statistics.summarize(latencies),
      service_ms: Statistics.summarize(service),
      queue_ms: %{
        status: :unavailable,
        reason: :inline_nx_serving_does_not_expose_queue_time
      },
      completed: length(completed),
      failed: count_status(rows, :failed),
      rejected: count_status(rows, :rejected),
      timed_out: count_status(rows, :timed_out),
      output_fingerprint: output_fingerprint(completed),
      resources: resources
    }
  end

  defp aggregate_repetitions(rows, concurrency) do
    output_fingerprints = MapSet.new(rows, & &1.output_fingerprint)

    %{
      concurrency: concurrency,
      repetition_count: length(rows),
      repetitions: rows,
      throughput_rps: Statistics.summarize(Enum.map(rows, & &1.throughput_rps)),
      completed: sum(rows, :completed),
      failed: sum(rows, :failed),
      rejected: sum(rows, :rejected),
      timed_out: sum(rows, :timed_out),
      stable_output: MapSet.size(output_fingerprints) == 1
    }
    |> Map.put(:latency_ms, aggregate_latency(rows))
  end

  defp aggregate_latency(rows) do
    fields = [:mean, :p50, :p95, :p99, :max]

    Map.new(fields, fn field ->
      values =
        rows
        |> Enum.map(&get_in(&1, [:latency_ms, field]))
        |> Enum.filter(&is_number/1)

      {field, if(values == [], do: nil, else: Enum.sum(values) / length(values))}
    end)
    |> Map.put(:method, :mean_of_repetition_percentiles)
  end

  defp summarize_sustained(
         workers,
         elapsed_ms,
         requested_ms,
         request_count,
         concurrency,
         resources
       ) do
    completed = sum(workers, :completed)

    %{
      requested_duration_ms: requested_ms,
      requested_request_count: request_count,
      elapsed_ms: elapsed_ms,
      stop_reason: if(elapsed_ms >= requested_ms, do: :duration, else: :request_limit),
      concurrency: concurrency,
      worker_count: length(workers),
      completed: completed,
      failed: sum(workers, :failed),
      rejected: sum(workers, :rejected),
      timed_out: sum(workers, :timed_out),
      throughput_rps: Statistics.throughput(completed, elapsed_ms),
      first_half_mean_latency_ms: half_mean(workers, :first),
      second_half_mean_latency_ms: half_mean(workers, :second),
      latency_drift_ratio: half_drift(workers),
      memory_growth_bytes: memory_growth(resources),
      resources: resources
    }
  end

  defp sustained_worker(host, samples, index, context, summary) do
    if monotonic_time() >= context.deadline or not claim_request(context.budget) do
      summary
    else
      sample = elem(samples, rem(index, tuple_size(samples)))
      started = monotonic_time()

      result =
        RuntimeHost.analyze(host, sample.text,
          timeout: context.timeout,
          include_text: false
        )

      latency = elapsed_ms(started)
      half = if monotonic_time() < context.midpoint, do: :first, else: :second

      next_summary =
        summary
        |> count_sustained_result(result)
        |> update_half(half, latency)

      sustained_worker(host, samples, index + context.stride, context, next_summary)
    end
  end

  defp empty_worker_summary do
    %{
      completed: 0,
      failed: 0,
      rejected: 0,
      timed_out: 0,
      first_count: 0,
      first_latency_sum: 0.0,
      second_count: 0,
      second_latency_sum: 0.0
    }
  end

  defp count_sustained_result(summary, {:ok, _results, _service}),
    do: Map.update!(summary, :completed, &(&1 + 1))

  defp count_sustained_result(summary, {:error, %{code: :overloaded}}),
    do: Map.update!(summary, :rejected, &(&1 + 1))

  defp count_sustained_result(summary, {:error, %{code: code}})
       when code in [:request_timeout, :caller_timeout],
       do: Map.update!(summary, :timed_out, &(&1 + 1))

  defp count_sustained_result(summary, _result),
    do: Map.update!(summary, :failed, &(&1 + 1))

  defp update_half(summary, :first, latency) do
    summary
    |> Map.update!(:first_count, &(&1 + 1))
    |> Map.update!(:first_latency_sum, &(&1 + latency))
  end

  defp update_half(summary, :second, latency) do
    summary
    |> Map.update!(:second_count, &(&1 + 1))
    |> Map.update!(:second_latency_sum, &(&1 + latency))
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

  defp output_fingerprint(rows) do
    rows
    |> Enum.sort_by(&to_string(&1.sample_id))
    |> Enum.map(&{&1.sample_id, &1.output})
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp count_status(rows, status), do: Enum.count(rows, &(&1.status == status))

  defp half_mean(workers, half) do
    count = sum(workers, :"#{half}_count")
    latency = sum(workers, :"#{half}_latency_sum")
    if count > 0, do: latency / count
  end

  defp half_drift(workers) do
    case {half_mean(workers, :first), half_mean(workers, :second)} do
      {left, right} when is_number(left) and left > 0 and is_number(right) -> right / left
      _other -> nil
    end
  end

  defp sum(rows, key),
    do: Enum.reduce(rows, 0, fn row, total -> total + Map.fetch!(row, key) end)

  defp request_budget(nil), do: nil

  defp request_budget(limit) when is_integer(limit) and limit > 0 do
    budget = :atomics.new(1, signed: true)
    :atomics.put(budget, 1, limit)
    budget
  end

  defp claim_request(nil), do: true
  defp claim_request(budget), do: :atomics.sub_get(budget, 1, 1) >= 0

  defp memory_growth(resources) do
    first = get_in(resources, [:os_rss, :initial])
    last = get_in(resources, [:os_rss, :steady])

    if is_number(first) and is_number(last), do: last - first
  end

  defp monotonic_time, do: System.monotonic_time()

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end

  defp milliseconds_to_native(milliseconds) do
    milliseconds
    |> Kernel.*(1_000)
    |> round()
    |> System.convert_time_unit(:microsecond, :native)
  end
end
