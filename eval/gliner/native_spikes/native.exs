defmodule Obscura.Eval.GLiNER.NativeSpikes do
  @moduledoc false

  import Nx.Defn

  @head_names [
    "rnn",
    "span",
    "prompt",
    "logits"
  ]

  @block_names [
    "self_context",
    "attention_probs",
    "attention_output",
    "intermediate",
    "output"
  ]

  def load!(directory) do
    path = Path.join(directory, "oracles.safetensors")

    unless File.regular?(path) do
      raise "missing native-spike oracle at #{path}; run generate_oracles.py first"
    end

    unless Code.ensure_loaded?(Safetensors) do
      raise "the optional :safetensors dependency is required for native GLiNER spikes"
    end

    Safetensors.read!(path)
  end

  def head_inputs(tensors), do: select(tensors, "head.input.")
  def head_params(tensors), do: select(tensors, "head.param.")
  def block_inputs(tensors), do: select(tensors, "block.input.")
  def block_params(tensors), do: select(tensors, "block.param.")

  def head_expected(tensors), do: expected(tensors, "head.expected.", @head_names)
  def block_expected(tensors), do: expected(tensors, "block.expected.", @block_names)

  def head(input, params), do: head_impl(input, params)
  def block(input, params), do: block_impl(input, params)

  defn head_impl(input, params) do
    rnn = bidirectional_lstm(input["words"], params)

    start = mlp(rnn, params, "span.span_rep_layer.project_start")
    finish = mlp(rnn, params, "span.span_rep_layer.project_end")
    span_idx = Nx.squeeze(input["span_idx"], axes: [0])
    start_idx = span_idx[[.., 0]]
    end_idx = span_idx[[.., 1]]
    start = Nx.take(start, start_idx, axis: 1)
    finish = Nx.take(finish, end_idx, axis: 1)

    span =
      Nx.concatenate([start, finish], axis: -1)
      |> Nx.max(0.0)
      |> mlp(params, "span.span_rep_layer.out_project")
      |> Nx.reshape({1, Nx.axis_size(input["words"], 1), 12, 512})

    prompt = mlp(input["prompts"], params, "prompt")

    logits =
      Nx.multiply(
        Nx.new_axis(span, 3),
        prompt |> Nx.new_axis(1) |> Nx.new_axis(1)
      )
      |> Nx.sum(axes: [-1])

    {rnn, span, prompt, logits}
  end

  defn block_impl(input, params) do
    hidden = input["hidden"]
    {batch, length, _hidden_size} = Nx.shape(hidden)
    heads = 12
    head_size = 64

    query = attention_projection(hidden, params, "query_proj", heads, head_size)
    key = attention_projection(hidden, params, "key_proj", heads, head_size)
    value = attention_projection(hidden, params, "value_proj", heads, head_size)

    content = pairwise_dot(query, key)
    relative = input["relative_embeddings"]
    pos_key = relative_projection(relative, params, "key_proj", heads, head_size)
    pos_query = relative_projection(relative, params, "query_proj", heads, head_size)

    c2p = pairwise_relative_dot(query, pos_key)
    c2p_idx = Nx.clip(input["relative_pos"] + 256, 0, 511)
    c2p_idx = Nx.broadcast(c2p_idx, {batch, heads, length, length})
    c2p = Nx.take_along_axis(c2p, c2p_idx, axis: 3)

    p2c = pairwise_relative_dot(key, pos_query)
    p2c_idx = Nx.squeeze(Nx.clip(-input["relative_pos"] + 256, 0, 511), axes: [0])
    p2c_idx = Nx.broadcast(p2c_idx, {batch, heads, length, length})

    p2c =
      Nx.take_along_axis(p2c, p2c_idx, axis: 3)
      |> Nx.transpose(axes: [0, 1, 3, 2])

    scores = Nx.divide(content + c2p + p2c, 13.856406460551018)
    mask = Nx.broadcast(input["attention_mask"], {batch, heads, length, length})
    scores = Nx.select(mask, scores, Nx.tensor(-3.4028234663852886e38, type: :f32))
    probabilities = softmax(scores)

    self_context =
      Nx.multiply(Nx.new_axis(probabilities, 4), Nx.new_axis(value, 2))
      |> Nx.sum(axes: [3])
      |> Nx.transpose(axes: [0, 2, 1, 3])
      |> Nx.reshape({batch, length, heads * head_size})

    attention_output =
      linear(
        self_context,
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

    output =
      linear(intermediate, params["output.dense.weight"], params["output.dense.bias"])
      |> Nx.add(attention_output)
      |> layer_norm(params["output.LayerNorm.weight"], params["output.LayerNorm.bias"])

    {self_context, probabilities, attention_output, intermediate, output}
  end

  def compare(actual, expected, names) do
    actual
    |> Tuple.to_list()
    |> Enum.zip(names)
    |> Enum.map(fn {value, name} ->
      reference = Map.fetch!(expected, name)
      difference = Nx.abs(Nx.subtract(value, reference))

      {name,
       %{
         max_abs: difference |> Nx.reduce_max() |> Nx.to_number(),
         mean_abs: difference |> Nx.mean() |> Nx.to_number(),
         shape: Tuple.to_list(Nx.shape(value))
       }}
    end)
    |> Map.new()
  end

  def head_names, do: @head_names
  def block_names, do: @block_names

  defp select(tensors, prefix) do
    for {name, tensor} <- tensors,
        String.starts_with?(name, prefix),
        into: %{},
        do: {String.replace_prefix(name, prefix, ""), tensor}
  end

  defp expected(tensors, prefix, names) do
    Map.new(names, fn name -> {name, Map.fetch!(tensors, prefix <> name)} end)
  end

  deftransformp bidirectional_lstm(input, params) do
    forward = lstm(input, params, "rnn.lstm", false)
    backward = lstm(input, params, "rnn.lstm", true)
    Nx.concatenate([forward, backward], axis: -1)
  end

  deftransformp lstm(input, params, prefix, reverse?) do
    suffix = if reverse?, do: "_reverse", else: ""
    weight_ih = params["#{prefix}.weight_ih_l0#{suffix}"]
    weight_hh = params["#{prefix}.weight_hh_l0#{suffix}"]
    bias_ih = params["#{prefix}.bias_ih_l0#{suffix}"]
    bias_hh = params["#{prefix}.bias_hh_l0#{suffix}"]
    input = if reverse?, do: Nx.reverse(input, axes: [1]), else: input
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

        input_gate = Nx.slice_along_axis(gates, 0, hidden_size, axis: -1)
        forget_gate = Nx.slice_along_axis(gates, hidden_size, hidden_size, axis: -1)

        candidate =
          Nx.slice_along_axis(gates, hidden_size * 2, hidden_size, axis: -1)

        output_gate =
          Nx.slice_along_axis(gates, hidden_size * 3, hidden_size, axis: -1)

        input_gate = Nx.sigmoid(input_gate)
        forget_gate = Nx.sigmoid(forget_gate)
        candidate = Nx.tanh(candidate)
        output_gate = Nx.sigmoid(output_gate)

        cell =
          Nx.add(
            Nx.multiply(forget_gate, cell),
            Nx.multiply(input_gate, candidate)
          )

        hidden = Nx.multiply(output_gate, Nx.tanh(cell))
        {hidden, cell, [hidden | outputs]}
      end)

    outputs = outputs |> Enum.reverse() |> Nx.stack(axis: 1)
    if reverse?, do: Nx.reverse(outputs, axes: [1]), else: outputs
  end

  defnp mlp(input, params, prefix) do
    input
    |> linear(params["#{prefix}.0.weight"], params["#{prefix}.0.bias"])
    |> Nx.max(0.0)
    |> linear(params["#{prefix}.3.weight"], params["#{prefix}.3.bias"])
  end

  defnp linear(input, weight, bias) do
    input
    |> Nx.dot([-1], weight, [1])
    |> Nx.add(bias)
  end

  defnp attention_projection(input, params, name, heads, head_size) do
    input
    |> linear(params["attention.self.#{name}.weight"], params["attention.self.#{name}.bias"])
    |> Nx.reshape({Nx.axis_size(input, 0), Nx.axis_size(input, 1), heads, head_size})
    |> Nx.transpose(axes: [0, 2, 1, 3])
  end

  defnp relative_projection(input, params, name, heads, head_size) do
    input
    |> linear(params["attention.self.#{name}.weight"], params["attention.self.#{name}.bias"])
    |> Nx.reshape({Nx.axis_size(input, 0), heads, head_size})
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
    input * 0.5 * (1.0 + Nx.erf(input / 1.4142135623730951))
  end
end
