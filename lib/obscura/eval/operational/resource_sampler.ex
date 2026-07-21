defmodule Obscura.Eval.Operational.ResourceSampler do
  @moduledoc """
  Periodically samples report-safe BEAM, OS, scheduler, and Emily allocator data.

  OS RSS is sampled from the current BEAM process with `ps`. GPU allocator
  values are reported only when Emily exposes them directly.
  """

  use GenServer

  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Eval.Operational.SystemProbe

  @default_interval 50

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec snapshot(pid()) :: map()
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  @spec series(pid()) :: [map()]
  def series(pid), do: GenServer.call(pid, :series)

  @spec capture(keyword()) :: map()
  def capture(opts \\ []) do
    host = Keyword.get(opts, :host)
    environmental? = Keyword.get(opts, :environmental, false)

    %{
      beam_memory: :erlang.memory() |> Map.new(),
      rss_bytes: rss_bytes(),
      run_queue: :erlang.statistics(:run_queue),
      scheduler_utilization: scheduler_utilization(),
      gpu_memory: emily_memory(Keyword.get(opts, :gpu, false)),
      host: host_snapshot(host),
      system: if(environmental?, do: SystemProbe.capture(), else: nil)
    }
  end

  @impl true
  def init(opts) do
    :erlang.system_flag(:scheduler_wall_time, true)

    state = %{
      interval: Keyword.get(opts, :interval, @default_interval),
      gpu: Keyword.get(opts, :gpu, false),
      host: Keyword.get(opts, :host),
      detailed: Keyword.get(opts, :detailed, false),
      environmental: Keyword.get(opts, :environmental, false),
      started: System.monotonic_time(),
      samples: [],
      scheduler_previous: scheduler_totals()
    }

    maybe_reset_emily_peak(state.gpu)
    send(self(), :sample)
    {:ok, state}
  end

  @impl true
  def handle_info(:sample, state) do
    Process.send_after(self(), :sample, state.interval)
    {sample, scheduler_previous} = sample(state)

    {:noreply,
     %{state | samples: [sample | state.samples], scheduler_previous: scheduler_previous}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    samples = Enum.reverse(state.samples)
    {:reply, summarize(samples, state.gpu), state}
  end

  def handle_call(:series, _from, state) do
    {:reply, Enum.reverse(state.samples), state}
  end

  defp sample(state) do
    captured =
      capture(
        gpu: state.gpu,
        host: state.host,
        environmental: state.environmental
      )

    scheduler_current = scheduler_totals()
    scheduler_utilization = scheduler_delta(state.scheduler_previous, scheduler_current)

    base = %{
      elapsed_ms: elapsed_ms(state.started),
      beam_memory_bytes: get_in(captured, [:beam_memory, :total]),
      rss_bytes: captured.rss_bytes,
      run_queue: captured.run_queue,
      scheduler_utilization: scheduler_utilization || captured.scheduler_utilization,
      gpu_memory: captured.gpu_memory
    }

    sample =
      if state.detailed do
        Map.merge(base, Map.take(captured, [:beam_memory, :host, :system]))
      else
        base
      end

    {sample, scheduler_current}
  end

  defp summarize([], gpu?) do
    %{
      sample_count: 0,
      beam: unavailable(),
      os_rss: unavailable(),
      scheduler: unavailable(),
      gpu: gpu_summary([], gpu?)
    }
  end

  defp summarize(samples, gpu?) do
    %{
      sample_count: length(samples),
      beam: numeric_summary(samples, :beam_memory_bytes),
      os_rss: numeric_summary(samples, :rss_bytes),
      scheduler: %{
        run_queue: numeric_summary(samples, :run_queue),
        utilization: numeric_summary(samples, :scheduler_utilization)
      },
      gpu: gpu_summary(samples, gpu?)
    }
  end

  defp numeric_summary(samples, key) do
    values = samples |> Enum.map(&Map.get(&1, key)) |> Enum.filter(&is_number/1)

    case values do
      [] ->
        unavailable()

      _ ->
        %{
          status: :measured,
          initial: List.first(values),
          steady: List.last(values),
          peak: Enum.max(values)
        }
    end
  end

  defp gpu_summary(_samples, false),
    do: %{status: :unavailable, reason: :non_emily_backend}

  defp gpu_summary(samples, true) do
    measured =
      samples
      |> Enum.map(& &1.gpu_memory)
      |> Enum.filter(&is_map/1)

    case measured do
      [] ->
        %{status: :unavailable, reason: :emily_memory_api_unavailable}

      rows ->
        %{
          status: :measured,
          source: :emily_memory,
          active_bytes: numeric_summary(rows, :active),
          peak_bytes: rows |> Enum.map(& &1.peak) |> Enum.max(),
          cache_bytes: numeric_summary(rows, :cache)
        }
    end
  end

  defp unavailable, do: %{status: :unavailable, reason: :no_samples}

  defp rss_bytes do
    case System.cmd("ps", ["-o", "rss=", "-p", System.pid()], stderr_to_stdout: true) do
      {output, 0} ->
        case Integer.parse(String.trim(output)) do
          {kilobytes, ""} -> kilobytes * 1_024
          _other -> nil
        end

      _other ->
        nil
    end
  rescue
    _error -> nil
  end

  defp scheduler_utilization do
    case scheduler_totals() do
      {_active, 0} -> nil
      {active, total} -> active / total
      nil -> nil
    end
  rescue
    _error -> nil
  end

  defp scheduler_totals do
    case :erlang.statistics(:scheduler_wall_time) do
      rows when is_list(rows) ->
        Enum.reduce(rows, {0, 0}, fn {_id, active, total}, {active_sum, total_sum} ->
          {active_sum + active, total_sum + total}
        end)

      _other ->
        nil
    end
  rescue
    _error -> nil
  end

  defp scheduler_delta({previous_active, previous_total}, {active, total}) do
    active_delta = active - previous_active
    total_delta = total - previous_total
    if total_delta > 0, do: active_delta / total_delta
  end

  defp scheduler_delta(_previous, _current), do: nil

  defp emily_memory(true) do
    module = Module.concat([Emily, Memory])

    if Code.ensure_loaded?(module) and function_exported?(module, :stats, 0),
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      do: apply(module, :stats, []),
      else: nil
  rescue
    _error -> nil
  end

  defp emily_memory(false), do: nil

  defp maybe_reset_emily_peak(true) do
    module = Module.concat([Emily, Memory])

    if Code.ensure_loaded?(module) and function_exported?(module, :reset_peak, 0),
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      do: apply(module, :reset_peak, [])
  rescue
    _error -> :ok
  end

  defp maybe_reset_emily_peak(false), do: :ok

  defp host_snapshot(nil), do: nil

  defp host_snapshot(host) when is_pid(host) do
    stats = RuntimeHost.stats(host)

    message_queue_len =
      case Process.info(host, :message_queue_len) do
        {:message_queue_len, length} -> length
        _other -> nil
      end

    Map.put(stats, :message_queue_len, message_queue_len)
  catch
    :exit, _reason -> nil
  end

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
