defmodule Obscura.Eval.Operational.RuntimeHost do
  @moduledoc """
  Bounded, supervised request gateway used by operational benchmarks.

  The prepared runtime is passed as immutable child state. Restarting this
  gateway therefore exercises request-process recovery without reconstructing
  model resources.
  """

  use GenServer

  alias Obscura.Internal.StageDiagnostics

  @default_timeout 120_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  @spec analyze(pid(), String.t(), keyword()) ::
          {:ok, term(), map()} | {:error, map()}
  def analyze(pid, text, opts \\ []) when is_binary(text) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    enqueued_at = System.monotonic_time()
    GenServer.call(pid, {:analyze, text, opts, timeout, enqueued_at}, timeout + 1_000)
  catch
    :exit, {:timeout, _call} ->
      {:error, safe_error(:caller_timeout, true)}

    :exit, _reason ->
      {:error, safe_error(:serving_unavailable, true)}
  end

  @spec stats(pid()) :: map()
  def stats(pid), do: GenServer.call(pid, :stats)

  @spec reset_diagnostic_shapes(pid()) :: :ok
  def reset_diagnostic_shapes(pid), do: GenServer.call(pid, :reset_diagnostic_shapes)

  @impl true
  def init(opts) do
    {:ok,
     %{
       runtime: Keyword.fetch!(opts, :runtime),
       analyzer: Keyword.get(opts, :analyzer, &Obscura.analyze/2),
       max_in_flight: Keyword.get(opts, :max_in_flight, 16),
       diagnostics: Keyword.get(opts, :diagnostics, false),
       diagnostic_shapes: MapSet.new(),
       in_flight: %{},
       completed: 0,
       rejected: 0,
       timed_out: 0,
       failed: 0
     }}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats =
      state
      |> Map.take([:completed, :rejected, :timed_out, :failed, :max_in_flight])
      |> Map.put(:in_flight, map_size(state.in_flight))

    {:reply, stats, state}
  end

  def handle_call(:reset_diagnostic_shapes, _from, state) do
    {:reply, :ok, %{state | diagnostic_shapes: MapSet.new()}}
  end

  def handle_call({:analyze, _text, _opts, _timeout, _enqueued_at}, _from, state)
      when map_size(state.in_flight) >= state.max_in_flight do
    {:reply, {:error, safe_error(:overloaded, true)}, %{state | rejected: state.rejected + 1}}
  end

  def handle_call({:analyze, text, opts, timeout, enqueued_at}, from, state) do
    runtime = state.runtime
    analyzer = state.analyzer
    started = System.monotonic_time()
    queue_ms = elapsed_ms(enqueued_at)
    owner = self()
    request_ref = make_ref()
    diagnostics? = state.diagnostics

    {:ok, task_pid} =
      Task.start(fn ->
        {result, diagnostics} =
          StageDiagnostics.capture(diagnostics?, fn ->
            StageDiagnostics.metadata(:input_bytes, byte_size(text))
            analyzer.(text, Keyword.put(opts, :profile, runtime))
          end)

        send(owner, {request_ref, result, diagnostics})
      end)

    monitor_ref = Process.monitor(task_pid)
    timer = Process.send_after(self(), {:request_timeout, request_ref}, timeout)

    request = %{
      task_pid: task_pid,
      monitor_ref: monitor_ref,
      from: from,
      timer: timer,
      started: started,
      queue_ms: queue_ms
    }

    {:noreply, put_in(state.in_flight[request_ref], request)}
  end

  @impl true
  def handle_info({ref, result, diagnostics}, state) when is_reference(ref) do
    case Map.pop(state.in_flight, ref) do
      {nil, _in_flight} ->
        {:noreply, state}

      {request, in_flight} ->
        Process.cancel_timer(request.timer)
        Process.demonitor(request.monitor_ref, [:flush])
        service_ms = elapsed_ms(request.started)

        {reply, state} =
          case result do
            {:ok, value} ->
              {shape, state} = annotate_shape(diagnostics, state)

              service = %{
                service_ms: service_ms,
                queue_ms: request.queue_ms,
                diagnostics: diagnostics,
                model_shape: shape
              }

              {{:ok, value, service}, %{state | completed: state.completed + 1}}

            {:error, reason} ->
              error = safe_error(error_code(reason), false)
              {{:error, error}, %{state | failed: state.failed + 1}}

            _other ->
              {{:error, safe_error(:invalid_analyzer_response, false)},
               %{state | failed: state.failed + 1}}
          end

        GenServer.reply(request.from, reply)
        {:noreply, %{state | in_flight: in_flight}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case find_by_monitor(state.in_flight, ref) do
      nil ->
        {:noreply, state}

      {request_ref, request} ->
        Process.cancel_timer(request.timer)
        GenServer.reply(request.from, {:error, safe_error(:serving_crash, true)})

        {:noreply,
         %{
           state
           | in_flight: Map.delete(state.in_flight, request_ref),
             failed: state.failed + 1
         }}
    end
  end

  def handle_info({:request_timeout, ref}, state) do
    case Map.pop(state.in_flight, ref) do
      {nil, _in_flight} ->
        {:noreply, state}

      {request, in_flight} ->
        Process.exit(request.task_pid, :kill)
        GenServer.reply(request.from, {:error, safe_error(:request_timeout, true)})
        {:noreply, %{state | in_flight: in_flight, timed_out: state.timed_out + 1}}
    end
  end

  defp error_code(%{code: code}) when is_atom(code), do: code
  defp error_code({code, _detail}) when is_atom(code), do: code
  defp error_code(code) when is_atom(code), do: code
  defp error_code(_reason), do: :analysis_failed

  defp safe_error(code, retryable) do
    %{code: code, component: :operational_runtime, retryable: retryable}
  end

  defp annotate_shape(%{status: :measured, metadata: metadata} = diagnostics, state) do
    sequence_length = Map.get(metadata, :model_sequence_length)
    window_count = Map.get(metadata, :window_count)

    if is_number(sequence_length) and is_number(window_count) do
      key = {sequence_length, window_count}
      first_seen? = not MapSet.member?(state.diagnostic_shapes, key)

      shapes =
        if MapSet.size(state.diagnostic_shapes) < 256,
          do: MapSet.put(state.diagnostic_shapes, key),
          else: state.diagnostic_shapes

      shape = %{
        sequence_length: sequence_length,
        window_count: window_count,
        model_ms: get_in(diagnostics, [:stages, :model_serving, :total_ms]),
        first_seen: first_seen?,
        tracked_shape_count: MapSet.size(shapes),
        tracking_overflow: MapSet.size(state.diagnostic_shapes) >= 256 and first_seen?
      }

      {shape, %{state | diagnostic_shapes: shapes}}
    else
      {%{status: :unavailable, reason: :model_shape_unavailable}, state}
    end
  end

  defp annotate_shape(_diagnostics, state),
    do: {%{status: :disabled}, state}

  defp find_by_monitor(in_flight, monitor_ref) do
    Enum.find(in_flight, fn {_request_ref, request} ->
      request.monitor_ref == monitor_ref
    end)
  end

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
