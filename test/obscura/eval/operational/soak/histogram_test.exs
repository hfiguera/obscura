defmodule Obscura.Eval.Operational.Soak.HistogramTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Obscura.Eval.Operational.Soak.Histogram

  test "summarizes and merges bounded latency histograms" do
    left = Enum.reduce([1.0, 2.0, 3.0], Histogram.new(), &Histogram.add(&2, &1))
    right = Enum.reduce([4.0, 5.0], Histogram.new(), &Histogram.add(&2, &1))
    summary = left |> Histogram.merge(right) |> Histogram.summarize()

    assert summary.count == 5
    assert_in_delta summary.mean, 3.0, 0.001
    assert summary.p50 >= 3.0
    assert summary.p95 >= 5.0
    assert summary.p99 >= 5.0
    assert summary.max == 5.0
  end

  property "histogram percentiles remain ordered for arbitrary nonnegative latencies" do
    check all(values <- list_of(float(min: 0.0, max: 60_000.0), min_length: 1, max_length: 200)) do
      summary =
        Enum.reduce(values, Histogram.new(), &Histogram.add(&2, &1)) |> Histogram.summarize()

      assert summary.p50 <= summary.p95
      assert summary.p95 <= summary.p99
      assert summary.p99 <= summary.max + 50.0
    end
  end
end
