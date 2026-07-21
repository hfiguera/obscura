defmodule Obscura.PrivacyFilter.Model.ParametersTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Model.Parameters
  alias Obscura.PrivacyFilter.Weights

  test "names returns logical checkpoint tensor names" do
    assert "embedding.weight" in Parameters.names(tiny_config())
    assert "block.0.attn.qkv.weight" in Parameters.names(tiny_config())
    assert "block.0.mlp.mlp1_weight" in Parameters.names(tiny_config())
    assert "unembedding.weight" in Parameters.names(tiny_config())
  end

  test "from_map assembles nested model parameter tree" do
    assert {:ok, params} = Parameters.from_map(tiny_tensors(), tiny_config())

    assert Nx.shape(params.embedding) == {3, 2}
    assert [_block] = params.blocks
    assert Nx.shape(params.blocks |> hd() |> get_in([:attn, :qkv_weight])) == {4, 2}
    assert Nx.shape(params.blocks |> hd() |> get_in([:mlp, :mlp1_weight])) == {2, 2, 4}
    assert params.unembedding_bias == nil
  end

  test "from_map assembles Hugging Face privacy-filter checkpoint tensor names" do
    assert {:ok, params} = Parameters.from_map(tiny_hf_tensors(), tiny_config())

    block = hd(params.blocks)

    assert Nx.shape(params.embedding) == {3, 2}
    assert Nx.shape(params.unembedding_weight) == {5, 2}
    assert Nx.shape(params.unembedding_bias) == {5}
    assert Nx.shape(block.attn.qkv_weight) == {4, 2}
    assert Nx.shape(block.attn.qkv_bias) == {4}

    assert Nx.to_flat_list(block.attn.qkv_bias) == [1, 2, 3, 4]
    assert Nx.shape(block.mlp.gate_weight) == {2, 2}
    assert Nx.shape(block.mlp.mlp1_weight) == {2, 2, 4}
    assert Nx.shape(block.mlp.mlp2_weight) == {2, 2, 2}
  end

  test "validate_metadata checks Hugging Face tensor names without materializing tensors" do
    weights = %Weights{
      path: "checkpoint",
      tensor_name_to_file:
        Map.new(tiny_hf_tensors(), fn {name, _tensor} -> {name, "model.safetensors"} end),
      tensor_metadata:
        Map.new(tiny_hf_tensors(), fn {name, tensor} ->
          {name, %{shape: Nx.shape(tensor), type: Nx.type(tensor), byte_size: 0}}
        end)
    }

    assert {:ok, summary} = Parameters.validate_metadata(weights, tiny_config())
    assert summary.assembled_blocks == 1
    assert summary.has_classifier_bias == true
  end

  test "validate_metadata rejects mismatched Hugging Face split projection shapes" do
    tensors =
      Map.put(
        tiny_hf_tensors(),
        "model.layers.0.self_attn.q_proj.weight",
        Nx.broadcast(0.0, {3, 2})
      )

    weights = weights_from_tensors(tensors)

    assert {:error,
            {:tensor_shape_mismatch, "model.layers.0.self_attn.q_proj.weight", {2, 2}, {3, 2}}} =
             Parameters.validate_metadata(weights, tiny_config())
  end

  test "validate_metadata accepts Python original MXFP4 expert weight pairs" do
    tensors =
      tiny_python_original_tensors()
      |> Map.drop(["block.0.mlp.swiglu.weight", "block.0.mlp.out.weight"])
      |> Map.merge(%{
        "block.0.mlp.swiglu.weight.blocks" => typed_broadcast(0, {2, 2, 1, 2}, {:u, 8}),
        "block.0.mlp.swiglu.weight.scales" => typed_broadcast(127, {2, 2, 1}, {:u, 8}),
        "block.0.mlp.out.weight.blocks" => typed_broadcast(0, {2, 2, 1, 1}, {:u, 8}),
        "block.0.mlp.out.weight.scales" => typed_broadcast(127, {2, 2, 1}, {:u, 8})
      })

    weights = weights_from_tensors(tensors)

    assert {:ok, summary} = Parameters.validate_metadata(weights, tiny_config())
    assert summary.assembled_blocks == 1
  end

  test "validate_metadata rejects MXFP4 pairs whose decoded shape is wrong" do
    tensors =
      tiny_python_original_tensors()
      |> Map.drop(["block.0.mlp.swiglu.weight"])
      |> Map.merge(%{
        "block.0.mlp.swiglu.weight.blocks" => typed_broadcast(0, {2, 2, 1, 1}, {:u, 8}),
        "block.0.mlp.swiglu.weight.scales" => typed_broadcast(127, {2, 2, 1}, {:u, 8})
      })

    weights = weights_from_tensors(tensors)

    assert {:error, {:tensor_shape_mismatch, "block.0.mlp.swiglu.weight", {2, 2, 4}, {2, 2, 2}}} =
             Parameters.validate_metadata(weights, tiny_config())
  end

  test "from_map rejects mismatched checkpoint tensor shapes" do
    tensors = Map.put(tiny_tensors(), "block.0.attn.qkv.weight", Nx.broadcast(0.0, {5, 2}))

    assert {:error, {:tensor_shape_mismatch, "block.0.attn.qkv.weight", {4, 2}, {5, 2}}} =
             Parameters.from_map(tensors, tiny_config())
  end

  defp tiny_config do
    %{
      num_hidden_layers: 1,
      vocab_size: 3,
      num_labels: 5,
      hidden_size: 2,
      intermediate_size: 2,
      num_experts: 2,
      head_dim: 1,
      num_attention_heads: 2,
      num_key_value_heads: 1
    }
  end

  defp tiny_tensors do
    %{
      "embedding.weight" => Nx.broadcast(0.0, {3, 2}),
      "norm.scale" => Nx.broadcast(1.0, {2}),
      "unembedding.weight" => Nx.broadcast(0.0, {5, 2}),
      "block.0.attn.norm.scale" => Nx.broadcast(1.0, {2}),
      "block.0.attn.sinks" => Nx.broadcast(0.0, {2}),
      "block.0.attn.qkv.weight" => Nx.broadcast(0.0, {4, 2}),
      "block.0.attn.qkv.bias" => Nx.broadcast(0.0, {4}),
      "block.0.attn.out.weight" => Nx.broadcast(0.0, {2, 2}),
      "block.0.attn.out.bias" => Nx.broadcast(0.0, {2}),
      "block.0.mlp.norm.scale" => Nx.broadcast(1.0, {2}),
      "block.0.mlp.gate.weight" => Nx.broadcast(0.0, {2, 2}),
      "block.0.mlp.gate.bias" => Nx.broadcast(0.0, {2}),
      "block.0.mlp.mlp1_weight" => Nx.broadcast(0.0, {2, 2, 4}),
      "block.0.mlp.mlp1_bias" => Nx.broadcast(0.0, {2, 4}),
      "block.0.mlp.mlp2_weight" => Nx.broadcast(0.0, {2, 2, 2}),
      "block.0.mlp.mlp2_bias" => Nx.broadcast(0.0, {2, 2})
    }
  end

  defp tiny_hf_tensors do
    %{
      "model.embed_tokens.weight" => Nx.broadcast(0.0, {3, 2}),
      "model.norm.weight" => Nx.broadcast(1.0, {2}),
      "score.weight" => Nx.broadcast(0.0, {5, 2}),
      "score.bias" => Nx.broadcast(0.0, {5}),
      "model.layers.0.input_layernorm.weight" => Nx.broadcast(1.0, {2}),
      "model.layers.0.self_attn.sinks" => Nx.broadcast(0.0, {2}),
      "model.layers.0.self_attn.q_proj.weight" => Nx.broadcast(0.0, {2, 2}),
      "model.layers.0.self_attn.k_proj.weight" => Nx.broadcast(0.0, {1, 2}),
      "model.layers.0.self_attn.v_proj.weight" => Nx.broadcast(0.0, {1, 2}),
      "model.layers.0.self_attn.q_proj.bias" => Nx.tensor([1, 2]),
      "model.layers.0.self_attn.k_proj.bias" => Nx.tensor([3]),
      "model.layers.0.self_attn.v_proj.bias" => Nx.tensor([4]),
      "model.layers.0.self_attn.o_proj.weight" => Nx.broadcast(0.0, {2, 2}),
      "model.layers.0.self_attn.o_proj.bias" => Nx.broadcast(0.0, {2}),
      "model.layers.0.post_attention_layernorm.weight" => Nx.broadcast(1.0, {2}),
      "model.layers.0.mlp.router.weight" => Nx.broadcast(0.0, {2, 2}),
      "model.layers.0.mlp.router.bias" => Nx.broadcast(0.0, {2}),
      "model.layers.0.mlp.experts.gate_up_proj" => Nx.broadcast(0.0, {2, 2, 4}),
      "model.layers.0.mlp.experts.gate_up_proj_bias" => Nx.broadcast(0.0, {2, 4}),
      "model.layers.0.mlp.experts.down_proj" => Nx.broadcast(0.0, {2, 2, 2}),
      "model.layers.0.mlp.experts.down_proj_bias" => Nx.broadcast(0.0, {2, 2})
    }
  end

  defp tiny_python_original_tensors do
    %{
      "embedding.weight" => Nx.broadcast(0.0, {3, 2}),
      "norm.scale" => Nx.broadcast(1.0, {2}),
      "unembedding.weight" => Nx.broadcast(0.0, {5, 2}),
      "block.0.attn.norm.scale" => Nx.broadcast(1.0, {2}),
      "block.0.attn.sinks" => Nx.broadcast(0.0, {2}),
      "block.0.attn.qkv.weight" => Nx.broadcast(0.0, {4, 2}),
      "block.0.attn.qkv.bias" => Nx.broadcast(0.0, {4}),
      "block.0.attn.out.weight" => Nx.broadcast(0.0, {2, 2}),
      "block.0.attn.out.bias" => Nx.broadcast(0.0, {2}),
      "block.0.mlp.norm.scale" => Nx.broadcast(1.0, {2}),
      "block.0.mlp.gate.weight" => Nx.broadcast(0.0, {2, 2}),
      "block.0.mlp.gate.bias" => Nx.broadcast(0.0, {2}),
      "block.0.mlp.swiglu.weight" => Nx.broadcast(0.0, {2, 2, 4}),
      "block.0.mlp.swiglu.bias" => Nx.broadcast(0.0, {2, 4}),
      "block.0.mlp.out.weight" => Nx.broadcast(0.0, {2, 2, 2}),
      "block.0.mlp.out.bias" => Nx.broadcast(0.0, {2, 2})
    }
  end

  defp weights_from_tensors(tensors) do
    %Weights{
      path: "checkpoint",
      tensor_name_to_file:
        Map.new(tensors, fn {name, _tensor} -> {name, "model.safetensors"} end),
      tensor_metadata:
        Map.new(tensors, fn {name, tensor} ->
          {name, %{shape: Nx.shape(tensor), type: Nx.type(tensor), byte_size: 0}}
        end)
    }
  end

  defp typed_broadcast(value, shape, type) do
    value
    |> Nx.tensor(type: type)
    |> Nx.broadcast(shape)
  end
end
