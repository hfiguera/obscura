defmodule Obscura.Eval.Operational.Soak.Histogram do
  @moduledoc false

  defstruct count: 0, total_us: 0, max_us: 0, buckets: %{}

  @type t :: %__MODULE__{
          count: non_neg_integer(),
          total_us: non_neg_integer(),
          max_us: non_neg_integer(),
          buckets: %{non_neg_integer() => pos_integer()}
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add(t(), number()) :: t()
  def add(%__MODULE__{} = histogram, latency_ms)
      when is_number(latency_ms) and latency_ms >= 0 do
    latency_us = round(latency_ms * 1_000)
    bucket = bucket_upper_bound(latency_us)

    %{
      histogram
      | count: histogram.count + 1,
        total_us: histogram.total_us + latency_us,
        max_us: max(histogram.max_us, latency_us),
        buckets: Map.update(histogram.buckets, bucket, 1, &(&1 + 1))
    }
  end

  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = left, %__MODULE__{} = right) do
    %__MODULE__{
      count: left.count + right.count,
      total_us: left.total_us + right.total_us,
      max_us: max(left.max_us, right.max_us),
      buckets:
        Map.merge(left.buckets, right.buckets, fn _bucket, left_count, right_count ->
          left_count + right_count
        end)
    }
  end

  @spec summarize(t()) :: map()
  def summarize(%__MODULE__{count: 0}) do
    %{count: 0, mean: nil, p50: nil, p95: nil, p99: nil, max: nil}
  end

  def summarize(%__MODULE__{} = histogram) do
    %{
      count: histogram.count,
      mean: histogram.total_us / histogram.count / 1_000,
      p50: percentile(histogram, 0.50),
      p95: percentile(histogram, 0.95),
      p99: percentile(histogram, 0.99),
      max: histogram.max_us / 1_000
    }
  end

  defp percentile(histogram, percentile) do
    rank = max(1, ceil(histogram.count * percentile))

    histogram.buckets
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while(0, fn {upper_bound, count}, seen ->
      next = seen + count
      if next >= rank, do: {:halt, upper_bound / 1_000}, else: {:cont, next}
    end)
  end

  defp bucket_upper_bound(microseconds) when microseconds <= 1_000,
    do: ceil_bucket(microseconds, 10)

  defp bucket_upper_bound(microseconds) when microseconds <= 10_000,
    do: ceil_bucket(microseconds, 50)

  defp bucket_upper_bound(microseconds) when microseconds <= 100_000,
    do: ceil_bucket(microseconds, 500)

  defp bucket_upper_bound(microseconds) when microseconds <= 1_000_000,
    do: ceil_bucket(microseconds, 5_000)

  defp bucket_upper_bound(microseconds), do: ceil_bucket(microseconds, 50_000)

  defp ceil_bucket(0, _resolution), do: 0
  defp ceil_bucket(value, resolution), do: div(value + resolution - 1, resolution) * resolution
end
