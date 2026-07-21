defmodule Obscura.Eval.Operational.Soak.Analysis do
  @moduledoc """
  Statistical memory-growth analysis for long-duration operational soaks.

  Growth classification is deliberately conservative. A plateau means the
  final-half slope and growth remain inside a metric-relative noise budget; it
  is not a universal proof that a runtime can never leak.
  """

  alias Obscura.Eval.Operational.Common
  alias Obscura.Eval.Operational.Statistics

  @mebibyte 1_048_576
  @default_rolling_samples 60

  @type classification ::
          :stable_plateau | :allocator_caching | :inconclusive | :probable_leak

  @spec analyze([map()], keyword()) :: map()
  def analyze(samples, opts \\ []) when is_list(samples) do
    rolling_samples = Keyword.get(opts, :rolling_samples, @default_rolling_samples)

    metrics =
      %{
        beam_total: metric(samples, [:beam_memory, :total], rolling_samples),
        beam_processes: metric(samples, [:beam_memory, :processes], rolling_samples),
        beam_binary: metric(samples, [:beam_memory, :binary], rolling_samples),
        beam_ets: metric(samples, [:beam_memory, :ets], rolling_samples),
        beam_atom: metric(samples, [:beam_memory, :atom], rolling_samples),
        beam_system: metric(samples, [:beam_memory, :system], rolling_samples),
        os_rss: metric(samples, [:rss_bytes], rolling_samples),
        emily_active: metric(samples, [:gpu_memory, :active], rolling_samples),
        emily_cache: metric(samples, [:gpu_memory, :cache], rolling_samples),
        in_flight: metric(samples, [:host, :in_flight], rolling_samples),
        mailbox_length: metric(samples, [:host, :message_queue_len], rolling_samples)
      }

    %{
      sample_count: length(samples),
      duration_ms: duration(samples),
      rolling_window_samples: rolling_samples,
      metrics: metrics,
      request_correlations: %{
        beam_total: correlation(samples, [:beam_memory, :total]),
        os_rss: correlation(samples, [:rss_bytes]),
        emily_active: correlation(samples, [:gpu_memory, :active]),
        emily_cache: correlation(samples, [:gpu_memory, :cache])
      }
    }
  end

  @spec classify(map(), map()) :: %{classification: classification(), reasons: [atom()]}
  def classify(%{metrics: metrics}, post_soak) do
    rss = metrics.os_rss
    active = metrics.emily_active
    cache = metrics.emily_cache

    cache_release =
      release(post_soak, [:after_gc, :gpu_memory, :cache], [
        :after_cache_clear,
        :gpu_memory,
        :cache
      ])

    rss_release = release(post_soak, [:before_idle, :rss_bytes], [:after_gc, :rss_bytes])
    settled_active = get_in(post_soak, [:after_idle, :gpu_memory, :active])

    cond do
      probable_leak?(rss, active, rss_release, settled_active) ->
        %{classification: :probable_leak, reasons: [:rss_and_live_allocator_continuous_growth]}

      allocator_caching?(active, cache, cache_release, settled_active) ->
        %{classification: :allocator_caching, reasons: [:cache_growth_released_by_cache_clear]}

      plateau?(rss) and
          (plateau?(active) or active.status == :unavailable or
             settled_to_baseline?(active, settled_active)) ->
        %{classification: :stable_plateau, reasons: [:rss_and_live_allocator_plateau]}

      true ->
        %{classification: :inconclusive, reasons: inconclusive_reasons(rss, active, cache)}
    end
  end

  @spec linear_regression([{number(), number()}]) :: map()
  def linear_regression(points) when is_list(points) do
    measured = Enum.filter(points, fn {x, y} -> is_number(x) and is_number(y) end)

    case measured do
      [] ->
        unavailable()

      [_one] ->
        unavailable()

      _ ->
        count = length(measured)
        mean_x = Enum.reduce(measured, 0, fn {x, _y}, sum -> sum + x end) / count
        mean_y = Enum.reduce(measured, 0, fn {_x, y}, sum -> sum + y end) / count

        {numerator, denominator} =
          Enum.reduce(measured, {0.0, 0.0}, fn {x, y}, {num, den} ->
            delta_x = x - mean_x
            {num + delta_x * (y - mean_y), den + delta_x * delta_x}
          end)

        slope = if denominator == 0, do: 0.0, else: numerator / denominator
        intercept = mean_y - slope * mean_x

        %{
          status: :measured,
          slope_bytes_per_ms: slope,
          slope_bytes_per_minute: slope * 60_000,
          intercept_bytes: intercept,
          r_squared: r_squared(measured, mean_y, slope, intercept)
        }
    end
  end

  defp metric(samples, path, rolling_samples) do
    points =
      samples
      |> Enum.map(fn sample -> {sample.elapsed_ms, get_in(sample, path)} end)
      |> Enum.filter(fn {_elapsed, value} -> is_number(value) end)

    case points do
      [] ->
        unavailable()

      _ ->
        values = Enum.map(points, &elem(&1, 1))
        midpoint = max(1, div(length(points), 2))
        {first_half, second_half} = Enum.split(points, midpoint)
        baseline = values |> List.first() |> :erlang.float()
        final = values |> List.last() |> :erlang.float()
        noise_budget = noise_budget(baseline)
        final_regression = linear_regression(second_half)

        %{
          status: :measured,
          baseline: baseline,
          final: final,
          minimum: Enum.min(values),
          maximum: Enum.max(values),
          median: Statistics.percentile(Enum.sort(values), 0.50),
          absolute_growth: final - baseline,
          percentage_growth: percentage_growth(baseline, final),
          first_half_growth: half_growth(first_half),
          second_half_growth: half_growth(second_half),
          full_regression: linear_regression(points),
          final_half_regression: final_regression,
          rolling_median: rolling_summary(values, rolling_samples),
          noise_budget_bytes: noise_budget,
          trend: trend(final_regression, half_growth(second_half), noise_budget)
        }
    end
  end

  defp rolling_summary(values, window_size) do
    medians =
      values
      |> Enum.chunk_every(max(1, window_size), 1, :discard)
      |> Enum.map(fn window -> Statistics.percentile(Enum.sort(window), 0.50) end)

    medians =
      if medians == [], do: [Statistics.percentile(Enum.sort(values), 0.50)], else: medians

    %{
      count: length(medians),
      minimum: Enum.min(medians),
      maximum: Enum.max(medians),
      median: Statistics.percentile(Enum.sort(medians), 0.50)
    }
  end

  defp trend(
         %{status: :measured, slope_bytes_per_minute: slope, r_squared: r_squared},
         growth,
         budget
       ) do
    cond do
      abs(slope) <= budget and abs(growth) <= budget * 2 -> :plateau
      slope > budget and growth > budget * 2 and r_squared >= 0.5 -> :continuous_growth
      slope < -budget and growth < -budget * 2 -> :declining
      true -> :inconclusive
    end
  end

  defp trend(_regression, _growth, _budget), do: :inconclusive

  defp probable_leak?(rss, active, rss_release, settled_active) do
    continuous?(rss) and continuous?(active) and
      not materially_released?(rss_release, rss.absolute_growth) and
      not settled_to_baseline?(active, settled_active)
  end

  defp allocator_caching?(active, cache, cache_release, settled_active) do
    (plateau?(active) or settled_to_baseline?(active, settled_active)) and
      accumulated?(cache) and
      materially_released?(cache_release, cache.absolute_growth)
  end

  defp accumulated?(%{status: :measured} = metric) do
    metric.maximum - metric.baseline > metric.noise_budget_bytes * 2
  end

  defp accumulated?(_metric), do: false

  defp settled_to_baseline?(%{status: :measured} = metric, settled)
       when is_number(settled) do
    settled <= metric.baseline + metric.noise_budget_bytes * 2
  end

  defp settled_to_baseline?(_metric, _settled), do: false

  defp plateau?(%{status: :measured, trend: :plateau}), do: true
  defp plateau?(_metric), do: false

  defp continuous?(%{status: :measured, trend: :continuous_growth}), do: true
  defp continuous?(_metric), do: false

  defp materially_released?(released, growth)
       when is_number(released) and released > 0 and is_number(growth) and growth > 0,
       do: released >= growth * 0.5

  defp materially_released?(_released, _growth), do: false

  defp inconclusive_reasons(rss, active, cache) do
    [
      reason_if(rss.status == :unavailable, :rss_unavailable),
      reason_if(active.status == :unavailable, :emily_active_unavailable),
      reason_if(cache.status == :unavailable, :emily_cache_unavailable),
      reason_if(inconclusive?(rss), :rss_trend_inconclusive),
      reason_if(inconclusive?(active), :live_allocator_trend_inconclusive)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [:classification_requirements_not_met]
      reasons -> reasons
    end
  end

  defp inconclusive?(%{status: :measured, trend: :inconclusive}), do: true
  defp inconclusive?(_metric), do: false
  defp reason_if(true, reason), do: reason
  defp reason_if(false, _reason), do: nil

  defp release(post_soak, before_path, after_path) do
    before = get_in(post_soak, before_path)
    after_value = get_in(post_soak, after_path)
    if is_number(before) and is_number(after_value), do: before - after_value
  end

  defp correlation(samples, memory_path) do
    points =
      samples
      |> Enum.map(fn sample ->
        {get_in(sample, [:host, :completed]), get_in(sample, memory_path)}
      end)
      |> Enum.filter(fn {requests, memory} -> is_number(requests) and is_number(memory) end)

    case points do
      [_first, _second | _rest] ->
        case Common.pearson_coefficient(points) do
          {:ok, coefficient} ->
            %{status: :measured, coefficient: coefficient, sample_count: length(points)}

          {:error, :zero_variance} ->
            %{status: :unavailable, reason: :zero_variance}
        end

      _ ->
        unavailable()
    end
  end

  defp half_growth([]), do: nil
  defp half_growth(points), do: elem(List.last(points), 1) - elem(List.first(points), 1)

  defp percentage_growth(baseline, _final) when baseline == 0, do: nil
  defp percentage_growth(baseline, final), do: (final - baseline) / baseline * 100

  defp noise_budget(baseline), do: max(:erlang.float(@mebibyte), abs(baseline) * 0.001)

  defp duration([]), do: 0.0
  defp duration(samples), do: List.last(samples).elapsed_ms - List.first(samples).elapsed_ms

  defp r_squared(points, mean_y, slope, intercept) do
    residual =
      Enum.reduce(points, 0.0, fn {x, y}, sum ->
        predicted = intercept + slope * x
        sum + :math.pow(y - predicted, 2)
      end)

    total = Enum.reduce(points, 0.0, fn {_x, y}, sum -> sum + :math.pow(y - mean_y, 2) end)
    if total == 0, do: 1.0, else: max(0.0, 1.0 - residual / total)
  end

  defp unavailable, do: %{status: :unavailable, reason: :insufficient_measurements}
end
