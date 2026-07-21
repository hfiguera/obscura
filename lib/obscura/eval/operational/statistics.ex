defmodule Obscura.Eval.Operational.Statistics do
  @moduledoc """
  Deterministic operational benchmark statistics.

  Percentiles use the nearest-rank definition. Empty samples are represented
  explicitly instead of producing misleading zero-latency measurements.
  """

  @type summary :: %{
          count: non_neg_integer(),
          mean: float() | nil,
          p50: float() | nil,
          p95: float() | nil,
          p99: float() | nil,
          max: float() | nil
        }

  @spec summarize([number()]) :: summary()
  def summarize([]) do
    %{count: 0, mean: nil, p50: nil, p95: nil, p99: nil, max: nil}
  end

  def summarize(values) when is_list(values) do
    sorted = Enum.sort(values)

    %{
      count: length(sorted),
      mean: Enum.sum(sorted) / length(sorted),
      p50: percentile(sorted, 0.50),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99),
      max: :erlang.float(List.last(sorted))
    }
  end

  @spec percentile([number()], float()) :: float() | nil
  def percentile([], percentile) when percentile >= 0 and percentile <= 1, do: nil

  def percentile(sorted, percentile)
      when is_list(sorted) and percentile >= 0 and percentile <= 1 do
    rank = max(1, ceil(percentile * length(sorted)))
    sorted |> Enum.at(rank - 1) |> :erlang.float()
  end

  @spec throughput(non_neg_integer(), number()) :: float()
  def throughput(_completed, elapsed_ms) when elapsed_ms <= 0, do: 0.0
  def throughput(completed, elapsed_ms), do: completed * 1_000.0 / elapsed_ms
end
