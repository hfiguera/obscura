defmodule Obscura.PrivacyFilter.Model.Attention do
  @moduledoc """
  Grouped-query local attention for native privacy-filter inference.

  This is a correctness-first reference implementation matching the Python
  privacy-filter attention semantics, including RoPE, sink logits stored in
  log2 space, grouped query heads, and bidirectional local windows.
  """

  alias Obscura.PrivacyFilter.Model.BFloat16
  alias Obscura.PrivacyFilter.Model.Linear
  alias Obscura.PrivacyFilter.Model.RMSNorm
  alias Obscura.PrivacyFilter.Model.RotaryEmbedding

  @spec forward(Nx.Tensor.t(), map(), map(), keyword()) :: Nx.Tensor.t()
  def forward(input, params, config, opts \\ []) do
    head_dim = Map.fetch!(config, :head_dim)
    num_attention_heads = Map.fetch!(config, :num_attention_heads)
    num_key_value_heads = Map.fetch!(config, :num_key_value_heads)

    normalized = RMSNorm.forward(input, Map.fetch!(params, :norm_scale), opts)

    qkv =
      Linear.apply(normalized, Map.fetch!(params, :qkv_weight), Map.get(params, :qkv_bias), opts)

    q_width = num_attention_heads * head_dim
    kv_width = num_key_value_heads * head_dim

    query = Nx.slice_along_axis(qkv, 0, q_width, axis: -1)
    key = Nx.slice_along_axis(qkv, q_width, kv_width, axis: -1)
    value = Nx.slice_along_axis(qkv, q_width + kv_width, kv_width, axis: -1)

    {query, key} = apply_rotary(query, key, config, opts)

    qk_scale = 1 / :math.sqrt(:math.sqrt(head_dim))
    {batch, tokens, _width} = Nx.shape(query)
    round_bf16? = torch_bf16_parity?(config, opts)
    query = maybe_round_bf16(Nx.multiply(query, qk_scale), round_bf16?)
    key = maybe_round_bf16(Nx.multiply(key, qk_scale), round_bf16?)
    q_mult = div(num_attention_heads, num_key_value_heads)

    query = Nx.reshape(query, {batch, tokens, num_key_value_heads, q_mult, head_dim})
    key = Nx.reshape(key, {batch, tokens, num_key_value_heads, head_dim})
    value = Nx.reshape(value, {batch, tokens, num_key_value_heads, head_dim})

    attention =
      local_attention(query, key, value, Map.fetch!(params, :sinks), config,
        attention_mask: Keyword.get(opts, :attention_mask),
        round_bf16: round_bf16?
      )

    projection =
      Linear.apply(attention, Map.fetch!(params, :out_weight), Map.get(params, :out_bias), opts)

    projection_for_residual =
      if round_bf16?,
        do: BFloat16.round_to_nearest_even(projection),
        else: Nx.as_type(projection, Nx.type(input))

    input
    |> Nx.as_type({:f, 32})
    |> Nx.add(projection_for_residual)
    |> maybe_round_bf16(round_bf16?)
  end

  @spec debug(Nx.Tensor.t(), map(), map(), keyword()) :: map()
  def debug(input, params, config, opts \\ []) do
    head_dim = Map.fetch!(config, :head_dim)
    num_attention_heads = Map.fetch!(config, :num_attention_heads)
    num_key_value_heads = Map.fetch!(config, :num_key_value_heads)

    normalized = RMSNorm.forward(input, Map.fetch!(params, :norm_scale), opts)

    qkv =
      Linear.apply(normalized, Map.fetch!(params, :qkv_weight), Map.get(params, :qkv_bias), opts)

    q_width = num_attention_heads * head_dim
    kv_width = num_key_value_heads * head_dim

    query = Nx.slice_along_axis(qkv, 0, q_width, axis: -1)
    key = Nx.slice_along_axis(qkv, q_width, kv_width, axis: -1)
    value = Nx.slice_along_axis(qkv, q_width + kv_width, kv_width, axis: -1)

    {query, key} = apply_rotary(query, key, config, opts)

    qk_scale = 1 / :math.sqrt(:math.sqrt(head_dim))
    {batch, tokens, _width} = Nx.shape(query)
    round_bf16? = torch_bf16_parity?(config, opts)
    query_rotary = query
    key_rotary = key
    query = maybe_round_bf16(Nx.multiply(query, qk_scale), round_bf16?)
    key = maybe_round_bf16(Nx.multiply(key, qk_scale), round_bf16?)
    q_mult = div(num_attention_heads, num_key_value_heads)

    query = Nx.reshape(query, {batch, tokens, num_key_value_heads, q_mult, head_dim})
    key = Nx.reshape(key, {batch, tokens, num_key_value_heads, head_dim})
    value = Nx.reshape(value, {batch, tokens, num_key_value_heads, head_dim})

    attention_debug =
      local_attention_debug(query, key, value, Map.fetch!(params, :sinks), config,
        attention_mask: Keyword.get(opts, :attention_mask),
        round_bf16: round_bf16?
      )

    attention = attention_debug.output

    projection =
      Linear.apply(attention, Map.fetch!(params, :out_weight), Map.get(params, :out_bias), opts)

    projection_for_residual =
      if round_bf16?,
        do: BFloat16.round_to_nearest_even(projection),
        else: Nx.as_type(projection, Nx.type(input))

    output =
      input
      |> Nx.as_type({:f, 32})
      |> Nx.add(projection_for_residual)
      |> maybe_round_bf16(round_bf16?)

    %{
      normalized: normalized,
      qkv: qkv,
      query_rotary: Nx.reshape(query_rotary, {batch, tokens, num_attention_heads * head_dim}),
      key_rotary: Nx.reshape(key_rotary, {batch, tokens, num_key_value_heads * head_dim}),
      value: value |> Nx.reshape({batch, tokens, num_key_value_heads * head_dim}),
      query_scaled: Nx.reshape(query, {batch, tokens, num_attention_heads * head_dim}),
      key_scaled: Nx.reshape(key, {batch, tokens, num_key_value_heads * head_dim}),
      attention_scores: attention_debug.scores,
      attention_weights: attention_debug.weights,
      attention: attention,
      projection: projection,
      output: output
    }
  end

  defp apply_rotary(query, key, config, opts) do
    RotaryEmbedding.apply_flattened(query, key,
      head_dim: Map.fetch!(config, :head_dim),
      base: Map.fetch!(config, :rope_theta),
      initial_context_length: Map.fetch!(config, :initial_context_length),
      scaling_factor: Map.get(config, :rope_scaling_factor, 1.0),
      ntk_alpha: Map.get(config, :rope_ntk_alpha, 1.0),
      ntk_beta: Map.get(config, :rope_ntk_beta, 32.0),
      round_bf16: torch_bf16_parity?(config, opts)
    )
  end

  @spec local_attention(
          Nx.Tensor.t(),
          Nx.Tensor.t(),
          Nx.Tensor.t(),
          Nx.Tensor.t(),
          map(),
          keyword()
        ) ::
          Nx.Tensor.t()
  def local_attention(query, key, value, sinks, config, opts \\ []) do
    local_attention_output(query, key, value, sinks, config, opts)
  end

  defp local_attention_output(query, key, value, sinks, config, opts) do
    {batch, tokens, kv_heads, q_mult, head_dim} = Nx.shape(query)
    attention_mask = Keyword.get(opts, :attention_mask)
    round_bf16? = Keyword.get(opts, :round_bf16, false)
    sm_scale = Map.get(config, :sm_scale, 1.0)

    left_context =
      if Map.get(config, :bidirectional_context, false),
        do: Map.fetch!(config, :bidirectional_left_context),
        else: Map.get(config, :sliding_window, 0)

    right_context =
      if Map.get(config, :bidirectional_context, false),
        do: Map.fetch!(config, :bidirectional_right_context),
        else: 0

    offsets = Enum.to_list(-left_context..right_context)
    window_count = length(offsets)
    base_mask = attention_mask || Nx.broadcast(1, {batch, tokens})

    key_windows = stack_shifted_windows(key, offsets, {batch, tokens, kv_heads, head_dim})
    value_windows = stack_shifted_windows(value, offsets, {batch, tokens, kv_heads, head_dim})
    mask_windows = stack_shifted_masks(base_mask, offsets, {batch, tokens})

    scores =
      query
      |> Nx.new_axis(-2)
      |> Nx.multiply(Nx.new_axis(key_windows, -3))
      |> Nx.sum(axes: [-1])
      |> maybe_round_bf16(round_bf16?)
      |> Nx.multiply(sm_scale)

    invalid_mask =
      mask_windows
      |> Nx.equal(0)
      |> Nx.new_axis(2)
      |> Nx.new_axis(3)
      |> Nx.broadcast({batch, tokens, kv_heads, q_mult, window_count})

    scores = Nx.select(invalid_mask, Nx.broadcast(-1.0e9, Nx.shape(scores)), scores)

    sink_scores =
      sinks
      |> Nx.reshape({kv_heads, q_mult})
      |> Nx.multiply(:math.log(2.0))
      |> Nx.reshape({1, 1, kv_heads, q_mult, 1})
      |> Nx.broadcast({batch, tokens, kv_heads, q_mult, 1})

    weights =
      scores
      |> then(&Nx.concatenate([&1, sink_scores], axis: -1))
      |> tensor_softmax(axis: -1)

    value_weights =
      weights
      |> Nx.slice_along_axis(0, window_count, axis: -1)
      |> maybe_round_bf16(round_bf16?)

    value_windows
    |> Nx.new_axis(-3)
    |> Nx.multiply(Nx.new_axis(value_weights, -1))
    |> Nx.sum(axes: [-2])
    |> maybe_round_bf16(round_bf16?)
    |> Nx.reshape({batch, tokens, kv_heads * q_mult * head_dim})
  end

  defp stack_shifted_windows(tensor, offsets, {batch, tokens, kv_heads, head_dim}) do
    offsets
    |> Enum.map(&shift_token_axis(tensor, &1, {batch, tokens, kv_heads, head_dim}))
    |> Nx.stack(axis: 3)
  end

  defp stack_shifted_masks(mask, offsets, {batch, tokens}) do
    offsets
    |> Enum.map(&shift_mask(mask, &1, {batch, tokens}))
    |> Nx.stack(axis: 2)
  end

  defp shift_token_axis(tensor, 0, _shape), do: tensor

  defp shift_token_axis(_tensor, offset, {batch, tokens, kv_heads, head_dim})
       when abs(offset) >= tokens do
    Nx.broadcast(0.0, {batch, tokens, kv_heads, head_dim})
  end

  defp shift_token_axis(tensor, offset, {batch, tokens, kv_heads, head_dim}) when offset > 0 do
    valid = tokens - offset
    padding = Nx.broadcast(0.0, {batch, offset, kv_heads, head_dim})

    shifted = Nx.slice(tensor, [0, offset, 0, 0], [batch, valid, kv_heads, head_dim])
    Nx.concatenate([shifted, padding], axis: 1)
  end

  defp shift_token_axis(tensor, offset, {batch, tokens, kv_heads, head_dim}) do
    padding_width = -offset
    valid = tokens - padding_width
    padding = Nx.broadcast(0.0, {batch, padding_width, kv_heads, head_dim})
    sliced = Nx.slice(tensor, [0, 0, 0, 0], [batch, valid, kv_heads, head_dim])

    Nx.concatenate([padding, sliced], axis: 1)
  end

  defp shift_mask(mask, 0, _shape), do: mask

  defp shift_mask(_mask, offset, {batch, tokens}) when abs(offset) >= tokens do
    Nx.broadcast(0, {batch, tokens})
  end

  defp shift_mask(mask, offset, {batch, tokens}) when offset > 0 do
    valid = tokens - offset
    padding = Nx.broadcast(0, {batch, offset})

    shifted = Nx.slice(mask, [0, offset], [batch, valid])
    Nx.concatenate([shifted, padding], axis: 1)
  end

  defp shift_mask(mask, offset, {batch, tokens}) do
    padding_width = -offset
    valid = tokens - padding_width
    padding = Nx.broadcast(0, {batch, padding_width})
    sliced = Nx.slice(mask, [0, 0], [batch, valid])

    Nx.concatenate([padding, sliced], axis: 1)
  end

  defp local_attention_debug(query, key, value, sinks, config, opts) do
    {batch, tokens, kv_heads, q_mult, head_dim} = Nx.shape(query)
    attention_mask = Keyword.get(opts, :attention_mask)
    round_bf16? = Keyword.get(opts, :round_bf16, false)
    sm_scale = Map.get(config, :sm_scale, 1.0)

    left_context =
      if Map.get(config, :bidirectional_context, false) do
        Map.fetch!(config, :bidirectional_left_context)
      else
        Map.get(config, :sliding_window, 0)
      end

    right_context =
      if Map.get(config, :bidirectional_context, false) do
        Map.fetch!(config, :bidirectional_right_context)
      else
        0
      end

    query_values = Nx.to_list(query)
    key_values = Nx.to_list(key)
    value_values = Nx.to_list(value)
    sink_values = Nx.to_flat_list(sinks)
    mask_values = if is_nil(attention_mask), do: nil, else: Nx.to_list(attention_mask)

    {scores, weights, output} =
      for batch_index <- 0..(batch - 1) do
        attention_debug_batch(
          {query_values, key_values, value_values, sink_values, mask_values},
          batch_index,
          {tokens, kv_heads, q_mult, head_dim, left_context, right_context, sm_scale, round_bf16?}
        )
      end
      |> split_attention_debug(kv_heads, q_mult)

    %{
      scores: Nx.tensor(scores, type: {:f, 32}),
      weights: Nx.tensor(weights, type: {:f, 32}),
      output: Nx.tensor(output, type: Nx.type(value))
    }
  end

  defp attention_debug_batch(
         values,
         batch_index,
         {tokens, kv_heads, q_mult, head_dim, left_context, right_context, sm_scale, round_bf16?}
       ) do
    for token_index <- 0..(tokens - 1) do
      attention_debug_token(
        values,
        {batch_index, token_index},
        {tokens, kv_heads, q_mult, head_dim, left_context, right_context, sm_scale, round_bf16?}
      )
    end
  end

  defp attention_debug_token(
         {query_values, key_values, value_values, sink_values, mask_values},
         {batch_index, token_index},
         {tokens, kv_heads, q_mult, head_dim, left_context, right_context, sm_scale, round_bf16?}
       ) do
    for kv_head_index <- 0..(kv_heads - 1), q_index <- 0..(q_mult - 1) do
      global_head_index = kv_head_index * q_mult + q_index

      attention_for_head_debug(
        query_values,
        key_values,
        value_values,
        sink_values,
        mask_values,
        {batch_index, token_index, kv_head_index, q_index, global_head_index},
        {tokens, head_dim, left_context, right_context, sm_scale, round_bf16?}
      )
    end
  end

  defp attention_for_head_debug(
         query_values,
         key_values,
         value_values,
         sink_values,
         mask_values,
         {batch_index, token_index, kv_head_index, q_index, global_head_index},
         {tokens, head_dim, left_context, right_context, sm_scale, round_bf16?}
       ) do
    query_vector =
      query_values
      |> Enum.at(batch_index)
      |> Enum.at(token_index)
      |> Enum.at(kv_head_index)
      |> Enum.at(q_index)

    window_offsets = Enum.to_list(-left_context..right_context)

    sink_score = Enum.at(sink_values, global_head_index) * :math.log(2.0)

    candidates =
      Enum.map(window_offsets, fn offset ->
        key_index = token_index + offset

        if key_index >= 0 and key_index < tokens and
             (is_nil(mask_values) or
                mask_values |> Enum.at(batch_index) |> Enum.at(key_index) |> truthy_mask?()) do
          key_vector =
            key_values
            |> Enum.at(batch_index)
            |> Enum.at(key_index)
            |> Enum.at(kv_head_index)

          value_vector =
            value_values
            |> Enum.at(batch_index)
            |> Enum.at(key_index)
            |> Enum.at(kv_head_index)

          score =
            query_vector
            |> dot(key_vector)
            |> maybe_round_bf16_scalar(round_bf16?)
            |> Kernel.*(sm_scale)

          {score, value_vector}
        else
          {-1.0e9, List.duplicate(0.0, head_dim)}
        end
      end)

    scores = Enum.map(candidates, &elem(&1, 0)) ++ [sink_score]
    weights = softmax(scores)

    value_weights =
      weights
      |> Enum.take(length(candidates))
      |> maybe_round_bf16_scalars(round_bf16?)

    output =
      candidates
      |> Enum.map(&elem(&1, 1))
      |> weighted_sum(value_weights, head_dim)
      |> maybe_round_bf16_scalars(round_bf16?)

    %{scores: scores, weights: weights, output: output}
  end

  defp split_attention_debug(batch_values, kv_heads, q_mult) do
    scores =
      Enum.map(batch_values, fn token_values ->
        Enum.map(token_values, fn head_values ->
          head_values
          |> Enum.map(& &1.scores)
          |> Enum.chunk_every(q_mult)
          |> Enum.take(kv_heads)
        end)
      end)

    weights =
      Enum.map(batch_values, fn token_values ->
        Enum.map(token_values, fn head_values ->
          head_values
          |> Enum.map(& &1.weights)
          |> Enum.chunk_every(q_mult)
          |> Enum.take(kv_heads)
        end)
      end)

    output =
      Enum.map(batch_values, fn token_values ->
        Enum.map(token_values, fn head_values ->
          head_values
          |> Enum.map(& &1.output)
          |> List.flatten()
        end)
      end)

    {scores, weights, output}
  end

  defp weighted_sum([], _weights, head_dim), do: List.duplicate(0.0, head_dim)

  defp weighted_sum(vectors, weights, head_dim) do
    Enum.reduce(Enum.zip(vectors, weights), List.duplicate(0.0, head_dim), fn {vector, weight},
                                                                              acc ->
      Enum.zip_with(acc, vector, &(&1 + &2 * weight))
    end)
  end

  defp dot(left, right) do
    left
    |> Enum.zip(right)
    |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
  end

  defp softmax(values) do
    max_value = Enum.max(values)
    exps = Enum.map(values, &:math.exp(&1 - max_value))
    total = Enum.sum(exps)
    Enum.map(exps, &(&1 / total))
  end

  defp tensor_softmax(tensor, opts) do
    axis = Keyword.fetch!(opts, :axis)
    max_value = Nx.reduce_max(tensor, axes: [axis], keep_axes: true)
    exp = Nx.exp(Nx.subtract(tensor, max_value))
    Nx.divide(exp, Nx.sum(exp, axes: [axis], keep_axes: true))
  end

  defp truthy_mask?(value), do: value not in [false, 0, 0.0, nil]

  defp maybe_round_bf16(tensor, true), do: BFloat16.round_to_nearest_even(tensor)
  defp maybe_round_bf16(tensor, false), do: tensor
  defp maybe_round_bf16_scalar(value, true), do: BFloat16.round_scalar_to_nearest_even(value)
  defp maybe_round_bf16_scalar(value, false), do: value

  defp maybe_round_bf16_scalars(values, true),
    do: Enum.map(values, &BFloat16.round_scalar_to_nearest_even/1)

  defp maybe_round_bf16_scalars(values, false), do: values

  defp torch_bf16_parity?(config, opts),
    do:
      Keyword.get(opts, :torch_bf16_parity, false) and Map.get(config, :param_dtype) == "bfloat16"
end
