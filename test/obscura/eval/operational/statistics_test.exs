defmodule Obscura.Eval.Operational.StatisticsTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Statistics

  test "uses nearest-rank percentiles including p99" do
    values = Enum.to_list(1..100)
    summary = Statistics.summarize(values)

    assert summary.p50 == 50.0
    assert summary.p95 == 95.0
    assert summary.p99 == 99.0
    assert summary.max == 100.0
    assert summary.mean == 50.5
  end

  test "keeps empty measurements explicit" do
    assert Statistics.summarize([]) == %{
             count: 0,
             mean: nil,
             p50: nil,
             p95: nil,
             p99: nil,
             max: nil
           }

    assert Statistics.throughput(10, 0) == 0.0
    assert_in_delta Statistics.throughput(10, 250), 40.0, 0.001
  end
end
