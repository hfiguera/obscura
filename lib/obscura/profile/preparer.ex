defmodule Obscura.Profile.Preparer do
  @moduledoc """
  Supervised asynchronous preparation and ownership of a reusable profile runtime.

  Add the preparer to an application supervision tree, then query `status/1`
  or call `await/2` before accepting work which requires the model-backed
  profile. The process prepares exactly once and retains the runtime for reuse.
  `status/1` exposes the latest report-safe preparation event while large model
  assets download or load. Download authorization and offline behavior come
  from the `:prepare_options` passed to `start_link/1`.
  """

  use GenServer

  alias Obscura.Diagnostic
  alias Obscura.Profile
  alias Obscura.Profile.Preparation
  alias Obscura.Profile.Runtime

  @type status :: :preparing | :ready | :failed
  @type server :: GenServer.server()

  @doc "Starts a supervised profile preparer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Returns readiness and the latest safe progress event."
  @spec status(server()) :: map()
  def status(server), do: GenServer.call(server, :status)

  @doc "Returns the reusable runtime when preparation is complete."
  @spec runtime(server()) :: {:ok, Runtime.t()} | {:error, :not_ready | Diagnostic.t()}
  def runtime(server), do: GenServer.call(server, :runtime)

  @doc "Waits for preparation and returns the reusable runtime or diagnostic."
  @spec await(server(), timeout()) :: {:ok, Runtime.t()} | {:error, Diagnostic.t()}
  def await(server, timeout \\ 30_000) do
    GenServer.call(server, :await, timeout)
  catch
    :exit, {:timeout, _call} ->
      {:error,
       Diagnostic.new(:preparation_timeout,
         component: :profile_preparer,
         metadata: %{await_timeout: true}
       )}
  end

  @doc "Subscribes the caller to progress and completion messages."
  @spec subscribe(server()) :: :ok
  def subscribe(server), do: GenServer.call(server, {:subscribe, self()})

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, Keyword.get(opts, :name, __MODULE__)),
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  @impl true
  def init(opts) do
    profile = Keyword.fetch!(opts, :profile)
    prepare_opts = Keyword.get(opts, :prepare_options, [])
    callback = Keyword.get(prepare_opts, :progress)

    state = %{
      profile: profile,
      prepare_opts: prepare_opts,
      callback: callback,
      status: :preparing,
      runtime: nil,
      diagnostic: nil,
      progress: nil,
      subscribers: MapSet.new(),
      waiters: [],
      worker: nil,
      monitor: nil
    }

    {:ok, state, {:continue, :prepare}}
  end

  @impl true
  def handle_continue(:prepare, state) do
    owner = self()

    opts =
      Keyword.put(state.prepare_opts, :progress, fn event ->
        send(owner, {:preparation_progress, event})
      end)

    {worker, monitor} =
      spawn_monitor(fn ->
        result = Profile.prepare(state.profile, opts)
        send(owner, {:preparation_result, result})
      end)

    {:noreply, %{state | worker: worker, monitor: monitor}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = %{
      status: state.status,
      profile: state.profile,
      progress: state.progress,
      diagnostic: diagnostic_map(state.diagnostic)
    }

    {:reply, reply, state}
  end

  def handle_call(:runtime, _from, %{status: :ready, runtime: runtime} = state) do
    {:reply, {:ok, runtime}, state}
  end

  def handle_call(:runtime, _from, %{status: :failed, diagnostic: diagnostic} = state) do
    {:reply, {:error, diagnostic}, state}
  end

  def handle_call(:runtime, _from, state), do: {:reply, {:error, :not_ready}, state}

  def handle_call(:await, _from, %{status: :ready, runtime: runtime} = state) do
    {:reply, {:ok, runtime}, state}
  end

  def handle_call(:await, _from, %{status: :failed, diagnostic: diagnostic} = state) do
    {:reply, {:error, diagnostic}, state}
  end

  def handle_call(:await, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call({:subscribe, pid}, _from, state) when is_pid(pid) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_info({:preparation_progress, event}, state) do
    Preparation.invoke_callback(state.callback, event)
    notify(state.subscribers, {:obscura_profile_preparation, self(), event})
    {:noreply, %{state | progress: event}}
  end

  def handle_info({:preparation_result, {:ok, runtime} = result}, state) do
    Process.demonitor(state.monitor, [:flush])
    reply_waiters(state.waiters, result)
    notify(state.subscribers, {:obscura_profile_ready, self()})
    {:noreply, %{state | status: :ready, runtime: runtime, waiters: []}}
  end

  def handle_info({:preparation_result, {:error, %Diagnostic{} = diagnostic} = result}, state) do
    Process.demonitor(state.monitor, [:flush])
    reply_waiters(state.waiters, result)
    notify(state.subscribers, {:obscura_profile_failed, self(), Diagnostic.to_map(diagnostic)})
    {:noreply, %{state | status: :failed, diagnostic: diagnostic, waiters: []}}
  end

  def handle_info({:DOWN, monitor, :process, _pid, :normal}, %{monitor: monitor} = state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, %{monitor: monitor} = state) do
    diagnostic =
      Diagnostic.new(:model_download_interrupted,
        profile: safe_profile(state.profile),
        component: :profile_preparer,
        cause: {:worker_exit, reason}
      )

    result = {:error, diagnostic}
    reply_waiters(state.waiters, result)
    notify(state.subscribers, {:obscura_profile_failed, self(), Diagnostic.to_map(diagnostic)})
    {:noreply, %{state | status: :failed, diagnostic: diagnostic, waiters: []}}
  end

  def handle_info({:DOWN, _monitor, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  defp reply_waiters(waiters, result), do: Enum.each(waiters, &GenServer.reply(&1, result))

  defp notify(subscribers, message), do: Enum.each(subscribers, &send(&1, message))

  defp diagnostic_map(%Diagnostic{} = diagnostic), do: Diagnostic.to_map(diagnostic)
  defp diagnostic_map(nil), do: nil

  defp safe_profile(profile) when is_atom(profile), do: profile
  defp safe_profile(_profile), do: nil
end
