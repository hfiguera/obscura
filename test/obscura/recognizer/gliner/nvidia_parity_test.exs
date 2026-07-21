defmodule Obscura.Recognizer.GLiNER.NvidiaParityTest do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.GLiNER.Ortex, as: GLiNEROrtex
  alias Obscura.Test.GLiNERParityAssertions

  @reference_path "eval/gliner/nvidia-parity-reference.json"
  @moduletag :gliner_nvidia

  setup_all do
    model_dir = System.fetch_env!("OBSCURA_GLINER_NVIDIA_MODEL_DIR")

    {:ok, serving} =
      GLiNEROrtex.build(model: :nvidia_gliner_pii_v1, model_dir: model_dir)

    reference = @reference_path |> File.read!() |> Jason.decode!()
    %{serving: serving, reference: reference}
  end

  test "matches Python inputs, ONNX logits, decoded labels, scores, and byte offsets", context do
    GLiNERParityAssertions.assert_parity(
      context.serving,
      :nvidia_gliner_pii_v1,
      context.reference
    )
  end
end
