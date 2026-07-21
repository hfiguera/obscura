defmodule Obscura.Internal.StageDiagnostics do
  @moduledoc false

  @process_key {__MODULE__, :state}
  @allowed_metadata ~w(
    input_bytes
    token_count
    window_count
    model_sequence_length
    model_packed_tokens
    model_padding_tokens
    model_padding_ratio
    result_count
  )a

  @type snapshot :: %{
          status: :measured | :disabled,
          stages: %{optional(atom()) => map()},
          metadata: %{optional(atom()) => number()},
          unavailable: %{optional(atom()) => atom()}
        }

  @spec capture(boolean(), (-> term())) :: {term(), snapshot()}
  def capture(false, fun) when is_function(fun, 0), do: {fun.(), disabled()}

  def capture(true, fun) when is_function(fun, 0) do
    previous = Process.get(@process_key)
    Process.put(@process_key, empty())

    try do
      result = fun.()
      {result, snapshot()}
    after
      restore(previous)
    end
  end

  @spec measure(atom(), (-> result)) :: result when result: term()
  def measure(stage, fun) when is_atom(stage) and is_function(fun, 0) do
    if enabled?() do
      started = System.monotonic_time()

      try do
        fun.()
      after
        record(stage, elapsed_ms(started))
      end
    else
      fun.()
    end
  end

  @spec record(atom(), number()) :: :ok
  def record(stage, duration_ms)
      when is_atom(stage) and is_number(duration_ms) and duration_ms >= 0 do
    update(fn state ->
      event = Map.get(state.stages, stage, %{count: 0, total_ms: 0.0, max_ms: 0.0})

      next = %{
        count: event.count + 1,
        total_ms: event.total_ms + duration_ms,
        max_ms: max(event.max_ms, duration_ms)
      }

      %{state | stages: Map.put(state.stages, stage, next)}
    end)
  end

  @spec metadata(atom(), number()) :: :ok
  def metadata(key, value) when key in @allowed_metadata and is_number(value) and value >= 0 do
    update(fn state -> %{state | metadata: Map.put(state.metadata, key, value)} end)
  end

  @spec unavailable(atom(), atom()) :: :ok
  def unavailable(stage, reason) when is_atom(stage) and is_atom(reason) do
    update(fn state ->
      %{state | unavailable: Map.put_new(state.unavailable, stage, reason)}
    end)
  end

  @spec enabled?() :: boolean()
  def enabled?, do: is_map(Process.get(@process_key))

  defp snapshot do
    case Process.get(@process_key) do
      state when is_map(state) -> Map.put(state, :status, :measured)
      _other -> disabled()
    end
  end

  defp empty, do: %{stages: %{}, metadata: %{}, unavailable: %{}}
  defp disabled, do: %{status: :disabled, stages: %{}, metadata: %{}, unavailable: %{}}

  defp update(fun) do
    case Process.get(@process_key) do
      state when is_map(state) ->
        Process.put(@process_key, fun.(state))
        :ok

      _other ->
        :ok
    end
  end

  defp restore(nil), do: Process.delete(@process_key)
  defp restore(previous), do: Process.put(@process_key, previous)

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
