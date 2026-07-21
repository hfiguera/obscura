defmodule Obscura.PrivacyFilter.Checkpoint do
  @moduledoc """
  Validation helpers for local native privacy-filter checkpoints.

  This module is intentionally inference-free. By default it validates the
  checkpoint directory, config normalization, label space, safetensors header
  metadata, and parameter assembly without materializing large tensors. Pass
  `metadata_only: false` to also load tensors.
  """

  alias Obscura.PrivacyFilter.Checkpoint.Layout
  alias Obscura.PrivacyFilter.Config
  alias Obscura.PrivacyFilter.DTypes
  alias Obscura.PrivacyFilter.LabelInfo
  alias Obscura.PrivacyFilter.Model.Parameters
  alias Obscura.PrivacyFilter.Weights

  @spec validate(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def validate(path, opts \\ []) when is_binary(path) and is_list(opts) do
    with {:ok, layout} <- normalize_layout(opts),
         :ok <- Layout.validate(path, layout),
         :ok <- validate_path(path),
         {:ok, config} <- Config.from_file(Path.join(path, "config.json"), opts),
         {:ok, label_info} <- LabelInfo.build(config.ner_class_names),
         {:ok, weights} <- Weights.load(path),
         {:ok, dtypes_summary} <- validate_layout_dtypes(path, layout, weights),
         {:ok, params_summary} <- validate_parameters(weights, config, opts) do
      {:ok,
       %{
         checkpoint: path,
         layout: layout,
         mode:
           if(Keyword.get(opts, :metadata_only, true), do: :metadata_only, else: :materialized),
         config: config_summary(config),
         labels: %{
           token_label_count: length(config.ner_class_names),
           span_label_count: length(label_info.span_class_names),
           span_labels: label_info.span_class_names
         },
         tensors: %{
           count: map_size(weights.tensor_name_to_file),
           assembled_blocks: params_summary.assembled_blocks,
           has_classifier_bias: params_summary.has_classifier_bias
         },
         dtypes: dtypes_summary
       }}
    end
  end

  defp normalize_layout(opts) do
    opts
    |> Keyword.get(:layout, :native)
    |> Layout.normalize()
  end

  defp validate_layout_dtypes(path, :python_original, weights) do
    with {:ok, dtypes} <- DTypes.load(Path.join(path, "dtypes.json")),
         {:ok, summary} <- DTypes.validate_against_weights(dtypes, weights) do
      {:ok, Map.put(summary, :status, :validated)}
    end
  end

  defp validate_layout_dtypes(_path, :native, _weights), do: {:ok, %{status: :not_applicable}}

  defp validate_parameters(weights, config, opts) do
    if Keyword.get(opts, :metadata_only, true) do
      Parameters.validate_metadata(weights, config)
    else
      with {:ok, params} <- Parameters.load(weights, config) do
        {:ok,
         %{
           assembled_blocks: length(params.blocks),
           has_classifier_bias: not is_nil(Map.get(params, :unembedding_bias))
         }}
      end
    end
  end

  defp validate_path(path) do
    cond do
      not File.dir?(path) ->
        {:error, {:checkpoint_dir_not_found, path}}

      not File.exists?(Path.join(path, "config.json")) ->
        {:error, {:missing_checkpoint_config, Path.join(path, "config.json")}}

      true ->
        :ok
    end
  end

  defp config_summary(config) do
    %{
      model_type: config.model_type,
      encoding: config.encoding,
      num_hidden_layers: config.num_hidden_layers,
      num_experts: config.num_experts,
      experts_per_token: config.experts_per_token,
      vocab_size: config.vocab_size,
      num_labels: config.num_labels,
      hidden_size: config.hidden_size,
      intermediate_size: config.intermediate_size,
      num_attention_heads: config.num_attention_heads,
      num_key_value_heads: config.num_key_value_heads,
      head_dim: config.head_dim,
      bidirectional_left_context: config.bidirectional_left_context,
      bidirectional_right_context: config.bidirectional_right_context,
      sliding_window: config.sliding_window,
      param_dtype: config.param_dtype
    }
  end
end
