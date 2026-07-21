defmodule Obscura.Eval.PrivacyFilter.BackendLatencyComparison do
  alias Obscura.PrivacyFilter.Serving

  @out_json "eval/reports/privacy_filter_backend_latency_comparison.json"
  @out_md "eval/reports/privacy_filter_backend_latency_comparison.md"
  @default_text "Ada Lovelace can be reached at ada@example.com or 415-555-0199."

  def run do
    checkpoint = checkpoint!()
    text = System.get_env("OBSCURA_PRIVACY_FILTER_LATENCY_TEXT", @default_text)
    iterations = iterations()
    warmup_iterations = warmup_iterations()

    report =
      %{
        "run_id" => "privacy_filter_backend_latency_comparison",
        "checkpoint" => checkpoint,
        "text" => text,
        "iterations" => iterations,
        "warmup_iterations" => warmup_iterations,
        "backends" =>
          for backend <- [:exla, :emily], into: %{} do
            {Atom.to_string(backend),
             run_backend(backend, checkpoint, text, warmup_iterations, iterations)}
          end
      }
      |> put_comparison()

    File.mkdir_p!(Path.dirname(@out_json))
    File.write!(@out_json, Jason.encode!(report, pretty: true) <> "\n")
    File.write!(@out_md, render_markdown(report))
    IO.puts(@out_json)
    IO.puts(@out_md)
  end

  defp checkpoint! do
    case System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT") do
      nil ->
        raise "Set OBSCURA_PRIVACY_FILTER_CHECKPOINT to compare privacy-filter backend latency"

      "" ->
        raise "Set OBSCURA_PRIVACY_FILTER_CHECKPOINT to compare privacy-filter backend latency"

      checkpoint ->
        checkpoint
    end
  end

  defp iterations do
    "OBSCURA_PRIVACY_FILTER_LATENCY_ITERATIONS"
    |> System.get_env("3")
    |> String.to_integer()
    |> max(1)
  end

  defp warmup_iterations do
    "OBSCURA_PRIVACY_FILTER_LATENCY_WARMUP_ITERATIONS"
    |> System.get_env("1")
    |> String.to_integer()
    |> max(0)
  end

  defp run_backend(backend, checkpoint, text, warmup_iterations, iterations) do
    start = System.monotonic_time()

    try do
      with {:ok, serving} <- build_serving(backend, checkpoint),
           {:ok, _warmup_runs} <- run_iterations(serving, text, warmup_iterations),
           {:ok, runs} <- run_iterations(serving, text, iterations) do
        %{
          "status" => "completed",
          "backend_metadata" => stringify(serving.backend_metadata),
          "build_ms" => elapsed_ms(start),
          "latency" => latency_summary(Enum.map(runs, & &1.timings.total_ms)),
          "stage_latency" => stage_latency_summary(runs),
          "outputs" => hd(runs).outputs
        }
      else
        {:error, reason} ->
          %{
            "status" => "failed",
            "backend" => Atom.to_string(backend),
            "reason" => inspect(reason),
            "first_failing_stage" => failure_stage(reason),
            "build_ms" => elapsed_ms(start)
          }
      end
    rescue
      error ->
        %{
          "status" => "failed",
          "backend" => Atom.to_string(backend),
          "reason" => Exception.format(:error, error, __STACKTRACE__),
          "first_failing_stage" => :exception |> Atom.to_string(),
          "build_ms" => elapsed_ms(start)
        }
    end
  end

  defp build_serving(backend, checkpoint) do
    Serving.build(
      checkpoint: checkpoint,
      backend: backend,
      n_ctx: 128,
      decoder: :viterbi,
      trim_span_whitespace: true,
      discard_overlapping_spans: true,
      emily_fallback: :raise
    )
  end

  defp run_iterations(_serving, _text, 0), do: {:ok, []}

  defp run_iterations(serving, text, iterations) do
    1..iterations
    |> Enum.reduce_while({:ok, []}, fn _index, {:ok, acc} ->
      case Serving.run_with_timings(serving, text) do
        {:ok, results, timings} ->
          {:cont, {:ok, [%{outputs: normalized_outputs(results), timings: timings} | acc]}}

        {:error, reason, timings} ->
          {:halt, {:error, {reason, timings}}}
      end
    end)
    |> case do
      {:ok, runs} -> {:ok, Enum.reverse(runs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalized_outputs(results) do
    Enum.map(results, fn result ->
      %{
        "entity" => Atom.to_string(result.entity),
        "start" => result.start,
        "end" => result.end,
        "text" => result.text,
        "score" => result.score
      }
    end)
  end

  defp latency_summary(values) do
    sorted = Enum.sort(values)

    %{
      "mean_ms" => mean(values),
      "p50_ms" => percentile(sorted, 0.50),
      "p95_ms" => percentile(sorted, 0.95),
      "max_ms" => Enum.max(values)
    }
  end

  defp stage_latency_summary(runs) do
    [:tokenization_ms, :model_ms, :decode_ms, :total_ms]
    |> Map.new(fn key ->
      values = Enum.map(runs, &Map.fetch!(&1.timings, key))
      {Atom.to_string(key), latency_summary(values)}
    end)
  end

  defp put_comparison(report) do
    exla = report["backends"]["exla"]
    emily = report["backends"]["emily"]

    comparison =
      if exla["status"] == "completed" and emily["status"] == "completed" do
        exla_latency = exla["latency"]
        emily_latency = emily["latency"]

        %{
          "status" => "completed",
          "outputs_identical" => exla["outputs"] == emily["outputs"],
          "mean_latency_delta_ms" => emily_latency["mean_ms"] - exla_latency["mean_ms"],
          "p95_latency_delta_ms" => emily_latency["p95_ms"] - exla_latency["p95_ms"],
          "max_latency_delta_ms" => emily_latency["max_ms"] - exla_latency["max_ms"],
          "emily_faster_mean" => emily_latency["mean_ms"] < exla_latency["mean_ms"],
          "emily_faster_p95" => emily_latency["p95_ms"] < exla_latency["p95_ms"]
        }
      else
        %{
          "status" => "incomplete",
          "reason" => "both EXLA and Emily must complete to compare latency"
        }
      end

    Map.put(report, "comparison", comparison)
  end

  defp failure_stage({{:privacy_filter_model_forward_failed, _error, message}, _timings}),
    do: "model_forward: #{message}"

  defp failure_stage({:missing_optional_dependency, dep}),
    do: "missing_optional_dependency: #{dep}"

  defp failure_stage({reason, _timings}), do: failure_stage(reason)

  defp failure_stage({:backend_configuration_failed, backend, reason}),
    do: "#{backend}: #{inspect(reason)}"

  defp failure_stage(reason), do: inspect(reason)

  defp percentile(sorted, fraction) do
    index =
      sorted
      |> length()
      |> Kernel.*(fraction)
      |> Float.ceil()
      |> trunc()
      |> Kernel.-(1)
      |> max(0)

    Enum.at(sorted, index)
  end

  defp mean(values), do: Enum.sum(values) / length(values)

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end

  defp stringify(value) when is_map(value),
    do: Map.new(value, fn {key, child} -> {to_string(key), stringify(child)} end)

  defp stringify(value) when is_boolean(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value

  defp render_markdown(report) do
    backend_rows =
      report["backends"]
      |> Enum.map(fn {backend, result} ->
        latency = result["latency"] || %{}

        "| #{backend} | #{result["status"]} | #{fmt(latency["mean_ms"])} | #{fmt(latency["p95_ms"])} | #{fmt(latency["max_ms"])} | #{result["first_failing_stage"] || ""} |"
      end)
      |> Enum.join("\n")

    comparison = report["comparison"]

    """
    # Privacy-Filter Backend Latency Comparison

    - Run ID: #{report["run_id"]}
    - Checkpoint: #{report["checkpoint"]}
    - Warmup iterations: #{report["warmup_iterations"]}
    - Iterations: #{report["iterations"]}
    - Comparison status: #{comparison["status"]}
    - Outputs identical: #{comparison["outputs_identical"]}
    - Emily mean latency delta ms: #{fmt(comparison["mean_latency_delta_ms"])}
    - Emily p95 latency delta ms: #{fmt(comparison["p95_latency_delta_ms"])}
    - Emily max latency delta ms: #{fmt(comparison["max_latency_delta_ms"])}

    | Backend | Status | Mean ms | P95 ms | Max ms | First failing stage |
    | --- | --- | ---: | ---: | ---: | --- |
    #{backend_rows}
    """
  end

  defp fmt(nil), do: ""
  defp fmt(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 4)
  defp fmt(value), do: to_string(value)
end

Obscura.Eval.PrivacyFilter.BackendLatencyComparison.run()
