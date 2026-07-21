defmodule Obscura.Serving.StageTiming do
  @moduledoc false

  @spec measure(atom(), atom(), (map() -> term()) | nil, (-> term())) :: term()
  def measure(component, stage, observer, fun) do
    started = System.monotonic_time()
    notify(observer, component, stage, :started, started)

    try do
      result = fun.()
      notify(observer, component, stage, status(result), started)
      result
    rescue
      error ->
        notify(observer, component, stage, :error, started)
        reraise error, __STACKTRACE__
    end
  end

  defp notify(observer, component, stage, status, started) when is_function(observer, 1) do
    observer.(%{
      component: component,
      stage: stage,
      status: status,
      duration_ms: elapsed_ms(started)
    })
  rescue
    _error -> :ok
  end

  defp notify(_observer, _component, _stage, _status, _started), do: :ok

  defp status({:ok, _value}), do: :ok
  defp status(:ok), do: :ok
  defp status(_result), do: :error

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
