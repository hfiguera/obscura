defmodule Obscura.PrivacyFilter.Model.Parameters do
  @moduledoc """
  Builds the parameter map consumed by `Obscura.PrivacyFilter.Model`.

  The local privacy-filter reference and the published Hugging Face checkpoint
  use different physical tensor names. This module accepts both and assembles
  the internal fused parameter tree consumed by `Obscura.PrivacyFilter.Model`.
  """

  alias Obscura.PrivacyFilter.Weights

  @type fetcher :: (String.t() -> {:ok, Nx.Tensor.t()} | {:error, term()})

  @spec load(Weights.t(), map()) :: {:ok, map()} | {:error, term()}
  def load(%Weights{} = checkpoint, config) do
    load_with_fetcher(config, &Weights.get(checkpoint, &1))
  end

  @spec validate_metadata(Weights.t(), map()) :: {:ok, map()} | {:error, term()}
  def validate_metadata(%Weights{} = checkpoint, config) do
    validate_with_metadata_fetcher(config, &Weights.metadata(checkpoint, &1))
  end

  @spec from_map(%{String.t() => Nx.Tensor.t()}, map()) :: {:ok, map()} | {:error, term()}
  def from_map(tensors, config) when is_map(tensors) do
    load_with_fetcher(config, fn name ->
      case Map.fetch(tensors, name) do
        {:ok, tensor} -> {:ok, tensor}
        :error -> {:error, {:missing_tensor, name}}
      end
    end)
  end

  @spec names(map()) :: [String.t()]
  def names(config) do
    top_level_names() ++ Enum.flat_map(0..(field(config, :num_hidden_layers) - 1), &block_names/1)
  end

  @spec load_with_fetcher(map(), fetcher()) :: {:ok, map()} | {:error, term()}
  def load_with_fetcher(config, fetcher) when is_function(fetcher, 1) do
    with {:ok, embedding} <-
           fetch_tensor_any(
             fetcher,
             ["embedding.weight", "model.embed_tokens.weight"],
             embedding_shape(config)
           ),
         {:ok, blocks} <- load_blocks(config, fetcher),
         {:ok, norm_scale} <-
           fetch_tensor_any(fetcher, ["norm.scale", "model.norm.weight"], hidden_shape(config)),
         {:ok, unembedding_weight} <-
           fetch_tensor_any(
             fetcher,
             ["unembedding.weight", "score.weight"],
             {field(config, :num_labels), field(config, :hidden_size)}
           ),
         {:ok, unembedding_bias} <-
           fetch_optional_tensor_any(
             fetcher,
             ["unembedding.bias", "score.bias"],
             {field(config, :num_labels)}
           ) do
      {:ok,
       %{
         embedding: embedding,
         blocks: blocks,
         norm_scale: norm_scale,
         unembedding_weight: unembedding_weight,
         unembedding_bias: unembedding_bias
       }}
    end
  end

  defp load_blocks(config, fetcher) do
    0..(field(config, :num_hidden_layers) - 1)
    |> Enum.reduce_while({:ok, []}, fn layer, {:ok, blocks} ->
      case load_block(config, fetcher, layer) do
        {:ok, block} -> {:cont, {:ok, [block | blocks]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, blocks} -> {:ok, Enum.reverse(blocks)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_block(config, fetcher, layer) do
    with {:ok, attn} <- load_attention(config, fetcher, layer),
         {:ok, mlp} <- load_mlp(config, fetcher, layer) do
      {:ok, %{attn: attn, mlp: mlp}}
    end
  end

  defp load_attention(config, fetcher, layer) do
    prefix = "block.#{layer}.attn"
    hf_prefix = "model.layers.#{layer}.self_attn"
    hidden_size = field(config, :hidden_size)
    head_dim = field(config, :head_dim)
    attention_heads = field(config, :num_attention_heads)
    kv_heads = field(config, :num_key_value_heads)
    qkv_dim = head_dim * (attention_heads + 2 * kv_heads)

    with {:ok, norm_scale} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.norm.scale", "model.layers.#{layer}.input_layernorm.weight"],
             {hidden_size}
           ),
         {:ok, sinks} <-
           fetch_tensor_any(fetcher, ["#{prefix}.sinks", "#{hf_prefix}.sinks"], {attention_heads}),
         {:ok, qkv_weight} <-
           load_qkv_weight(
             fetcher,
             prefix,
             hf_prefix,
             qkv_dim,
             hidden_size,
             attention_heads,
             kv_heads,
             head_dim
           ),
         {:ok, qkv_bias} <-
           load_qkv_bias(fetcher, prefix, hf_prefix, qkv_dim, attention_heads, kv_heads, head_dim),
         {:ok, out_weight} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.out.weight", "#{hf_prefix}.o_proj.weight"],
             {hidden_size, attention_heads * head_dim}
           ),
         {:ok, out_bias} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.out.bias", "#{hf_prefix}.o_proj.bias"],
             {hidden_size}
           ) do
      {:ok,
       %{
         norm_scale: norm_scale,
         sinks: sinks,
         qkv_weight: qkv_weight,
         qkv_bias: qkv_bias,
         out_weight: out_weight,
         out_bias: out_bias
       }}
    end
  end

  defp load_mlp(config, fetcher, layer) do
    prefix = "block.#{layer}.mlp"
    hf_prefix = "model.layers.#{layer}.mlp"
    hidden_size = field(config, :hidden_size)
    intermediate_size = field(config, :intermediate_size)
    num_experts = field(config, :num_experts)

    with {:ok, norm_scale} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.norm.scale", "model.layers.#{layer}.post_attention_layernorm.weight"],
             {hidden_size}
           ),
         {:ok, gate_weight} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.gate.weight", "#{hf_prefix}.router.weight"],
             {num_experts, hidden_size}
           ),
         {:ok, gate_bias} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.gate.bias", "#{hf_prefix}.router.bias"],
             {num_experts}
           ),
         {:ok, mlp1_weight} <-
           fetch_tensor_any(
             fetcher,
             [
               "#{prefix}.mlp1_weight",
               "#{prefix}.swiglu.weight",
               "#{hf_prefix}.experts.gate_up_proj"
             ],
             {num_experts, hidden_size, intermediate_size * 2}
           ),
         {:ok, mlp1_bias} <-
           fetch_tensor_any(
             fetcher,
             [
               "#{prefix}.mlp1_bias",
               "#{prefix}.swiglu.bias",
               "#{hf_prefix}.experts.gate_up_proj_bias"
             ],
             {num_experts, intermediate_size * 2}
           ),
         {:ok, mlp2_weight} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.mlp2_weight", "#{prefix}.out.weight", "#{hf_prefix}.experts.down_proj"],
             {num_experts, intermediate_size, hidden_size}
           ),
         {:ok, mlp2_bias} <-
           fetch_tensor_any(
             fetcher,
             ["#{prefix}.mlp2_bias", "#{prefix}.out.bias", "#{hf_prefix}.experts.down_proj_bias"],
             {num_experts, hidden_size}
           ) do
      {:ok,
       %{
         norm_scale: norm_scale,
         gate_weight: gate_weight,
         gate_bias: gate_bias,
         mlp1_weight: mlp1_weight,
         mlp1_bias: mlp1_bias,
         mlp2_weight: mlp2_weight,
         mlp2_bias: mlp2_bias
       }}
    end
  end

  defp fetch_tensor(fetcher, name, expected_shape) do
    with {:ok, tensor} <- fetcher.(name) do
      actual_shape = Nx.shape(tensor)

      if actual_shape == expected_shape do
        {:ok, tensor}
      else
        {:error, {:tensor_shape_mismatch, name, expected_shape, actual_shape}}
      end
    end
  end

  defp validate_with_metadata_fetcher(config, fetcher) do
    with :ok <-
           validate_metadata_any(
             fetcher,
             ["embedding.weight", "model.embed_tokens.weight"],
             embedding_shape(config)
           ),
         :ok <- validate_metadata_blocks(config, fetcher),
         :ok <-
           validate_metadata_any(
             fetcher,
             ["norm.scale", "model.norm.weight"],
             hidden_shape(config)
           ),
         :ok <-
           validate_metadata_any(
             fetcher,
             ["unembedding.weight", "score.weight"],
             {field(config, :num_labels), field(config, :hidden_size)}
           ),
         {:ok, has_classifier_bias} <-
           optional_metadata_present?(
             fetcher,
             ["unembedding.bias", "score.bias"],
             {field(config, :num_labels)}
           ) do
      {:ok,
       %{
         assembled_blocks: field(config, :num_hidden_layers),
         has_classifier_bias: has_classifier_bias
       }}
    end
  end

  defp validate_metadata_blocks(config, fetcher) do
    0..(field(config, :num_hidden_layers) - 1)
    |> Enum.reduce_while(:ok, fn layer, :ok ->
      case validate_metadata_block(config, fetcher, layer) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_metadata_block(config, fetcher, layer) do
    with :ok <- validate_metadata_attention(config, fetcher, layer),
         do: validate_metadata_mlp(config, fetcher, layer)
  end

  defp validate_metadata_attention(config, fetcher, layer) do
    prefix = "block.#{layer}.attn"
    hf_prefix = "model.layers.#{layer}.self_attn"
    hidden_size = field(config, :hidden_size)
    head_dim = field(config, :head_dim)
    attention_heads = field(config, :num_attention_heads)
    kv_heads = field(config, :num_key_value_heads)
    qkv_dim = head_dim * (attention_heads + 2 * kv_heads)

    with :ok <-
           validate_metadata_any(
             fetcher,
             ["#{prefix}.norm.scale", "model.layers.#{layer}.input_layernorm.weight"],
             {hidden_size}
           ),
         :ok <-
           validate_metadata_any(
             fetcher,
             ["#{prefix}.sinks", "#{hf_prefix}.sinks"],
             {attention_heads}
           ),
         :ok <-
           validate_qkv_metadata(
             fetcher,
             prefix,
             hf_prefix,
             qkv_dim,
             hidden_size,
             attention_heads,
             kv_heads,
             head_dim
           ),
         :ok <-
           validate_metadata_any(
             fetcher,
             ["#{prefix}.out.weight", "#{hf_prefix}.o_proj.weight"],
             {hidden_size, attention_heads * head_dim}
           ) do
      validate_metadata_any(
        fetcher,
        ["#{prefix}.out.bias", "#{hf_prefix}.o_proj.bias"],
        {hidden_size}
      )
    end
  end

  defp validate_metadata_mlp(config, fetcher, layer) do
    prefix = "block.#{layer}.mlp"
    hf_prefix = "model.layers.#{layer}.mlp"
    hidden_size = field(config, :hidden_size)
    intermediate_size = field(config, :intermediate_size)
    num_experts = field(config, :num_experts)

    with :ok <-
           validate_metadata_any(
             fetcher,
             ["#{prefix}.norm.scale", "model.layers.#{layer}.post_attention_layernorm.weight"],
             {hidden_size}
           ),
         :ok <-
           validate_metadata_any(
             fetcher,
             ["#{prefix}.gate.weight", "#{hf_prefix}.router.weight"],
             {num_experts, hidden_size}
           ),
         :ok <-
           validate_metadata_any(
             fetcher,
             ["#{prefix}.gate.bias", "#{hf_prefix}.router.bias"],
             {num_experts}
           ),
         :ok <-
           validate_expert_weight_metadata_any(
             fetcher,
             [
               "#{prefix}.mlp1_weight",
               "#{prefix}.swiglu.weight",
               "#{hf_prefix}.experts.gate_up_proj"
             ],
             {num_experts, hidden_size, intermediate_size * 2}
           ),
         :ok <-
           validate_metadata_any(
             fetcher,
             [
               "#{prefix}.mlp1_bias",
               "#{prefix}.swiglu.bias",
               "#{hf_prefix}.experts.gate_up_proj_bias"
             ],
             {num_experts, intermediate_size * 2}
           ),
         :ok <-
           validate_expert_weight_metadata_any(
             fetcher,
             ["#{prefix}.mlp2_weight", "#{prefix}.out.weight", "#{hf_prefix}.experts.down_proj"],
             {num_experts, intermediate_size, hidden_size}
           ) do
      validate_metadata_any(
        fetcher,
        ["#{prefix}.mlp2_bias", "#{prefix}.out.bias", "#{hf_prefix}.experts.down_proj_bias"],
        {num_experts, hidden_size}
      )
    end
  end

  defp validate_qkv_metadata(
         fetcher,
         prefix,
         hf_prefix,
         qkv_dim,
         hidden_size,
         attention_heads,
         kv_heads,
         head_dim
       ) do
    case validate_metadata(fetcher, "#{prefix}.qkv.weight", {qkv_dim, hidden_size}) do
      :ok ->
        validate_metadata(fetcher, "#{prefix}.qkv.bias", {qkv_dim})

      {:error, {:missing_tensor, _name}} ->
        with :ok <-
               validate_metadata(
                 fetcher,
                 "#{hf_prefix}.q_proj.weight",
                 {attention_heads * head_dim, hidden_size}
               ),
             :ok <-
               validate_metadata(
                 fetcher,
                 "#{hf_prefix}.k_proj.weight",
                 {kv_heads * head_dim, hidden_size}
               ),
             :ok <-
               validate_metadata(
                 fetcher,
                 "#{hf_prefix}.v_proj.weight",
                 {kv_heads * head_dim, hidden_size}
               ),
             :ok <-
               validate_metadata(
                 fetcher,
                 "#{hf_prefix}.q_proj.bias",
                 {attention_heads * head_dim}
               ),
             :ok <-
               validate_metadata(fetcher, "#{hf_prefix}.k_proj.bias", {kv_heads * head_dim}) do
          validate_metadata(fetcher, "#{hf_prefix}.v_proj.bias", {kv_heads * head_dim})
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_metadata_any(fetcher, names, expected_shape) do
    Enum.reduce_while(names, {:error, {:missing_tensor, names}}, fn name, _acc ->
      case validate_metadata(fetcher, name, expected_shape) do
        :ok -> {:halt, :ok}
        {:error, {:missing_tensor, _missing}} -> {:cont, {:error, {:missing_tensor, names}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_expert_weight_metadata_any(fetcher, names, expected_shape) do
    Enum.reduce_while(names, {:error, {:missing_tensor, names}}, fn name, _acc ->
      case validate_expert_weight_metadata(fetcher, name, expected_shape) do
        :ok -> {:halt, :ok}
        {:error, {:missing_tensor, _missing}} -> {:cont, {:error, {:missing_tensor, names}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_expert_weight_metadata(fetcher, name, expected_shape) do
    case validate_metadata(fetcher, name, expected_shape) do
      :ok ->
        :ok

      {:error, {:missing_tensor, ^name}} ->
        validate_mxfp4_metadata(fetcher, name, expected_shape)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_mxfp4_metadata(fetcher, name, expected_shape) do
    blocks_name = "#{name}.blocks"
    scales_name = "#{name}.scales"

    with {:ok, blocks_metadata} <- fetcher.(blocks_name),
         {:ok, scales_metadata} <- fetcher.(scales_name) do
      blocks_shape = Map.fetch!(blocks_metadata, :shape)
      scales_shape = Map.fetch!(scales_metadata, :shape)

      cond do
        Tuple.delete_at(blocks_shape, tuple_size(blocks_shape) - 1) != scales_shape ->
          {:error, {:mxfp4_shape_mismatch, blocks_name, blocks_shape, scales_shape}}

        decoded_mxfp4_shape(blocks_shape) != expected_shape ->
          {:error,
           {:tensor_shape_mismatch, name, expected_shape, decoded_mxfp4_shape(blocks_shape)}}

        true ->
          :ok
      end
    else
      {:error, {:missing_tensor, missing}} when missing in [blocks_name, scales_name] ->
        {:error, {:missing_tensor, name}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp optional_metadata_present?(fetcher, names, expected_shape) do
    case validate_metadata_any(fetcher, names, expected_shape) do
      :ok -> {:ok, true}
      {:error, {:missing_tensor, _names}} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_metadata(fetcher, name, expected_shape) do
    with {:ok, metadata} <- fetcher.(name) do
      actual_shape = Map.fetch!(metadata, :shape)

      if actual_shape == expected_shape do
        :ok
      else
        {:error, {:tensor_shape_mismatch, name, expected_shape, actual_shape}}
      end
    end
  end

  defp fetch_tensor_any(fetcher, names, expected_shape) when is_list(names) do
    Enum.reduce_while(names, {:error, {:missing_tensor, names}}, fn name, _acc ->
      case fetch_tensor(fetcher, name, expected_shape) do
        {:ok, tensor} -> {:halt, {:ok, tensor}}
        {:error, {:missing_tensor, _missing}} -> {:cont, {:error, {:missing_tensor, names}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_optional_tensor_any(fetcher, names, expected_shape) do
    case fetch_tensor_any(fetcher, names, expected_shape) do
      {:ok, tensor} -> {:ok, tensor}
      {:error, {:missing_tensor, _names}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_qkv_weight(
         fetcher,
         prefix,
         hf_prefix,
         qkv_dim,
         hidden_size,
         attention_heads,
         kv_heads,
         head_dim
       ) do
    case fetch_tensor(fetcher, "#{prefix}.qkv.weight", {qkv_dim, hidden_size}) do
      {:ok, tensor} ->
        {:ok, tensor}

      {:error, {:missing_tensor, _name}} ->
        assemble_qkv(
          fetcher,
          hf_prefix,
          "weight",
          hidden_size,
          attention_heads,
          kv_heads,
          head_dim
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_qkv_bias(fetcher, prefix, hf_prefix, qkv_dim, attention_heads, kv_heads, head_dim) do
    case fetch_tensor(fetcher, "#{prefix}.qkv.bias", {qkv_dim}) do
      {:ok, tensor} ->
        {:ok, tensor}

      {:error, {:missing_tensor, _name}} ->
        assemble_qkv(fetcher, hf_prefix, "bias", nil, attention_heads, kv_heads, head_dim)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assemble_qkv(fetcher, hf_prefix, suffix, hidden_size, attention_heads, kv_heads, head_dim) do
    q_shape = projection_shape(suffix, attention_heads * head_dim, hidden_size)
    kv_shape = projection_shape(suffix, kv_heads * head_dim, hidden_size)

    with {:ok, q} <- fetch_tensor(fetcher, "#{hf_prefix}.q_proj.#{suffix}", q_shape),
         {:ok, k} <- fetch_tensor(fetcher, "#{hf_prefix}.k_proj.#{suffix}", kv_shape),
         {:ok, v} <- fetch_tensor(fetcher, "#{hf_prefix}.v_proj.#{suffix}", kv_shape) do
      {:ok, Nx.concatenate([q, k, v], axis: 0)}
    end
  end

  defp projection_shape("weight", width, hidden_size), do: {width, hidden_size}
  defp projection_shape("bias", width, _hidden_size), do: {width}

  defp decoded_mxfp4_shape(blocks_shape) do
    blocks_shape
    |> Tuple.to_list()
    |> then(fn dimensions ->
      {prefix, [groups, block_width]} = Enum.split(dimensions, length(dimensions) - 2)
      List.to_tuple(prefix ++ [groups * block_width * 2])
    end)
  end

  defp top_level_names,
    do: [
      "embedding.weight",
      "model.embed_tokens.weight",
      "norm.scale",
      "model.norm.weight",
      "unembedding.weight",
      "score.weight",
      "unembedding.bias",
      "score.bias"
    ]

  defp block_names(layer) do
    [
      "block.#{layer}.attn.norm.scale",
      "block.#{layer}.attn.sinks",
      "block.#{layer}.attn.qkv.weight",
      "block.#{layer}.attn.qkv.bias",
      "block.#{layer}.attn.out.weight",
      "block.#{layer}.attn.out.bias",
      "block.#{layer}.mlp.norm.scale",
      "block.#{layer}.mlp.gate.weight",
      "block.#{layer}.mlp.gate.bias",
      "block.#{layer}.mlp.mlp1_weight",
      "block.#{layer}.mlp.mlp1_bias",
      "block.#{layer}.mlp.mlp2_weight",
      "block.#{layer}.mlp.mlp2_bias"
    ]
  end

  defp embedding_shape(config), do: {field(config, :vocab_size), field(config, :hidden_size)}
  defp hidden_shape(config), do: {field(config, :hidden_size)}

  defp field(config, key), do: Map.fetch!(config, key)
end
