Code.require_file("native.exs", __DIR__)

defmodule Obscura.Eval.GLiNER.NativeSpikeRunner do
  @moduledoc false

  alias Obscura.Eval.GLiNER.NativeSpikes

  @default_oracle_dir ".cache/gliner-native-spikes"
  @default_json "eval/reports/gliner-native-gpu-spikes.json"
  @iterations 30
  @tolerance 5.0e-5

  def run do
    oracle_dir = System.get_env("OBSCURA_GLINER_NATIVE_SPIKE_DIR", @default_oracle_dir)
    json_path = System.get_env("OBSCURA_GLINER_NATIVE_SPIKE_REPORT", @default_json)
    markdown_path = Path.rootname(json_path) <> ".md"
    configure_emily!()

    tensors = NativeSpikes.load!(oracle_dir)
    head_input = transfer(NativeSpikes.head_inputs(tensors))
    head_params = transfer(NativeSpikes.head_params(tensors))
    block_input = transfer(NativeSpikes.block_inputs(tensors))
    block_params = transfer(NativeSpikes.block_params(tensors))

    head =
      execute(
        "bilstm_span_head",
        &NativeSpikes.head/2,
        head_input,
        head_params,
        NativeSpikes.head_expected(tensors),
        NativeSpikes.head_names()
      )

    block =
      execute(
        "mdeberta_encoder_block_0",
        &NativeSpikes.block/2,
        block_input,
        block_params,
        NativeSpikes.block_expected(tensors),
        NativeSpikes.block_names()
      )

    manifest = oracle_dir |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

    report = %{
      "schema_version" => 1,
      "status" => "passed",
      "scope" => "two feasibility spikes only; not a complete GLiNER adapter",
      "generated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "oracle" => oracle_summary(manifest),
      "execution" => %{
        "backend" => "Emily.Backend",
        "compiler" => "Emily.Compiler",
        "device" => "gpu",
        "backend_fallback" => "raise",
        "compiler_fallback" => "raise",
        "native" => true,
        "fuse" => false,
        "warm_iterations" => @iterations,
        "tolerance_max_abs" => @tolerance
      },
      "spikes" => [head, block],
      "decision" => decision()
    }

    File.mkdir_p!(Path.dirname(json_path))
    File.write!(json_path, Jason.encode!(report, pretty: true) <> "\n")
    File.write!(markdown_path, markdown(report))
    IO.puts(json_path)
    IO.puts(markdown_path)
  end

  defp configure_emily! do
    unless Code.ensure_loaded?(Emily.Backend) and Code.ensure_loaded?(Emily.Compiler) do
      raise "Emily is unavailable; run with OBSCURA_REAL_MODEL_BACKEND=emily"
    end

    Application.put_env(:emily, :fallback, :raise)
    Application.put_env(:emily, :native_fallback, :raise)
    {:ok, _applications} = Application.ensure_all_started(:emily)
  end

  defp oracle_summary(manifest) do
    oracle = manifest["oracle"]

    %{
      "model" => manifest["model"],
      "input" => manifest["input"],
      "environment" => manifest["environment"],
      "file" => oracle["file"],
      "sha256" => oracle["sha256"],
      "bytes" => oracle["bytes"],
      "tensor_count" => map_size(oracle["tensors"])
    }
  end

  defp execute(name, function, input, params, expected, names) do
    compiled =
      Nx.Defn.jit(function,
        compiler: Emily.Compiler,
        device: :gpu,
        native: true,
        native_fallback: :raise,
        fuse: false
      )

    {compile_us, first} =
      :timer.tc(fn ->
        result = compiled.(input, params)
        synchronize(result)
        result
      end)

    assert_emily_backend!(first)
    comparisons = NativeSpikes.compare(first, expected, names)
    assert_parity!(name, comparisons)

    durations =
      for _iteration <- 1..@iterations do
        {microseconds, _result} =
          :timer.tc(fn ->
            result = compiled.(input, params)
            synchronize(result)
            result
          end)

        microseconds / 1_000
      end

    %{
      "name" => name,
      "status" => "passed",
      "compile_and_first_run_ms" => compile_us / 1_000,
      "warm_latency_ms" => latency(durations),
      "parity" => stringify_comparisons(comparisons)
    }
  end

  defp transfer(container) do
    Nx.backend_transfer(container, {Emily.Backend, device: :gpu})
  end

  defp synchronize(result) do
    result
    |> Tuple.to_list()
    |> List.last()
    |> Nx.to_binary()

    :ok
  end

  defp assert_emily_backend!(result) do
    backend = result |> elem(0) |> Map.fetch!(:data) |> Map.fetch!(:__struct__)

    unless backend == Emily.Backend do
      raise "expected Emily.Backend output, got #{inspect(backend)}"
    end
  end

  defp assert_parity!(name, comparisons) do
    case Enum.find(comparisons, fn {_stage, values} -> values.max_abs > @tolerance end) do
      nil -> :ok
      {stage, values} -> raise "#{name} #{stage} failed parity: #{inspect(values)}"
    end
  end

  defp latency(durations) do
    sorted = Enum.sort(durations)

    %{
      "mean" => Float.round(Enum.sum(sorted) / length(sorted), 4),
      "p50" => percentile(sorted, 0.50),
      "p95" => percentile(sorted, 0.95),
      "p99" => percentile(sorted, 0.99),
      "min" => Float.round(hd(sorted), 4),
      "max" => Float.round(List.last(sorted), 4)
    }
  end

  defp percentile(sorted, fraction) do
    index = ceil(length(sorted) * fraction) - 1
    sorted |> Enum.at(index) |> Float.round(4)
  end

  defp stringify_comparisons(comparisons) do
    Map.new(comparisons, fn {stage, values} ->
      {stage,
       %{
         "max_abs" => values.max_abs,
         "mean_abs" => values.mean_abs,
         "shape" => values.shape
       }}
    end)
  end

  defp decision do
    %{
      "full_native_port_feasible" => true,
      "reason" =>
        "Both custom GLiNER head math and one representative mDeBERTa block match the pinned Python oracle on strict Emily GPU execution.",
      "not_proven" => [
        "remaining eleven mDeBERTa blocks",
        "tokenizer and prompt construction in native Elixir",
        "checkpoint conversion and complete weight loading",
        "end-to-end span reconstruction and benchmark accuracy",
        "full-model latency and memory"
      ]
    }
  end

  defp markdown(report) do
    [head, block] = report["spikes"]

    """
    # Native GLiNER GPU Spike Report

    Status: **#{report["status"]}**

    This report covers only two feasibility spikes. It is not evidence that a complete native GLiNER adapter exists.

    ## Contract

    - Model: `#{report["oracle"]["model"]["id"]}`
    - Revision: `#{report["oracle"]["model"]["revision"]}`
    - Oracle SHA-256: `#{report["oracle"]["sha256"]}`
    - Backend: `Emily.Backend`
    - Device requested: `:gpu`
    - Native compiler: enabled
    - Backend fallback: `:raise`
    - Compiler fallback: `:raise`
    - Maximum absolute error gate: `#{@tolerance}`

    Because both fallback paths raise, a successful run cannot silently execute unsupported operations through BinaryBackend or the evaluator. Outputs are Emily-backed tensors produced by a compiler explicitly configured for `:gpu`.

    ## Results

    | Spike | Status | First compile + run | Warm mean | Warm p95 | Largest max abs error |
    |---|---:|---:|---:|---:|---:|
    | BiLSTM + span head | #{head["status"]} | #{format_ms(head["compile_and_first_run_ms"])} | #{format_ms(head["warm_latency_ms"]["mean"])} | #{format_ms(head["warm_latency_ms"]["p95"])} | #{format_error(max_error(head))} |
    | mDeBERTa encoder block 0 | #{block["status"]} | #{format_ms(block["compile_and_first_run_ms"])} | #{format_ms(block["warm_latency_ms"]["mean"])} | #{format_ms(block["warm_latency_ms"]["p95"])} | #{format_error(max_error(block))} |

    ## Interpretation

    The two hard architecture boundaries are feasible in native Nx/Emily:

    1. PyTorch-compatible bidirectional LSTM gate ordering, markerV0 span construction, prompt projection, and span-label logits match Python.
    2. DeBERTa relative attention, including content-to-position and position-to-content terms, plus the feed-forward block match Python.

    This supports proceeding to a full port only if its expected product value justifies the remaining work. The spike does not prove the other eleven encoder blocks, tokenizer/prompt construction, complete checkpoint loading, end-to-end offsets, benchmark accuracy, full-model memory, or full-model latency.

    ## Reproduce

    ```bash
    .gliner-urchade-venv/bin/python eval/gliner/native_spikes/generate_oracles.py \\
      --output-dir .cache/gliner-native-spikes

    OBSCURA_REAL_MODEL_BACKEND=emily \\
      mix run eval/gliner/native_spikes/run.exs
    ```
    """
  end

  defp max_error(spike) do
    spike["parity"]
    |> Map.values()
    |> Enum.map(& &1["max_abs"])
    |> Enum.max()
  end

  defp format_ms(value), do: :erlang.float_to_binary(value / 1, decimals: 4) <> " ms"
  defp format_error(value), do: :erlang.float_to_binary(value / 1, scientific: 4)
end

Obscura.Eval.GLiNER.NativeSpikeRunner.run()
