defmodule Obscura.PrivacyFilter.Model.MLP do
  @moduledoc """
  Mixture-of-experts MLP block helpers for privacy-filter models.
  """

  alias Obscura.PrivacyFilter.Model.Linear
  alias Obscura.PrivacyFilter.Model.RMSNorm

  @spec swiglu(Nx.Tensor.t(), keyword()) :: Nx.Tensor.t()
  def swiglu(input, opts \\ []) do
    alpha = Keyword.get(opts, :alpha, 1.702)
    limit = Keyword.get(opts, :limit, 7.0)
    packed = Keyword.get(opts, :packed, false)
    width = input |> Nx.shape() |> elem(tuple_size(Nx.shape(input)) - 1)
    half = div(width, 2)

    {x_glu, x_linear} =
      if packed do
        {
          Nx.slice_along_axis(input, 0, width, axis: -1, strides: 2),
          Nx.slice_along_axis(input, 1, width - 1, axis: -1, strides: 2)
        }
      else
        {
          Nx.slice_along_axis(input, 0, half, axis: -1),
          Nx.slice_along_axis(input, half, half, axis: -1)
        }
      end

    x_glu = Nx.min(x_glu, limit)
    x_linear = Nx.clip(x_linear, -limit, limit)
    out_glu = Nx.multiply(x_glu, Nx.sigmoid(Nx.multiply(alpha, x_glu)))
    Nx.multiply(out_glu, Nx.add(x_linear, 1))
  end

  @spec forward(Nx.Tensor.t(), map(), map(), keyword()) :: Nx.Tensor.t()
  def forward(input, params, config, opts \\ []) do
    debug(input, params, config, opts).output
  end

  @spec debug(Nx.Tensor.t(), map(), map(), keyword()) :: map()
  def debug(input, params, config, opts \\ []) do
    experts_per_token = Map.fetch!(config, :experts_per_token)
    swiglu_limit = Map.get(config, :swiglu_limit, 7.0)
    packed_geglu = Map.get(config, :packed_geglu, false)

    {batch, tokens, hidden_size} = Nx.shape(input)
    normalized = RMSNorm.forward(input, Map.fetch!(params, :norm_scale), opts)
    flat = Nx.reshape(normalized, {batch * tokens, hidden_size})

    gate_logits =
      flat
      |> Nx.as_type({:f, 32})
      |> Linear.apply(
        Map.fetch!(params, :gate_weight) |> Nx.as_type({:f, 32}),
        Map.get(params, :gate_bias) && Map.fetch!(params, :gate_bias) |> Nx.as_type({:f, 32}),
        opts
      )

    {expert_scores, expert_indices} = Nx.top_k(gate_logits, k: experts_per_token)
    expert_weights = softmax(expert_scores, axis: -1)

    expert_output =
      flat
      |> run_selected_experts(expert_indices, expert_weights, params, swiglu_limit, packed_geglu)
      |> Nx.reshape({batch, tokens, hidden_size})
      |> Nx.as_type(Nx.type(input))

    output = Nx.add(input, expert_output)

    %{
      normalized: normalized,
      flat: flat,
      gate_logits: gate_logits,
      expert_scores: expert_scores,
      expert_indices: expert_indices,
      expert_weights: expert_weights,
      expert_output: expert_output,
      output: output
    }
  end

  defp softmax(tensor, opts) do
    axis = Keyword.fetch!(opts, :axis)
    max_value = Nx.reduce_max(tensor, axes: [axis], keep_axes: true)
    exp = Nx.exp(Nx.subtract(tensor, max_value))
    Nx.divide(exp, Nx.sum(exp, axes: [axis], keep_axes: true))
  end

  defp run_selected_experts(
         flat,
         expert_indices,
         expert_weights,
         params,
         swiglu_limit,
         packed_geglu
       ) do
    {flat_tokens, hidden_size} = Nx.shape(flat)
    {_flat_tokens, experts_per_token} = Nx.shape(expert_indices)
    {_num_experts, _hidden_size, mlp1_width} = Nx.shape(Map.fetch!(params, :mlp1_weight))
    {_num_experts, intermediate_size, _hidden_size} = Nx.shape(Map.fetch!(params, :mlp2_weight))

    flat_expert_indices = Nx.reshape(expert_indices, {flat_tokens * experts_per_token})

    mlp1_weight =
      params
      |> Map.fetch!(:mlp1_weight)
      |> Nx.take(flat_expert_indices)
      |> Nx.reshape({flat_tokens, experts_per_token, hidden_size, mlp1_width})
      |> Nx.as_type({:f, 32})

    mlp1_bias =
      params
      |> Map.fetch!(:mlp1_bias)
      |> Nx.take(flat_expert_indices)
      |> Nx.reshape({flat_tokens, experts_per_token, mlp1_width})
      |> Nx.as_type({:f, 32})

    mlp2_weight =
      params
      |> Map.fetch!(:mlp2_weight)
      |> Nx.take(flat_expert_indices)
      |> Nx.reshape({flat_tokens, experts_per_token, intermediate_size, hidden_size})
      |> Nx.as_type({:f, 32})

    mlp2_bias =
      params
      |> Map.fetch!(:mlp2_bias)
      |> Nx.take(flat_expert_indices)
      |> Nx.reshape({flat_tokens, experts_per_token, hidden_size})
      |> Nx.as_type({:f, 32})

    hidden =
      flat
      |> Nx.as_type({:f, 32})
      |> Nx.reshape({flat_tokens, 1, hidden_size, 1})
      |> Nx.multiply(mlp1_weight)
      |> Nx.sum(axes: [2])
      |> Nx.add(mlp1_bias)
      |> swiglu(limit: swiglu_limit, packed: packed_geglu)

    hidden
    |> Nx.reshape({flat_tokens, experts_per_token, intermediate_size, 1})
    |> Nx.multiply(mlp2_weight)
    |> Nx.sum(axes: [2])
    |> Nx.add(mlp2_bias)
    |> Nx.multiply(Nx.reshape(expert_weights, {flat_tokens, experts_per_token, 1}))
    |> Nx.sum(axes: [1])
  end
end
