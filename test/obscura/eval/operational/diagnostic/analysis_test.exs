defmodule Obscura.Eval.Operational.Diagnostic.AnalysisTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Diagnostic.Analysis

  test "correlates stage, input, and resource degradation by minute" do
    analysis = Analysis.analyze(load())

    assert analysis.window_count == 3
    assert analysis.first_middle_last.first.throughput_rps == 4.0
    assert analysis.first_middle_last.last.throughput_rps == 2.0
    assert analysis.correlations.stages.model_serving.status == :measured
    assert analysis.correlations.stages.model_serving.coefficient < -0.9
    assert analysis.correlations.input.input_bytes.status == :measured
    assert analysis.earliest_degrading_stage.status == :observed
    assert analysis.earliest_degrading_stage.stage == :model_serving
    assert Enum.find(analysis.hypotheses, &(&1.hypothesis == :model_serving)).status == :supported
  end

  test "excludes an incomplete trailing window from trend analysis" do
    load =
      update_in(load().windows, fn windows ->
        windows ++
          [
            %{
              List.last(windows)
              | index: 3,
                start_ms: 180_000,
                measured_ms: 50,
                completed: 1,
                throughput_rps: 20.0
            }
          ]
      end)

    analysis = Analysis.analyze(load)

    assert analysis.window_count == 3
    assert analysis.first_middle_last.last.index == 2
  end

  defp load do
    windows =
      Enum.map(0..2, fn index ->
        model = 10.0 + index * 10

        %{
          index: index,
          start_ms: index * 60_000,
          measured_ms: 60_000,
          completed: 240 - index * 60,
          throughput_rps: 4.0 - index,
          latency_ms: summary(20.0 + index * 10),
          diagnostics: %{
            status: :measured,
            stages: %{
              queue_admission: summary(1.0),
              service_total: summary(model + 5),
              model_serving: summary(model)
            },
            input: %{
              input_bytes: summary(100.0 + index * 5),
              token_count: summary(20.0 + index)
            },
            unavailable_stages: %{}
          }
        }
      end)

    %{
      windows: windows,
      window_duration_ms: 60_000,
      diagnostics: %{
        status: :measured,
        stages: %{
          service_total: summary(25.0),
          model_serving: summary(20.0)
        },
        unavailable_stages: %{}
      },
      resource_series:
        Enum.flat_map(0..2, fn index ->
          [
            resource(index * 60_000, index * 100),
            resource(index * 60_000 + 59_000, index * 100 + 50)
          ]
        end)
    }
  end

  defp summary(mean) do
    %{count: 10, mean: mean, p50: mean, p95: mean, p99: mean, max: mean}
  end

  defp resource(elapsed_ms, counter) do
    %{
      elapsed_ms: elapsed_ms,
      scheduler_utilization: 0.5,
      run_queue: 1,
      rss_bytes: 100_000_000,
      gpu_memory: %{active: 10, cache: 20},
      host: %{in_flight: 4, message_queue_len: 0},
      system: %{
        process_cpu_percent: 50.0,
        beam_runtime: %{
          process_count: 100,
          reductions: counter,
          garbage_collections: counter,
          garbage_reclaimed_words: counter
        }
      }
    }
  end
end
