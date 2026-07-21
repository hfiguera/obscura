defmodule Obscura.Eval.Operational.Soak.AnalysisTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Soak.Analysis

  test "calculates full and final-half growth evidence for a plateau" do
    samples = samples(fn index -> 100_000_000 + rem(index, 4) * 100_000 end)
    analysis = Analysis.analyze(samples, rolling_samples: 5)
    rss = analysis.metrics.os_rss

    assert rss.status == :measured
    assert rss.full_regression.status == :measured
    assert rss.final_half_regression.status == :measured
    assert rss.rolling_median.count > 0
    assert rss.trend == :plateau
    assert analysis.request_correlations.os_rss.status == :measured

    classification =
      Analysis.classify(analysis, post_soak(100_000_000, 100_000_000, nil, nil))

    assert classification.classification == :stable_plateau
  end

  test "classifies released cache growth separately from live allocations" do
    samples =
      Enum.map(0..119, fn index ->
        sample(index,
          rss: 200_000_000 + rem(index, 3) * 100_000,
          active: 50_000_000 + rem(index, 2) * 50_000,
          cache: 10_000_000 + index * 2_000_000
        )
      end)

    analysis = Analysis.analyze(samples, rolling_samples: 10)

    post =
      post_soak(200_000_000, 199_000_000, 248_000_000, 8_000_000,
        active_before: 50_000_000,
        active_after: 50_000_000
      )

    assert %{classification: :allocator_caching} = Analysis.classify(analysis, post)
  end

  test "marks unreleased live allocator and RSS growth as a probable leak" do
    samples =
      Enum.map(0..119, fn index ->
        sample(index,
          rss: 100_000_000 + index * 3_000_000,
          active: 50_000_000 + index * 2_000_000,
          cache: 10_000_000
        )
      end)

    analysis = Analysis.analyze(samples, rolling_samples: 10)

    post =
      post_soak(457_000_000, 450_000_000, 10_000_000, 9_000_000,
        active_before: 288_000_000,
        active_after: 285_000_000
      )

    assert %{classification: :probable_leak} = Analysis.classify(analysis, post)
  end

  test "classifies released cache when noisy live allocations settle to baseline" do
    samples =
      Enum.map(0..119, fn index ->
        active = if index > 0 and rem(index, 5) == 0, do: 90_000_000, else: 50_000_000
        cache = if index < 30, do: 10_000_000 + index * 5_000_000, else: 160_000_000

        sample(index,
          rss: 200_000_000 + rem(index, 3) * 100_000,
          active: active,
          cache: cache
        )
      end)

    analysis = Analysis.analyze(samples, rolling_samples: 10)

    post =
      post_soak(200_000_000, 199_000_000, 160_000_000, 0,
        active_before: 45_000_000,
        active_after: 45_000_000
      )

    assert %{classification: :allocator_caching} = Analysis.classify(analysis, post)
  end

  test "classifies an RSS plateau when noisy live allocations settle to baseline" do
    samples =
      Enum.map(0..119, fn index ->
        active = if index > 0 and rem(index, 5) == 0, do: 90_000_000, else: 50_000_000

        sample(index,
          rss: 200_000_000 + rem(index, 3) * 100_000,
          active: active,
          cache: 10_000_000
        )
      end)

    analysis = Analysis.analyze(samples, rolling_samples: 10)

    post =
      post_soak(200_000_000, 199_000_000, 10_000_000, 0,
        active_before: 50_000_000,
        active_after: 50_000_000
      )

    assert %{classification: :stable_plateau} = Analysis.classify(analysis, post)
  end

  test "keeps malformed or incomplete measurements unavailable" do
    analysis = Analysis.analyze([%{elapsed_ms: 0}, %{elapsed_ms: 1_000}])

    assert analysis.metrics.os_rss.status == :unavailable
    assert analysis.metrics.emily_active.status == :unavailable
    assert %{classification: :inconclusive} = Analysis.classify(analysis, %{})
  end

  test "linear regression reports a byte-per-minute slope and fit" do
    regression = Analysis.linear_regression([{0, 10}, {1_000, 20}, {2_000, 30}])

    assert regression.status == :measured
    assert_in_delta regression.slope_bytes_per_ms, 0.01, 0.000_001
    assert_in_delta regression.slope_bytes_per_minute, 600.0, 0.001
    assert_in_delta regression.r_squared, 1.0, 0.000_001
  end

  defp samples(value_fun) do
    Enum.map(0..119, fn index ->
      value = value_fun.(index)
      sample(index, rss: value, active: value, cache: 0)
    end)
  end

  defp sample(index, opts) do
    value = Keyword.fetch!(opts, :rss)

    %{
      elapsed_ms: index * 1_000,
      rss_bytes: value,
      beam_memory: %{
        total: value,
        processes: div(value, 2),
        binary: 1_000,
        ets: 2_000,
        atom: 3_000,
        system: div(value, 2)
      },
      gpu_memory: %{
        active: Keyword.fetch!(opts, :active),
        cache: Keyword.fetch!(opts, :cache),
        peak: Keyword.fetch!(opts, :active)
      },
      host: %{completed: index * 10, in_flight: rem(index, 2), message_queue_len: 0}
    }
  end

  defp post_soak(rss_before, rss_after, cache_before, cache_after, opts \\ []) do
    active_before = Keyword.get(opts, :active_before, rss_before)
    active_after = Keyword.get(opts, :active_after, rss_after)

    %{
      before_idle: %{rss_bytes: rss_before},
      after_idle: %{gpu_memory: %{active: active_before}},
      after_gc: %{rss_bytes: rss_after, gpu_memory: %{active: active_after, cache: cache_before}},
      after_cache_clear: %{gpu_memory: %{cache: cache_after}}
    }
  end
end
