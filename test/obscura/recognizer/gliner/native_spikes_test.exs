Code.require_file(
  "../../../../eval/gliner/native_spikes/native.exs",
  __DIR__
)

defmodule Obscura.Recognizer.GLiNER.NativeSpikesTest do
  use ExUnit.Case, async: false

  alias Obscura.Eval.GLiNER.NativeSpikes

  @moduletag :real_model
  @tolerance 5.0e-5

  setup_all do
    unless Code.ensure_loaded?(Emily.Backend) and Code.ensure_loaded?(Emily.Compiler) do
      flunk("run this test with OBSCURA_REAL_MODEL_BACKEND=emily")
    end

    Application.put_env(:emily, :fallback, :raise)
    Application.put_env(:emily, :native_fallback, :raise)
    {:ok, _applications} = Application.ensure_all_started(:emily)

    directory = System.get_env("OBSCURA_GLINER_NATIVE_SPIKE_DIR", ".cache/gliner-native-spikes")
    tensors = NativeSpikes.load!(directory)
    {:ok, tensors: tensors}
  end

  test "BiLSTM and markerV0 span head match the pinned Python oracle on Emily GPU", %{
    tensors: tensors
  } do
    actual =
      run_gpu(
        &NativeSpikes.head/2,
        NativeSpikes.head_inputs(tensors),
        NativeSpikes.head_params(tensors)
      )

    assert_emily!(actual)

    assert_parity!(
      actual,
      NativeSpikes.head_expected(tensors),
      NativeSpikes.head_names()
    )
  end

  test "mDeBERTa encoder block zero matches the pinned Python oracle on Emily GPU", %{
    tensors: tensors
  } do
    actual =
      run_gpu(
        &NativeSpikes.block/2,
        NativeSpikes.block_inputs(tensors),
        NativeSpikes.block_params(tensors)
      )

    assert_emily!(actual)

    assert_parity!(
      actual,
      NativeSpikes.block_expected(tensors),
      NativeSpikes.block_names()
    )
  end

  defp run_gpu(function, input, params) do
    compiled =
      Nx.Defn.jit(function,
        compiler: Emily.Compiler,
        device: :gpu,
        native: true,
        native_fallback: :raise,
        fuse: false
      )

    compiled.(transfer(input), transfer(params))
  end

  defp transfer(container), do: Nx.backend_transfer(container, {Emily.Backend, device: :gpu})

  defp assert_emily!(result) do
    backend = result |> elem(0) |> Map.fetch!(:data) |> Map.fetch!(:__struct__)
    assert backend == Module.concat(["Emily", "Backend"])
  end

  defp assert_parity!(actual, expected, names) do
    for {stage, comparison} <- NativeSpikes.compare(actual, expected, names) do
      assert comparison.max_abs <= @tolerance,
             "#{stage} max abs error #{comparison.max_abs} exceeds #{@tolerance}"
    end
  end
end
