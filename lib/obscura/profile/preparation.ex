defmodule Obscura.Profile.Preparation do
  @moduledoc false

  alias Obscura.Diagnostic
  alias Obscura.Profile
  alias Obscura.Profile.Cache
  alias Obscura.Profile.Runtime
  alias Obscura.Telemetry

  @default_timeout :timer.minutes(30)
  @default_inactivity_timeout :timer.minutes(5)
  @default_progress_interval 250

  @type progress_event :: map()

  @spec prepare(Profile.name() | String.t(), keyword()) ::
          {:ok, Runtime.t()} | {:error, Diagnostic.t()}
  def prepare(profile, opts) when is_list(opts) do
    with {:ok, descriptor} <- Profile.fetch(profile),
         {:ok, config} <- validate_options(descriptor, opts) do
      run_controlled(descriptor, opts, config)
    end
  end

  defp validate_options(descriptor, opts) do
    config = %{
      profile: descriptor.name,
      models: descriptor.default_models,
      model_count: length(descriptor.default_models),
      allow_download: Keyword.get(opts, :allow_download, false),
      offline: Keyword.get(opts, :offline, false),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      inactivity_timeout: Keyword.get(opts, :inactivity_timeout, @default_inactivity_timeout),
      progress_interval: Keyword.get(opts, :progress_interval, @default_progress_interval),
      progress: Keyword.get(opts, :progress),
      stage_observer: Keyword.get(opts, :stage_observer),
      telemetry: Keyword.get(opts, :telemetry, true),
      backend: safe_backend(opts)
    }

    with :ok <- boolean_option(:allow_download, config.allow_download),
         :ok <- boolean_option(:offline, config.offline),
         :ok <- timeout_option(:timeout, config.timeout),
         :ok <- timeout_option(:inactivity_timeout, config.inactivity_timeout),
         :ok <- positive_integer_option(:progress_interval, config.progress_interval),
         :ok <- callback_option(:progress, config.progress),
         :ok <- callback_option(:stage_observer, config.stage_observer) do
      {:ok, Map.put(config, :effective_offline, config.offline or not config.allow_download)}
    else
      {:error, reason} ->
        {:error,
         Diagnostic.new(:profile_requirements_unsatisfied,
           profile: descriptor.name,
           component: :profile_preparation,
           cause: reason,
           metadata: %{option_validation: :failed}
         )}
    end
  end

  defp run_controlled(descriptor, opts, config) do
    started = monotonic_ms()
    reference = make_ref()
    caller = self()

    emit(config, event(:preparation_started, descriptor, started, config, %{}))

    worker_opts =
      opts
      |> Keyword.put(:offline, config.effective_offline)
      |> Keyword.put(:stage_observer, fn stage_event ->
        send(caller, {reference, :stage, stage_event})
      end)

    {worker, monitor} =
      spawn_monitor(fn ->
        result = locked_prepare(descriptor, worker_opts, config, caller, reference)
        send(caller, {reference, :result, result})
      end)

    initial_snapshot = cache_snapshot(descriptor, worker_opts)

    state = %{
      descriptor: descriptor,
      opts: worker_opts,
      config: config,
      reference: reference,
      worker: worker,
      monitor: monitor,
      started: started,
      last_activity: started,
      snapshot: initial_snapshot,
      initial_bytes: initial_snapshot.bytes,
      current_stage: :preparation,
      current_model: nil,
      current_model_index: nil,
      download_started: false
    }

    await_result(state)
  end

  defp locked_prepare(descriptor, opts, config, caller, reference) do
    relay(caller, reference, %{stage: :preparation_lock, status: :started})

    result =
      :global.trans({{__MODULE__, descriptor.name}, self()}, fn ->
        relay(caller, reference, %{stage: :preparation_lock, status: :ok, duration_ms: 0.0})
        prepare_under_lock(descriptor, opts, config, caller, reference)
      end)

    case result do
      {:aborted, reason} ->
        {:error,
         Diagnostic.new(:profile_requirements_unsatisfied,
           profile: descriptor.name,
           component: :profile_preparation,
           cause: {:lock_aborted, reason}
         )}

      other ->
        other
    end
  catch
    :exit, reason ->
      {:error,
       Diagnostic.new(:model_download_interrupted,
         profile: descriptor.name,
         component: :profile_preparation,
         cause: {:lock_exit, reason}
       )}
  end

  defp prepare_under_lock(descriptor, opts, config, caller, reference) do
    relay(caller, reference, %{stage: :cache_check, status: :started})

    with :ok <- Profile.validate_dependencies(descriptor, opts),
         {:ok, snapshot} <- Cache.inspect(descriptor, opts),
         :ok <- relay_cache_result(caller, reference, snapshot),
         {:ok, snapshot} <-
           recover_partial(snapshot, descriptor, opts, config, caller, reference),
         :ok <- authorize_assets(snapshot, descriptor, config),
         result <- Runtime.build(descriptor.name, opts),
         result <- normalize_runtime_result(result, snapshot, descriptor, config) do
      mark_successful_cache(result, descriptor, opts, caller, reference)
    else
      {:error, %Diagnostic{} = diagnostic} ->
        {:error, diagnostic}

      {:error, {:cache_failure, _reason} = reason} ->
        {:error, cache_diagnostic(descriptor, reason)}

      {:error, reason} ->
        {:error,
         Diagnostic.normalize(reason,
           profile: descriptor.name,
           component: :profile_preparation
         )}
    end
  end

  defp relay_cache_result(caller, reference, snapshot) do
    relay(caller, reference, %{
      stage: :cache_check,
      status: :ok,
      duration_ms: 0.0,
      cache_status: snapshot.status,
      cache_directory_source: snapshot.directory_source
    })

    :ok
  end

  defp recover_partial(
         %{status: :partial} = snapshot,
         descriptor,
         opts,
         config,
         caller,
         reference
       ) do
    if config.allow_download and not config.offline do
      with {:ok, _count} <- Cache.quarantine_incomplete(snapshot),
           {:ok, recovered_snapshot} <- Cache.inspect(descriptor, opts) do
        relay(caller, reference, %{
          stage: :cache_recovery,
          status: :ok,
          duration_ms: 0.0,
          cache_status: recovered_snapshot.status,
          cache_bytes: recovered_snapshot.bytes
        })

        {:ok, recovered_snapshot}
      end
    else
      {:error,
       Diagnostic.new(:model_asset_incomplete,
         profile: descriptor.name,
         component: :profile_preparation,
         asset: :model_cache,
         metadata: %{cache_status: :partial}
       )}
    end
  end

  defp recover_partial(snapshot, _descriptor, _opts, _config, _caller, _reference),
    do: {:ok, snapshot}

  defp authorize_assets(_snapshot, %Profile{name: name}, _config)
       when name not in [:balanced, :accurate],
       do: :ok

  defp authorize_assets(%{status: status}, descriptor, config)
       when status in [:missing, :partial] do
    cond do
      config.offline ->
        {:error,
         Diagnostic.new(:missing_model_asset,
           profile: descriptor.name,
           component: :profile_preparation,
           asset: :model_cache,
           metadata: %{offline: true, cache_status: status}
         )}

      not config.allow_download ->
        {:error,
         Diagnostic.new(:model_download_not_allowed,
           profile: descriptor.name,
           component: :profile_preparation,
           asset: :model_cache,
           metadata: %{cache_status: status}
         )}

      true ->
        :ok
    end
  end

  defp authorize_assets(_snapshot, _descriptor, _config), do: :ok

  defp normalize_runtime_result(
         {:error, %Diagnostic{code: code}},
         %{status: :present},
         descriptor,
         %{effective_offline: true}
       )
       when code in [:model_load_failed, :tokenizer_load_failed] do
    asset = if code == :tokenizer_load_failed, do: :tokenizer_cache, else: :model_cache

    {:error,
     Diagnostic.new(:model_asset_incomplete,
       profile: descriptor.name,
       component: :profile_preparation,
       asset: asset,
       metadata: %{cache_status: :present, offline: true}
     )}
  end

  defp normalize_runtime_result(result, _snapshot, _descriptor, _config), do: result

  defp mark_successful_cache({:ok, _runtime} = result, descriptor, opts, caller, reference) do
    snapshot = cache_snapshot(descriptor, opts)

    relay(caller, reference, %{
      stage: :asset_validation,
      status: :ok,
      duration_ms: 0.0,
      cache_status: if(snapshot.status == :not_applicable, do: :not_applicable, else: :complete)
    })

    result
  end

  defp mark_successful_cache(result, _descriptor, _opts, _caller, _reference), do: result

  defp await_result(state) do
    case timeout_reason(state) do
      nil -> receive_result(state)
      reason -> terminate_worker(state, reason)
    end
  end

  defp receive_result(state) do
    receive do
      {reference, :stage, stage_event} when reference == state.reference ->
        state = handle_stage_event(state, stage_event)
        await_result(%{state | last_activity: monotonic_ms()})

      {reference, :result, result} when reference == state.reference ->
        Process.demonitor(state.monitor, [:flush])
        finish(state, result)

      {:DOWN, monitor, :process, _pid, reason} when monitor == state.monitor ->
        diagnostic =
          Diagnostic.new(:model_download_interrupted,
            profile: state.descriptor.name,
            component: :profile_preparation,
            cause: {:worker_exit, reason},
            metadata: %{stage: state.current_stage}
          )

        quarantine_after_failure(state)
        finish(state, {:error, diagnostic})
    after
      state.config.progress_interval ->
        state |> sample_cache_progress() |> await_result()
    end
  end

  defp handle_stage_event(state, stage_event) do
    state = maybe_reset_cache_progress(state, stage_event)
    state = maybe_finish_download(state, stage_event)
    progress_event = stage_progress_event(state, stage_event)
    emit(state.config, progress_event)
    invoke_callback(state.config.stage_observer, stage_event)

    if stage_event.status == :started do
      %{
        state
        | current_stage: stage_event.stage,
          current_model: Map.get(stage_event, :model),
          current_model_index: Map.get(stage_event, :model_index)
      }
    else
      state
    end
  end

  defp maybe_reset_cache_progress(state, %{
         stage: :cache_recovery,
         status: :ok,
         cache_bytes: cache_bytes
       }) do
    %{state | initial_bytes: cache_bytes, snapshot: %{state.snapshot | bytes: cache_bytes}}
  end

  defp maybe_reset_cache_progress(state, _stage_event), do: state

  defp sample_cache_progress(state) do
    snapshot = cache_snapshot(state.descriptor, state.opts)

    cond do
      snapshot.bytes < state.snapshot.bytes ->
        %{state | snapshot: snapshot, initial_bytes: snapshot.bytes}

      snapshot.bytes > state.snapshot.bytes ->
        state = maybe_start_download(state)
        received = max(snapshot.bytes - state.initial_bytes, 0)

        emit(
          state.config,
          event(:stage_progress, state.descriptor, state.started, state.config, %{
            stage: :download,
            model: state.current_model,
            model_index: state.current_model_index,
            bytes_received: received,
            total_bytes: nil,
            percent: nil,
            cache_status: snapshot.status
          })
        )

        %{state | snapshot: snapshot, last_activity: monotonic_ms()}

      true ->
        %{state | snapshot: snapshot}
    end
  end

  defp maybe_start_download(%{download_started: true} = state), do: state

  defp maybe_start_download(state) do
    emit(
      state.config,
      event(:stage_started, state.descriptor, state.started, state.config, %{
        stage: :download,
        model: state.current_model,
        model_index: state.current_model_index,
        cache_status: :populating
      })
    )

    %{state | download_started: true}
  end

  defp maybe_finish_download(%{download_started: true} = state, %{
         stage: :model_load,
         status: status
       })
       when status in [:ok, :error] do
    emit(
      state.config,
      event(
        if(status == :ok, do: :stage_completed, else: :stage_failed),
        state.descriptor,
        state.started,
        state.config,
        %{
          stage: :download,
          model: state.current_model,
          model_index: state.current_model_index,
          bytes_received: max(state.snapshot.bytes - state.initial_bytes, 0),
          total_bytes: nil,
          percent: nil
        }
      )
    )

    %{state | download_started: false, initial_bytes: state.snapshot.bytes}
  end

  defp maybe_finish_download(state, _event), do: state

  defp stage_progress_event(state, stage_event) do
    type =
      case stage_event.status do
        :started -> :stage_started
        :ok -> :stage_completed
        :error -> :stage_failed
      end

    attrs =
      stage_event
      |> Map.take([
        :stage,
        :status,
        :duration_ms,
        :component,
        :model,
        :model_index,
        :model_count,
        :cache_status,
        :cache_directory_source
      ])

    event(type, state.descriptor, state.started, state.config, attrs)
  end

  defp finish(state, {:ok, _runtime} = result) do
    emit(
      state.config,
      event(:preparation_completed, state.descriptor, state.started, state.config, %{
        status: :ok,
        cache_status: :complete
      })
    )

    result
  end

  defp finish(state, {:error, %Diagnostic{} = diagnostic} = result) do
    emit(
      state.config,
      event(:preparation_completed, state.descriptor, state.started, state.config, %{
        status: :error,
        diagnostic_code: diagnostic.code
      })
    )

    result
  end

  defp terminate_worker(state, reason) do
    Process.exit(state.worker, :kill)

    receive do
      {:DOWN, monitor, :process, _pid, _reason} when monitor == state.monitor -> :ok
    after
      1_000 -> :ok
    end

    flush_reference_messages(state.reference)
    quarantine_after_failure(state)

    code =
      case reason do
        :overall_timeout -> :preparation_timeout
        :inactivity_timeout -> :preparation_inactivity_timeout
      end

    diagnostic =
      Diagnostic.new(code,
        profile: state.descriptor.name,
        component: :profile_preparation,
        metadata: %{stage: state.current_stage}
      )

    finish(state, {:error, diagnostic})
  end

  defp quarantine_after_failure(state) do
    with {:ok, snapshot} <- Cache.inspect(state.descriptor, state.opts),
         {:ok, _count} <- Cache.quarantine_incomplete(snapshot) do
      :ok
    else
      _error -> :ok
    end
  end

  defp timeout_reason(state) do
    now = monotonic_ms()

    cond do
      expired?(state.started, state.config.timeout, now) -> :overall_timeout
      expired?(state.last_activity, state.config.inactivity_timeout, now) -> :inactivity_timeout
      true -> nil
    end
  end

  defp expired?(_started, :infinity, _now), do: false
  defp expired?(started, timeout, now), do: now - started >= timeout

  defp cache_snapshot(descriptor, opts) do
    case Cache.inspect(descriptor, opts) do
      {:ok, snapshot} ->
        snapshot

      {:error, _reason} ->
        {directory, source} = Cache.effective_directory(opts)

        %{
          status: :missing,
          bytes: 0,
          repositories: [],
          directory: directory,
          directory_source: source
        }
    end
  end

  defp relay(caller, reference, stage_event) do
    send(caller, {reference, :stage, stage_event})
    :ok
  end

  defp flush_reference_messages(reference) do
    receive do
      {^reference, _kind, _value} -> flush_reference_messages(reference)
    after
      0 -> :ok
    end
  end

  defp event(type, descriptor, started, config, attrs) do
    %{
      event: type,
      profile: descriptor.name,
      model_count: config.model_count,
      elapsed_ms: monotonic_ms() - started,
      backend: config.backend
    }
    |> Map.merge(attrs)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp emit(config, progress_event) do
    invoke_callback(config.progress, progress_event)

    if config.telemetry do
      measurements =
        progress_event
        |> Map.take([:elapsed_ms, :duration_ms, :bytes_received, :total_bytes, :percent])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      metadata =
        progress_event
        |> Map.drop([:elapsed_ms, :duration_ms, :bytes_received, :total_bytes, :percent])
        |> sanitize_telemetry_metadata()

      Telemetry.execute(
        true,
        [:obscura, :profile, :preparation, progress_event.event],
        measurements,
        metadata
      )
    end

    :ok
  rescue
    _error -> :ok
  end

  @doc false
  @spec invoke_callback((term() -> term()) | nil, term()) :: :ok
  def invoke_callback(callback, value) when is_function(callback, 1) do
    callback.(value)
    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  def invoke_callback(_callback, _value), do: :ok

  defp sanitize_telemetry_metadata(metadata) do
    case Map.pop(metadata, :model) do
      {nil, metadata} -> metadata
      {model, metadata} -> Map.put(metadata, :model_alias, model)
    end
  end

  defp cache_diagnostic(descriptor, reason) do
    Diagnostic.new(:model_cache_failure,
      profile: descriptor.name,
      component: :profile_preparation,
      asset: :model_cache,
      cause: reason
    )
  end

  defp boolean_option(_key, value) when is_boolean(value), do: :ok
  defp boolean_option(key, value), do: {:error, {:invalid_option, key, value}}

  defp timeout_option(_key, :infinity), do: :ok
  defp timeout_option(_key, value) when is_integer(value) and value > 0, do: :ok
  defp timeout_option(key, value), do: {:error, {:invalid_option, key, value}}

  defp positive_integer_option(_key, value) when is_integer(value) and value > 0, do: :ok
  defp positive_integer_option(key, value), do: {:error, {:invalid_option, key, value}}

  defp callback_option(_key, nil), do: :ok
  defp callback_option(_key, value) when is_function(value, 1), do: :ok
  defp callback_option(key, value), do: {:error, {:invalid_option, key, value}}

  defp safe_backend(opts) do
    value =
      Keyword.get(opts, :real_model_backend) ||
        Keyword.get(opts, :backend) ||
        System.get_env("OBSCURA_REAL_MODEL_BACKEND")

    case value do
      backend when backend in [:binary, :default, :emily, :exla, :none, :ortex_cpu] -> backend
      "binary" -> :binary
      "emily" -> :emily
      "exla" -> :exla
      _other -> :default
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
