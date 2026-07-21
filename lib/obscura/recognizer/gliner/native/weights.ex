defmodule Obscura.Recognizer.GLiNER.Native.Weights do
  @moduledoc false

  @encoder_prefix "token_rep_layer.bert_layer.model"
  @layer_count 12

  @spec load(String.t(), module(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(path, backend, opts \\ []) do
    safetensors = Module.concat(["Safetensors"])

    with true <- Code.ensure_loaded?(safetensors),
         tensors when is_map(tensors) <- safetensors.read!(path, lazy: true),
         :ok <- validate_names(tensors),
         {:ok, params} <- load_tensors(tensors, backend, opts) do
      {:ok, structure(params)}
    else
      false -> {:error, {:missing_optional_dependency, :safetensors}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      {:error, {:gliner_native_weights_load_failed, error.__struct__, Exception.message(error)}}
  end

  @spec expected_shapes() :: %{String.t() => tuple()}
  def expected_shapes do
    Map.new(base_shapes() ++ encoder_layer_shapes() ++ head_shapes())
  end

  defp load_tensors(tensors, backend, opts) do
    transfer = Keyword.get(opts, :backend_transfer, &Nx.backend_transfer/2)

    expected_shapes()
    |> Enum.reduce_while({:ok, %{}}, fn {name, shape}, {:ok, params} ->
      tensor = tensors |> Map.fetch!(name) |> Nx.to_tensor()

      cond do
        Nx.shape(tensor) != shape ->
          {:halt, {:error, {:gliner_native_tensor_shape_mismatch, name, shape, Nx.shape(tensor)}}}

        Nx.type(tensor) != {:f, 32} ->
          {:halt,
           {:error, {:gliner_native_tensor_type_mismatch, name, {:f, 32}, Nx.type(tensor)}}}

        true ->
          transferred = transfer.(tensor, backend)
          {:cont, {:ok, Map.put(params, name, transferred)}}
      end
    end)
  end

  defp validate_names(tensors) do
    expected = expected_shapes() |> Map.keys() |> MapSet.new()
    actual = tensors |> Map.keys() |> MapSet.new()

    if expected == actual do
      :ok
    else
      {:error,
       {:gliner_native_tensor_contract_mismatch,
        %{
          missing: expected |> MapSet.difference(actual) |> Enum.sort(),
          unexpected: actual |> MapSet.difference(expected) |> Enum.sort()
        }}}
    end
  end

  defp structure(params) do
    %{
      "embedding" => %{
        "word" => params["#{@encoder_prefix}.embeddings.word_embeddings.weight"],
        "norm_weight" => params["#{@encoder_prefix}.embeddings.LayerNorm.weight"],
        "norm_bias" => params["#{@encoder_prefix}.embeddings.LayerNorm.bias"]
      },
      "relative" => %{
        "embedding" => params["#{@encoder_prefix}.encoder.rel_embeddings.weight"],
        "norm_weight" => params["#{@encoder_prefix}.encoder.LayerNorm.weight"],
        "norm_bias" => params["#{@encoder_prefix}.encoder.LayerNorm.bias"]
      },
      "projection" => %{
        "weight" => params["token_rep_layer.projection.weight"],
        "bias" => params["token_rep_layer.projection.bias"]
      },
      "layers" =>
        0..(@layer_count - 1)
        |> Enum.map(&layer_params(params, &1))
        |> List.to_tuple(),
      "rnn" => select(params, "rnn.lstm."),
      "span" => select(params, "span_rep_layer.span_rep_layer."),
      "prompt" => select(params, "prompt_rep_layer.")
    }
  end

  defp layer_params(params, layer) do
    select(params, "#{@encoder_prefix}.encoder.layer.#{layer}.")
  end

  defp select(params, prefix) do
    for {name, tensor} <- params,
        String.starts_with?(name, prefix),
        into: %{},
        do: {String.replace_prefix(name, prefix, ""), tensor}
  end

  defp base_shapes do
    [
      {"#{@encoder_prefix}.embeddings.word_embeddings.weight", {250_105, 768}},
      {"#{@encoder_prefix}.embeddings.LayerNorm.weight", {768}},
      {"#{@encoder_prefix}.embeddings.LayerNorm.bias", {768}},
      {"#{@encoder_prefix}.encoder.rel_embeddings.weight", {512, 768}},
      {"#{@encoder_prefix}.encoder.LayerNorm.weight", {768}},
      {"#{@encoder_prefix}.encoder.LayerNorm.bias", {768}},
      {"token_rep_layer.projection.weight", {512, 768}},
      {"token_rep_layer.projection.bias", {512}}
    ]
  end

  defp encoder_layer_shapes do
    for layer <- 0..(@layer_count - 1),
        {suffix, shape} <- layer_shapes(),
        do: {"#{@encoder_prefix}.encoder.layer.#{layer}.#{suffix}", shape}
  end

  defp layer_shapes do
    [
      {"attention.self.query_proj.weight", {768, 768}},
      {"attention.self.query_proj.bias", {768}},
      {"attention.self.key_proj.weight", {768, 768}},
      {"attention.self.key_proj.bias", {768}},
      {"attention.self.value_proj.weight", {768, 768}},
      {"attention.self.value_proj.bias", {768}},
      {"attention.output.dense.weight", {768, 768}},
      {"attention.output.dense.bias", {768}},
      {"attention.output.LayerNorm.weight", {768}},
      {"attention.output.LayerNorm.bias", {768}},
      {"intermediate.dense.weight", {3072, 768}},
      {"intermediate.dense.bias", {3072}},
      {"output.dense.weight", {768, 3072}},
      {"output.dense.bias", {768}},
      {"output.LayerNorm.weight", {768}},
      {"output.LayerNorm.bias", {768}}
    ]
  end

  defp head_shapes do
    [
      {"rnn.lstm.weight_ih_l0", {1024, 512}},
      {"rnn.lstm.weight_hh_l0", {1024, 256}},
      {"rnn.lstm.bias_ih_l0", {1024}},
      {"rnn.lstm.bias_hh_l0", {1024}},
      {"rnn.lstm.weight_ih_l0_reverse", {1024, 512}},
      {"rnn.lstm.weight_hh_l0_reverse", {1024, 256}},
      {"rnn.lstm.bias_ih_l0_reverse", {1024}},
      {"rnn.lstm.bias_hh_l0_reverse", {1024}},
      {"span_rep_layer.span_rep_layer.project_start.0.weight", {2048, 512}},
      {"span_rep_layer.span_rep_layer.project_start.0.bias", {2048}},
      {"span_rep_layer.span_rep_layer.project_start.3.weight", {512, 2048}},
      {"span_rep_layer.span_rep_layer.project_start.3.bias", {512}},
      {"span_rep_layer.span_rep_layer.project_end.0.weight", {2048, 512}},
      {"span_rep_layer.span_rep_layer.project_end.0.bias", {2048}},
      {"span_rep_layer.span_rep_layer.project_end.3.weight", {512, 2048}},
      {"span_rep_layer.span_rep_layer.project_end.3.bias", {512}},
      {"span_rep_layer.span_rep_layer.out_project.0.weight", {2048, 1024}},
      {"span_rep_layer.span_rep_layer.out_project.0.bias", {2048}},
      {"span_rep_layer.span_rep_layer.out_project.3.weight", {512, 2048}},
      {"span_rep_layer.span_rep_layer.out_project.3.bias", {512}},
      {"prompt_rep_layer.0.weight", {2048, 512}},
      {"prompt_rep_layer.0.bias", {2048}},
      {"prompt_rep_layer.3.weight", {512, 2048}},
      {"prompt_rep_layer.3.bias", {512}}
    ]
  end
end
