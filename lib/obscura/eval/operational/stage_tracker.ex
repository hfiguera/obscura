defmodule Obscura.Eval.Operational.StageTracker do
  @moduledoc false

  use Agent

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{events: [], counts: %{}} end, opts)
  end

  @spec observer(pid()) :: (map() -> :ok)
  def observer(pid) do
    fn event ->
      record(pid, event)
      :ok
    end
  end

  @spec record(pid(), map()) :: :ok
  def record(_pid, %{status: :started}), do: :ok

  def record(pid, %{stage: stage} = event) when is_atom(stage) do
    safe_event = Map.take(event, [:stage, :status, :duration_ms, :component])

    Agent.update(pid, fn state ->
      %{
        events: [safe_event | state.events],
        counts: Map.update(state.counts, stage, 1, &(&1 + 1))
      }
    end)
  end

  @spec snapshot(pid()) :: map()
  def snapshot(pid) do
    Agent.get(pid, fn state ->
      %{events: Enum.reverse(state.events), counts: state.counts}
    end)
  end
end
