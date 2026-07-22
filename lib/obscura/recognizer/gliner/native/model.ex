if Code.ensure_loaded?(Nx.Defn) do
  defmodule Obscura.Recognizer.GLiNER.Native.Model do
    @moduledoc false

    import Nx.Defn

    @layer_count 12
    @heads 12
    @head_size 64
    @max_width 12
    @hidden_size 512
    @attention_scale 13.856406460551018
    @sqrt_two 1.4142135623730951

    def forward(input, params), do: forward_impl(input, params)
    def trace(input, params), do: trace_impl(input, params)

    defn forward_impl(input, params) do
      {_trace, logits} = model(input, params)
      logits
    end

    defn trace_impl(input, params) do
      model(input, params)
    end

    defnp model(input, params) do
      embedding = embeddings(input, params["embedding"])

      relative =
        layer_norm(
          params["relative"]["embedding"],
          params["relative"]["norm_weight"],
          params["relative"]["norm_bias"]
        )

      attention_mask = pair_attention_mask(input["attention_mask"])
      layers = encoder_layers(embedding, attention_mask, input["relative_pos"], relative, params)
      encoded = elem(layers, @layer_count)

      projected =
        linear(encoded, params["projection"]["weight"], params["projection"]["bias"])

      prompt_indexes = Nx.squeeze(input["prompt_token_indexes"], axes: [0])
      word_indexes = Nx.squeeze(input["word_token_indexes"], axes: [0])
      prompts = Nx.take(projected, prompt_indexes, axis: 1)
      words = Nx.take(projected, word_indexes, axis: 1)
      rnn = bidirectional_lstm(words, input["word_mask"], params["rnn"])
      span = span_representation(rnn, input, params["span"])
      prompt = mlp(prompts, params["prompt"], "")

      logits =
        Nx.multiply(
          Nx.new_axis(span, 3),
          prompt |> Nx.new_axis(1) |> Nx.new_axis(1)
        )
        |> Nx.sum(axes: [-1])

      trace = %{
        "embedding" => embedding,
        "layers" => layers,
        "projected" => projected,
        "prompts" => prompts,
        "words" => words,
        "rnn" => rnn,
        "span" => span,
        "prompt" => prompt
      }

      {trace, logits}
    end

    defnp embeddings(input, params) do
      params["word"]
      |> Nx.take(input["input_ids"])
      |> layer_norm(params["norm_weight"], params["norm_bias"])
      |> Nx.multiply(Nx.new_axis(Nx.as_type(input["attention_mask"], :f32), 2))
    end

    defnp pair_attention_mask(mask) do
      row = mask |> Nx.new_axis(1) |> Nx.new_axis(3)
      column = mask |> Nx.new_axis(1) |> Nx.new_axis(2)
      Nx.multiply(row, column)
    end

    deftransformp encoder_layers(hidden, attention_mask, relative_pos, relative, params) do
      {states, _hidden} =
        Enum.map_reduce(0..(@layer_count - 1), hidden, fn layer, current ->
          output =
            encoder_block(
              current,
              attention_mask,
              relative_pos,
              relative,
              elem(params["layers"], layer)
            )

          {output, output}
        end)

      List.to_tuple([hidden | states])
    end

    defnp encoder_block(hidden, attention_mask, relative_pos, relative, params) do
      {batch, length, _hidden_size} = Nx.shape(hidden)

      query = attention_projection(hidden, params, "query_proj")
      key = attention_projection(hidden, params, "key_proj")
      value = attention_projection(hidden, params, "value_proj")
      content = pairwise_dot(query, key)
      pos_key = relative_projection(relative, params, "key_proj")
      pos_query = relative_projection(relative, params, "query_proj")

      c2p = pairwise_relative_dot(query, pos_key)
      c2p_idx = Nx.clip(relative_pos + 256, 0, 511)
      c2p_idx = Nx.broadcast(c2p_idx, {batch, @heads, length, length})
      c2p = Nx.take_along_axis(c2p, c2p_idx, axis: 3)

      p2c = pairwise_relative_dot(key, pos_query)
      p2c_idx = Nx.squeeze(Nx.clip(-relative_pos + 256, 0, 511), axes: [0])
      p2c_idx = Nx.broadcast(p2c_idx, {batch, @heads, length, length})

      p2c =
        Nx.take_along_axis(p2c, p2c_idx, axis: 3)
        |> Nx.transpose(axes: [0, 1, 3, 2])

      scores = Nx.divide(content + c2p + p2c, @attention_scale)
      mask = Nx.broadcast(attention_mask, {batch, @heads, length, length})
      scores = Nx.select(mask, scores, Nx.tensor(-3.402_823_466_385_288_6e38, type: :f32))
      probabilities = softmax(scores)

      context =
        Nx.multiply(Nx.new_axis(probabilities, 4), Nx.new_axis(value, 2))
        |> Nx.sum(axes: [3])
        |> Nx.transpose(axes: [0, 2, 1, 3])
        |> Nx.reshape({batch, length, @heads * @head_size})

      attention_output =
        linear(
          context,
          params["attention.output.dense.weight"],
          params["attention.output.dense.bias"]
        )
        |> Nx.add(hidden)
        |> layer_norm(
          params["attention.output.LayerNorm.weight"],
          params["attention.output.LayerNorm.bias"]
        )

      intermediate =
        linear(
          attention_output,
          params["intermediate.dense.weight"],
          params["intermediate.dense.bias"]
        )
        |> gelu()

      linear(intermediate, params["output.dense.weight"], params["output.dense.bias"])
      |> Nx.add(attention_output)
      |> layer_norm(params["output.LayerNorm.weight"], params["output.LayerNorm.bias"])
    end

    defnp span_representation(rnn, input, params) do
      span_idx =
        Nx.multiply(input["span_idx"], Nx.new_axis(input["span_mask"], 2))
        |> Nx.squeeze(axes: [0])

      start_idx = span_idx[[.., 0]]
      end_idx = span_idx[[.., 1]]
      start = rnn |> mlp(params, "project_start.") |> Nx.take(start_idx, axis: 1)
      finish = rnn |> mlp(params, "project_end.") |> Nx.take(end_idx, axis: 1)

      Nx.concatenate([start, finish], axis: -1)
      |> Nx.max(0.0)
      |> mlp(params, "out_project.")
      |> Nx.reshape({1, Nx.axis_size(rnn, 1), @max_width, @hidden_size})
    end

    deftransformp bidirectional_lstm(input, mask, params) do
      forward = lstm(input, mask, params, false)
      backward = lstm(input, mask, params, true)
      Nx.concatenate([forward, backward], axis: -1)
    end

    deftransformp lstm(input, mask, params, reverse?) do
      suffix = if reverse?, do: "_reverse", else: ""
      weight_ih = params["weight_ih_l0#{suffix}"]
      weight_hh = params["weight_hh_l0#{suffix}"]
      bias_ih = params["bias_ih_l0#{suffix}"]
      bias_hh = params["bias_hh_l0#{suffix}"]
      input = if reverse?, do: Nx.reverse(input, axes: [1]), else: input
      mask = if reverse?, do: Nx.reverse(mask, axes: [1]), else: mask
      batch = Nx.axis_size(input, 0)
      steps = Nx.axis_size(input, 1)
      hidden_size = Nx.axis_size(weight_hh, 1)
      zero = Nx.broadcast(Nx.tensor(0.0, type: Nx.type(input)), {batch, hidden_size})

      {_hidden, _cell, outputs} =
        Enum.reduce(0..(steps - 1), {zero, zero, []}, fn index, {hidden, cell, outputs} ->
          current = input[[.., index, ..]]

          gates =
            Nx.add(
              linear(current, weight_ih, bias_ih),
              linear(hidden, weight_hh, bias_hh)
            )

          input_gate = Nx.slice_along_axis(gates, 0, hidden_size, axis: -1) |> Nx.sigmoid()

          forget_gate =
            Nx.slice_along_axis(gates, hidden_size, hidden_size, axis: -1) |> Nx.sigmoid()

          candidate =
            Nx.slice_along_axis(gates, hidden_size * 2, hidden_size, axis: -1) |> Nx.tanh()

          output_gate =
            Nx.slice_along_axis(gates, hidden_size * 3, hidden_size, axis: -1) |> Nx.sigmoid()

          candidate_cell =
            Nx.add(
              Nx.multiply(forget_gate, cell),
              Nx.multiply(input_gate, candidate)
            )

          candidate_hidden = Nx.multiply(output_gate, Nx.tanh(candidate_cell))

          valid =
            mask[[.., index]]
            |> Nx.new_axis(1)
            |> Nx.as_type(:u8)
            |> Nx.broadcast(Nx.shape(hidden))

          cell = Nx.select(valid, candidate_cell, cell)
          hidden = Nx.select(valid, candidate_hidden, hidden)
          output = Nx.select(valid, hidden, zero)
          {hidden, cell, [output | outputs]}
        end)

      outputs = outputs |> Enum.reverse() |> Nx.stack(axis: 1)
      if reverse?, do: Nx.reverse(outputs, axes: [1]), else: outputs
    end

    defnp mlp(input, params, prefix) do
      input
      |> linear(params["#{prefix}0.weight"], params["#{prefix}0.bias"])
      |> Nx.max(0.0)
      |> linear(params["#{prefix}3.weight"], params["#{prefix}3.bias"])
    end

    defnp linear(input, weight, bias) do
      input
      |> Nx.dot([-1], weight, [1])
      |> Nx.add(bias)
    end

    defnp attention_projection(input, params, name) do
      input
      |> linear(params["attention.self.#{name}.weight"], params["attention.self.#{name}.bias"])
      |> Nx.reshape({Nx.axis_size(input, 0), Nx.axis_size(input, 1), @heads, @head_size})
      |> Nx.transpose(axes: [0, 2, 1, 3])
    end

    defnp relative_projection(input, params, name) do
      input
      |> linear(params["attention.self.#{name}.weight"], params["attention.self.#{name}.bias"])
      |> Nx.reshape({Nx.axis_size(input, 0), @heads, @head_size})
      |> Nx.transpose(axes: [1, 0, 2])
    end

    defnp pairwise_dot(left, right) do
      Nx.multiply(Nx.new_axis(left, 3), Nx.new_axis(right, 2))
      |> Nx.sum(axes: [-1])
    end

    defnp pairwise_relative_dot(left, relative) do
      Nx.multiply(Nx.new_axis(left, 3), relative |> Nx.new_axis(0) |> Nx.new_axis(2))
      |> Nx.sum(axes: [-1])
    end

    defnp softmax(input) do
      maximum = Nx.reduce_max(input, axes: [-1], keep_axes: true)
      exponentials = Nx.exp(input - maximum)
      exponentials / Nx.sum(exponentials, axes: [-1], keep_axes: true)
    end

    defnp layer_norm(input, weight, bias) do
      mean = Nx.mean(input, axes: [-1], keep_axes: true)
      variance = Nx.mean(Nx.pow(input - mean, 2), axes: [-1], keep_axes: true)
      (input - mean) / Nx.sqrt(variance + 1.0e-7) * weight + bias
    end

    defnp gelu(input) do
      input * 0.5 * (1.0 + Nx.erf(input / @sqrt_two))
    end
  end
else
  defmodule Obscura.Recognizer.GLiNER.Native.Model do
    @moduledoc false

    def forward(_input, _params), do: {:error, {:missing_optional_dependency, :nx}}
    def trace(_input, _params), do: {:error, {:missing_optional_dependency, :nx}}
  end
end
