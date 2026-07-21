defmodule Obscura.PrivacyFilter.Model.QKVMicroFixtureTest do
  use ExUnit.Case, async: true

  @fixture "eval/privacy_filter/fixtures/python_original_qkv_micro.json"

  test "python-original QKV micro fixture includes scalar dot-product evidence" do
    fixture = @fixture |> File.read!() |> Jason.decode!()

    assert fixture["status"] == "completed"
    assert fixture["operation"] == "block.0.attention.qkv"
    assert fixture["torch"]["input_dtype"] == "torch.bfloat16"
    assert fixture["torch"]["weight_dtype"] == "torch.bfloat16"
    assert fixture["torch"]["output_dtype"] == "torch.bfloat16"

    for probe <- fixture["scalar_probes"] do
      actual =
        probe["input_values"]
        |> Enum.zip(probe["weight_values"])
        |> Enum.reduce(0.0, fn {input_value, weight_value}, acc ->
          acc + input_value * weight_value
        end)
        |> Kernel.+(probe["bias_value"])

      assert_in_delta actual, probe["manual_f32_sum_with_bias"], 1.0e-6
      assert probe["torch_single_linear_value"] == probe["torch_output_value"]
    end
  end
end
