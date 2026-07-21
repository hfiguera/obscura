defmodule Obscura.PrivacyFilter.ModelTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Model
  alias Obscura.PrivacyFilter.Model.Attention
  alias Obscura.PrivacyFilter.Model.MLP
  alias Obscura.PrivacyFilter.Model.RMSNorm
  alias Obscura.PrivacyFilter.Model.RotaryEmbedding

  test "RMSNorm matches root mean square normalization over final dimension" do
    input = Nx.tensor([[[3.0, 4.0]]])
    scale = Nx.tensor([2.0, 0.5])

    assert_close(RMSNorm.forward(input, scale, eps: 0.0), [[[1.6970563, 1.1313709]]])
  end

  test "rotary embedding preserves flattened query/key shapes" do
    query = Nx.tensor([[[1.0, 0.0, 0.0, 1.0], [0.5, 0.5, 1.0, 1.0]]])
    key = Nx.tensor([[[1.0, 0.0], [0.0, 1.0]]])

    {rotated_query, rotated_key} =
      RotaryEmbedding.apply_flattened(query, key,
        head_dim: 2,
        base: 10_000.0,
        initial_context_length: 16,
        scaling_factor: 1.0,
        ntk_alpha: 1.0,
        ntk_beta: 32.0
      )

    assert Nx.shape(rotated_query) == {1, 2, 4}
    assert Nx.shape(rotated_key) == {1, 2, 2}
    assert_close(Nx.slice_along_axis(rotated_query, 0, 1, axis: 1), [[[1.0, 0.0, 0.0, 1.0]]])
  end

  test "rotary embedding preserves native privacy-filter checkpoint head layout" do
    query = Nx.broadcast(0.25, {1, 20, 14 * 64})
    key = Nx.broadcast(0.5, {1, 20, 2 * 64})

    {rotated_query, rotated_key} =
      RotaryEmbedding.apply_flattened(query, key,
        head_dim: 64,
        base: 10_000.0,
        initial_context_length: 4096,
        scaling_factor: 1.0,
        ntk_alpha: 1.0,
        ntk_beta: 32.0
      )

    assert Nx.shape(rotated_query) == {1, 20, 14 * 64}
    assert Nx.shape(rotated_key) == {1, 20, 2 * 64}
  end

  test "local attention applies bidirectional window and sink denominator" do
    query = Nx.tensor([[[[[0.0]]], [[[0.0]]], [[[0.0]]]]])
    key = Nx.tensor([[[[0.0]], [[0.0]], [[0.0]]]])
    value = Nx.tensor([[[[1.0]], [[3.0]], [[5.0]]]])
    sinks = Nx.tensor([0.0])

    output =
      Attention.local_attention(query, key, value, sinks, %{
        bidirectional_context: true,
        bidirectional_left_context: 1,
        bidirectional_right_context: 1
      })

    assert_close(output, [[[1.3333334], [2.25], [2.6666667]]])
  end

  test "local attention excludes masked padding keys from the denominator" do
    query = Nx.tensor([[[[[0.0]]], [[[0.0]]], [[[0.0]]]]])
    key = Nx.tensor([[[[0.0]], [[0.0]], [[0.0]]]])
    value = Nx.tensor([[[[1.0]], [[3.0]], [[5.0]]]])
    sinks = Nx.tensor([0.0])
    attention_mask = Nx.tensor([[1, 1, 0]])

    output =
      Attention.local_attention(
        query,
        key,
        value,
        sinks,
        %{
          bidirectional_context: true,
          bidirectional_left_context: 1,
          bidirectional_right_context: 1
        },
        attention_mask: attention_mask
      )

    assert_close(output, [[[1.3333334], [1.3333334], [1.5]]])
  end

  test "SwiGLU supports unpacked and packed privacy-filter variants" do
    unpacked = Nx.tensor([[1.0, 2.0, 3.0, 4.0]])
    packed = Nx.tensor([[1.0, 3.0, 2.0, 4.0]])

    unpacked_output = MLP.swiglu(unpacked, alpha: 1.0, limit: 7.0, packed: false)
    packed_output = MLP.swiglu(packed, alpha: 1.0, limit: 7.0, packed: true)

    assert Nx.shape(unpacked_output) == {1, 2}
    assert Nx.shape(packed_output) == {1, 2}
    assert_close(unpacked_output, packed_output)
  end

  test "MLP forward keeps residual shape for sparse expert routing" do
    input = Nx.tensor([[[1.0, 2.0], [3.0, 4.0]]])

    params = %{
      norm_scale: Nx.tensor([1.0, 1.0]),
      gate_weight: Nx.tensor([[1.0, 0.0], [0.0, 1.0]]),
      gate_bias: Nx.tensor([0.0, 0.0]),
      mlp1_weight: Nx.broadcast(0.0, {2, 2, 4}),
      mlp1_bias: Nx.broadcast(0.0, {2, 4}),
      mlp2_weight: Nx.broadcast(0.0, {2, 2, 2}),
      mlp2_bias: Nx.broadcast(0.0, {2, 2})
    }

    output =
      MLP.forward(input, params, %{
        experts_per_token: 1,
        swiglu_limit: 7.0,
        packed_geglu: false
      })

    assert Nx.shape(output) == {1, 2, 2}
    assert_close(output, input)
  end

  test "full model forward runs with zero transformer blocks" do
    token_ids = Nx.tensor([[0, 1]])

    params = %{
      embedding: Nx.tensor([[1.0, 0.0], [0.0, 1.0]]),
      blocks: [],
      norm_scale: Nx.tensor([1.0, 1.0]),
      unembedding_weight: Nx.tensor([[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]])
    }

    logits = Model.forward(token_ids, params, %{})

    assert Nx.shape(logits) == {1, 2, 3}
  end

  test "full model forward_result returns ok logits without raising" do
    token_ids = Nx.tensor([[0, 1]])

    params = %{
      embedding: Nx.tensor([[1.0, 0.0], [0.0, 1.0]]),
      blocks: [],
      norm_scale: Nx.tensor([1.0, 1.0]),
      unembedding_weight: Nx.tensor([[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]])
    }

    assert {:ok, logits} = Model.forward_result(token_ids, params, %{})
    assert Nx.shape(logits) == {1, 2, 3}
  end

  test "full model forward_result returns a controlled error for invalid token shape" do
    token_ids = Nx.tensor([0, 1])

    assert {:error, {:privacy_filter_model_forward_failed, ArgumentError}} =
             Model.forward_result(token_ids, %{}, %{})
  end

  test "full model forward_result returns a controlled error for missing parameters" do
    token_ids = Nx.tensor([[0, 1]])

    assert {:error, {:privacy_filter_model_forward_failed, KeyError}} =
             Model.forward_result(token_ids, %{}, %{})
  end

  test "full model forward applies optional classifier bias" do
    token_ids = Nx.tensor([[0]])

    params = %{
      embedding: Nx.tensor([[1.0, 0.0]]),
      blocks: [],
      norm_scale: Nx.tensor([1.0, 1.0]),
      unembedding_weight: Nx.tensor([[1.0, 0.0], [0.0, 1.0]]),
      unembedding_bias: Nx.tensor([0.5, 2.0])
    }

    assert_close(Model.forward(token_ids, params, %{}), [[[1.9142135, 2.0]]])
  end

  defp assert_close(left, right) do
    assert Nx.all_close(left, Nx.tensor(right), atol: 1.0e-5, rtol: 1.0e-5)
  end
end
