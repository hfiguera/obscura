defmodule Obscura.Spacy.Serving do
  @moduledoc """
  Experimental, locally prepared macOS/Linux spaCy CPU pool.

  Preparation verifies the pinned model files and starts 1–4 native processes.
  A request reserves a worker before sending text. Saturation returns
  `:spacy_busy` immediately; the pool does not queue input texts. Native crashes,
  malformed responses and timeouts discard that worker before replacement.
  Assets are never downloaded and must remain immutable while the pool is alive.

  `build/1` owns resources on behalf of the calling process (or `:runtime_owner`).
  `start_link/1` can instead be placed directly under a host supervisor. Use
  `stop/1` for explicit release. Status and crash formatting omit request data.
  """
  use GenServer
  alias Obscura.Spacy.Assets

  @max_bytes 1_048_576
  @response_bytes 8_388_608

  def build(opts \\ []) do
    opts = Keyword.put_new(opts, :runtime_owner, self())
    start(:start, opts)
  end

  def start_link(opts), do: start(:start_link, opts)

  def stop(server) do
    GenServer.stop(server, :normal)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, {:normal, _} -> :ok
    # OTP 27 can wrap a concurrent normal owner shutdown in :sys.terminate.
    :exit, {{reason, {:sys, :terminate, _}}, _} when reason in [:normal, :noproc] -> :ok
  end

  def status(server) do
    GenServer.call(server, :status, 5_000)
  catch
    :exit, _ -> %{status: :unavailable, backend: Assets.backend(), python_runtime: false}
  end

  def predict(server, text) when is_binary(text) and byte_size(text) <= @max_bytes do
    if String.valid?(text), do: predict_valid(server, text), else: {:error, :spacy_invalid_input}
  catch
    :exit, _ -> {:error, :spacy_unavailable}
  end

  def predict(_server, _text), do: {:error, :spacy_input_limit}

  defp predict_valid(server, text) do
    with {:ok, lease} <- GenServer.call(server, :reserve, 5_000),
         {:ok, predictions} <- GenServer.call(server, {:predict, lease, text}, :infinity) do
      if Enum.all?(
           predictions,
           &(boundary?(text, &1["byte_start"]) and boundary?(text, &1["byte_end"]))
         ), do: {:ok, predictions}, else: {:error, :spacy_invalid_response}
    end
  end

  defp boundary?(text, offset) when offset == byte_size(text), do: true

  defp boundary?(text, offset) when offset >= 0 and offset < byte_size(text),
    do: Bitwise.band(:binary.at(text, offset), 0xC0) != 0x80

  defp boundary?(_, _), do: false

  defp start(mode, opts) do
    workers = Keyword.get(opts, :workers, 1)
    timeout = Keyword.get(opts, :request_timeout, 30_000)
    owner = Keyword.get(opts, :runtime_owner)

    if workers in 1..4 and is_integer(timeout) and timeout in 1..300_000 and
         (is_nil(owner) or is_pid(owner)) do
      with {:ok, paths} <- Assets.validate(opts) do
        args = %{paths: paths, count: workers, timeout: timeout, owner: owner, starter: self()}
        start_verified(mode, args, opts)
      end
    else
      {:error, Assets.diagnostic(:profile_requirements_unsatisfied, :pool_options)}
    end
  end

  defp start_verified(mode, args, opts) do
    case apply(GenServer, mode, [__MODULE__, args, Keyword.take(opts, [:name])]) do
      {:ok, _} = ok -> ok
      _ -> {:error, Assets.diagnostic(:serving_build_failed, :native_worker)}
    end
  end

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    owner_monitor = if args.owner, do: Process.monitor(args.owner)
    starter_monitor = Process.monitor(args.starter)

    state =
      Map.merge(args, %{
        slots: %{},
        owner_monitor: owner_monitor,
        starter_monitor: starter_monitor,
        restarts: [],
        failures: 0
      })

    case open_slots(state) do
      {:ok, state} ->
        {:ok, state}

      {:error, state} ->
        close_all(state)
        {:stop, :native_startup_failed}
    end
  end

  defp open_slots(state) do
    Enum.reduce_while(1..state.count, {:ok, state}, fn id, {:ok, acc} ->
      case open_worker(acc.paths) do
        {:ok, slot} -> {:cont, {:ok, put_in(acc.slots[id], slot)}}
        {:error, _} -> {:halt, {:error, acc}}
      end
    end)
  end

  defp open_worker(paths) do
    port =
      Port.open({:spawn_executable, Path.expand(paths.native_binary)}, [
        :binary,
        :exit_status,
        {:line, @response_bytes},
        {:args, [Path.expand(paths.model_dir)]},
        {:env,
         [
           {~c"VECLIB_MAXIMUM_THREADS", ~c"1"},
           {~c"OPENBLAS_NUM_THREADS", ~c"1"},
           {~c"OPENBLAS_DEFAULT_NUM_THREADS", ~c"1"},
           {~c"OMP_NUM_THREADS", ~c"1"}
         ]}
      ])

    result =
      receive do
        {^port, {:data, {:eol, line}}} -> Jason.decode(line)
        {^port, _} -> {:error, :native_startup_failed}
        {:EXIT, ^port, _} -> {:error, :native_startup_failed}
      after
        5_000 -> {:error, :native_startup_timeout}
      end

    expected_backend = Assets.native_backend()

    case result do
      {:ok,
       %{
         "ready" => true,
         "protocol_version" => 1,
         "python_runtime" => false,
         "backend" => ^expected_backend,
         "model" => "en_core_web_lg",
         "model_version" => "3.8.0"
       } = ready} ->
        {:ok, %{port: port, busy: nil, peak_rss_bytes: safe_rss(ready["peak_rss_bytes"])}}

      _ ->
        close(port)
        {:error, :native_startup_failed}
    end
  rescue
    _ -> {:error, :native_startup_failed}
  end

  @impl true
  def handle_call(:status, _from, state) do
    busy = Enum.count(state.slots, fn {_, slot} -> slot.busy != nil end)

    {:reply,
     %{
       status: if(map_size(state.slots) == 0, do: :unavailable, else: :ready),
       backend: Assets.backend(),
       python_runtime: false,
       model: :en_core_web_lg_3_8_0,
       workers: map_size(state.slots),
       capacity: state.count,
       busy: busy,
       request_timeout: state.timeout,
       queued_inputs: 0,
       failures: state.failures,
       sum_peak_worker_rss_bytes:
         Enum.reduce(state.slots, 0, fn {_, slot}, sum -> sum + slot.peak_rss_bytes end),
       model_sha256: Map.get(state.paths, :model_sha256, Assets.hashes()["model.json"])
     }, state}
  end

  def handle_call(:reserve, {caller, _}, state) do
    case Enum.find(state.slots, fn {_, slot} -> is_nil(slot.busy) end) do
      nil ->
        {:reply, {:error, :spacy_busy}, state}

      {id, _slot} ->
        lease = make_ref()

        busy = %{
          lease: lease,
          caller: caller,
          monitor: Process.monitor(caller),
          from: nil,
          input_bytes: 0,
          timer: Process.send_after(self(), {:expired, id, lease}, state.timeout)
        }

        {:reply, {:ok, lease}, put_in(state.slots[id].busy, busy)}
    end
  end

  def handle_call({:predict, lease, text}, {caller, _} = from, state) do
    case Enum.find(state.slots, fn {_, slot} ->
           slot.busy && slot.busy.lease == lease && slot.busy.caller == caller &&
             is_nil(slot.busy.from)
         end) do
      nil ->
        {:reply, {:error, :spacy_invalid_lease}, state}

      {id, slot} ->
        state = put_in(state.slots[id].busy.from, from)

        state =
          put_in(
            state.slots[id].busy.input_bytes,
            if(is_binary(text), do: byte_size(text), else: 0)
          )

        if send_request(slot.port, text) do
          {:noreply, state}
        else
          {:noreply, discard(state, id, :spacy_invalid_input)}
        end
    end
  end

  defp send_request(port, text) when is_binary(text) and byte_size(text) <= @max_bytes do
    String.valid?(text) and Port.command(port, [Jason.encode!(%{text: text}), "\n"])
  rescue
    _ -> false
  end

  defp send_request(_, _), do: false

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, state) when is_port(port) do
    case Enum.find(state.slots, fn {_, slot} -> slot.port == port end) do
      {id, %{busy: %{from: from}}} when not is_nil(from) ->
        handle_response(state, id, from, line)

      {id, _} ->
        {:noreply, discard(state, id, :spacy_invalid_response)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({port, _message}, state) when is_port(port), do: lost_port(state, port)
  def handle_info({:EXIT, port, _reason}, state) when is_port(port), do: lost_port(state, port)

  def handle_info({:expired, id, lease}, state) do
    if match?(%{busy: %{lease: ^lease}}, state.slots[id]),
      do: {:noreply, discard(state, id, :spacy_timeout)},
      else: {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    cond do
      monitor == state.owner_monitor ->
        {:stop, :normal, state}

      monitor == state.starter_monitor and reason != :normal ->
        {:stop, :normal, state}

      monitor == state.starter_monitor ->
        {:noreply, state}

      true ->
        handle_caller_down(state, monitor)
    end
  end

  def handle_info({:restart, id}, state) do
    now = System.monotonic_time(:millisecond)
    restarts = Enum.filter(state.restarts, &(now - &1 < 5_000))
    state = %{state | restarts: [now | restarts]}

    if Enum.count_until(restarts, 5) >= 5 do
      {:noreply, state}
    else
      case open_worker(state.paths) do
        {:ok, slot} ->
          {:noreply, put_in(state.slots[id], slot)}

        _ ->
          Process.send_after(self(), {:restart, id}, 100)
          {:noreply, state}
      end
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_caller_down(state, monitor) do
    case Enum.find(state.slots, fn {_, slot} -> slot.busy && slot.busy.monitor == monitor end) do
      {id, %{busy: %{from: nil}}} -> {:noreply, release(state, id)}
      {id, _} -> {:noreply, discard(state, id, :spacy_cancelled)}
      nil -> {:noreply, state}
    end
  end

  defp handle_response(state, id, from, line) do
    case Jason.decode(line) do
      {:ok, %{"error" => _}} ->
        {:noreply, discard(state, id, :spacy_inference_failed)}

      {:ok, %{"predictions" => predictions} = result} when is_list(predictions) ->
        if valid_predictions?(predictions, state.slots[id].busy.input_bytes) do
          state =
            put_in(
              state.slots[id].peak_rss_bytes,
              max(state.slots[id].peak_rss_bytes, safe_rss(result["peak_rss_bytes"]))
            )

          GenServer.reply(from, {:ok, predictions})
          {:noreply, release(state, id)}
        else
          {:noreply, discard(state, id, :spacy_invalid_response)}
        end

      _ ->
        {:noreply, discard(state, id, :spacy_invalid_response)}
    end
  end

  defp safe_rss(value) when is_integer(value) and value > 0, do: value
  defp safe_rss(_), do: 0

  defp valid_predictions?(predictions, bytes) do
    Enum.count_until(predictions, 10_001) <= 10_000 and
      Enum.all?(predictions, fn
        %{"label" => label, "byte_start" => first, "byte_end" => last, "score" => score} ->
          label in ~w(PERSON NORP FAC ORG GPE LOC PRODUCT EVENT WORK_OF_ART LAW LANGUAGE DATE TIME PERCENT MONEY QUANTITY ORDINAL CARDINAL) and
            is_integer(first) and is_integer(last) and first >= 0 and last > first and
            last <= bytes and score == 0.85

        _ ->
          false
      end)
  end

  defp lost_port(state, port) do
    case Enum.find(state.slots, fn {_, slot} -> slot.port == port end) do
      {id, _} -> {:noreply, discard(state, id, :spacy_worker_failed)}
      nil -> {:noreply, state}
    end
  end

  defp release(state, id) do
    if busy = state.slots[id].busy do
      Process.cancel_timer(busy.timer)
      Process.demonitor(busy.monitor, [:flush])
    end

    put_in(state.slots[id].busy, nil)
  end

  defp discard(state, id, reason) do
    slot = state.slots[id]
    if slot.busy && slot.busy.from, do: GenServer.reply(slot.busy.from, {:error, reason})
    close(slot.port)
    state = release(state, id)
    Process.send_after(self(), {:restart, id}, 25)
    %{state | slots: Map.delete(state.slots, id), failures: state.failures + 1}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.slots, fn {_id, slot} ->
      if slot.busy && slot.busy.from,
        do: GenServer.reply(slot.busy.from, {:error, :spacy_unavailable})
    end)

    close_all(state)
  end

  @impl true
  def format_status(status),
    do: Map.merge(status, %{state: :redacted, message: :redacted, reason: :redacted, log: []})

  defp close_all(state), do: Enum.each(state.slots, fn {_, slot} -> close(slot.port) end)
  defp close(port), do: if(Port.info(port), do: Port.close(port))
end
