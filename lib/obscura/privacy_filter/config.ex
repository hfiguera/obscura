defmodule Obscura.PrivacyFilter.Config do
  @moduledoc """
  Validated configuration for native privacy-filter checkpoints.
  """

  alias Obscura.PrivacyFilter.LabelSpace

  @supported_model_types MapSet.new(["privacy_filter", "openai_privacy_filter"])
  @required_keys [
    "model_type",
    "encoding",
    "num_hidden_layers",
    "num_experts",
    "experts_per_token",
    "vocab_size",
    "num_labels",
    "hidden_size",
    "intermediate_size",
    "head_dim",
    "num_attention_heads",
    "num_key_value_heads",
    "sliding_window",
    "bidirectional_context",
    "bidirectional_left_context",
    "bidirectional_right_context",
    "initial_context_length",
    "rope_theta",
    "rope_scaling_factor",
    "rope_ntk_alpha",
    "rope_ntk_beta",
    "param_dtype"
  ]

  @enforce_keys [
    :model_type,
    :encoding,
    :num_hidden_layers,
    :num_experts,
    :experts_per_token,
    :vocab_size,
    :num_labels,
    :hidden_size,
    :intermediate_size,
    :head_dim,
    :num_attention_heads,
    :num_key_value_heads,
    :sliding_window,
    :bidirectional_context,
    :bidirectional_left_context,
    :bidirectional_right_context,
    :initial_context_length,
    :default_n_ctx,
    :max_position_embeddings,
    :rope_theta,
    :rope_scaling_factor,
    :rope_ntk_alpha,
    :rope_ntk_beta,
    :param_dtype,
    :category_version,
    :span_class_names,
    :ner_class_names
  ]
  defstruct [
    :model_type,
    :encoding,
    :num_hidden_layers,
    :num_experts,
    :experts_per_token,
    :vocab_size,
    :num_labels,
    :hidden_size,
    :intermediate_size,
    :head_dim,
    :num_attention_heads,
    :num_key_value_heads,
    :sliding_window,
    :bidirectional_context,
    :bidirectional_left_context,
    :bidirectional_right_context,
    :initial_context_length,
    :default_n_ctx,
    :max_position_embeddings,
    :rope_theta,
    :rope_scaling_factor,
    :rope_ntk_alpha,
    :rope_ntk_beta,
    :param_dtype,
    :category_version,
    :span_class_names,
    :ner_class_names,
    swiglu_limit: 7.0,
    packed_geglu: false,
    torch_ops_batch: 32
  ]

  @type t :: %__MODULE__{}

  @spec from_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_file(path, opts \\ []) when is_binary(path) and is_list(opts) do
    with {:ok, contents} <- File.read(path),
         {:ok, payload} <- Jason.decode(contents) do
      from_map(payload, Keyword.put(opts, :context, path))
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_json, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec from_map(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_map(payload, opts \\ []) when is_map(payload) do
    context = Keyword.get(opts, :context, "privacy-filter config")
    payload = normalize_payload(payload, opts)

    with :ok <- require_keys(payload, context),
         {:ok, model_type} <- string_field(payload, "model_type", context),
         :ok <- validate_model_type(model_type),
         {:ok, encoding} <- string_field(payload, "encoding", context),
         {:ok, bidirectional_context} <- bool_field(payload, "bidirectional_context", context),
         {:ok, num_hidden_layers} <- positive_int(payload, "num_hidden_layers", context),
         {:ok, num_experts} <- positive_int(payload, "num_experts", context),
         {:ok, experts_per_token} <- positive_int(payload, "experts_per_token", context),
         {:ok, vocab_size} <- positive_int(payload, "vocab_size", context),
         {:ok, num_labels} <- positive_int(payload, "num_labels", context),
         {:ok, hidden_size} <- positive_int(payload, "hidden_size", context),
         {:ok, intermediate_size} <- positive_int(payload, "intermediate_size", context),
         {:ok, head_dim} <- positive_int(payload, "head_dim", context),
         {:ok, num_attention_heads} <- positive_int(payload, "num_attention_heads", context),
         {:ok, num_key_value_heads} <- positive_int(payload, "num_key_value_heads", context),
         {:ok, sliding_window} <- nonnegative_int(payload, "sliding_window", context),
         {:ok, left_context} <- nonnegative_int(payload, "bidirectional_left_context", context),
         {:ok, right_context} <- nonnegative_int(payload, "bidirectional_right_context", context),
         {:ok, initial_context_length} <- positive_int(payload, "initial_context_length", context),
         {:ok, default_n_ctx} <- optional_positive_int(payload, "default_n_ctx", context),
         {:ok, max_position_embeddings} <-
           optional_positive_int(payload, "max_position_embeddings", context),
         {:ok, rope_theta} <- positive_numeric(payload, "rope_theta", context),
         {:ok, rope_scaling_factor} <- positive_numeric(payload, "rope_scaling_factor", context),
         {:ok, rope_ntk_alpha} <- positive_numeric(payload, "rope_ntk_alpha", context),
         {:ok, rope_ntk_beta} <- positive_numeric(payload, "rope_ntk_beta", context),
         {:ok, swiglu_limit} <- optional_positive_numeric(payload, "swiglu_limit", 7.0, context),
         {:ok, packed_geglu} <- optional_bool(payload, "packed_geglu", false, context),
         {:ok, torch_ops_batch} <- optional_positive_int(payload, "torch_ops_batch", 32, context),
         {:ok, param_dtype} <- string_field(payload, "param_dtype", context),
         :ok <- validate_param_dtype(param_dtype),
         :ok <- validate_experts_per_token(experts_per_token, num_experts),
         :ok <- validate_even_head_dim(head_dim),
         :ok <- validate_grouped_query_heads(num_attention_heads, num_key_value_heads),
         :ok <-
           validate_bidirectional(
             bidirectional_context,
             left_context,
             right_context,
             sliding_window
           ),
         {:ok, category_version, span_class_names, ner_class_names} <-
           LabelSpace.resolve_from_config(payload, context: context),
         :ok <- validate_num_labels(num_labels, ner_class_names) do
      {:ok,
       %__MODULE__{
         model_type: normalize_model_type(model_type),
         encoding: encoding,
         num_hidden_layers: num_hidden_layers,
         num_experts: num_experts,
         experts_per_token: experts_per_token,
         vocab_size: vocab_size,
         num_labels: num_labels,
         hidden_size: hidden_size,
         intermediate_size: intermediate_size,
         swiglu_limit: swiglu_limit,
         packed_geglu: packed_geglu,
         head_dim: head_dim,
         num_attention_heads: num_attention_heads,
         num_key_value_heads: num_key_value_heads,
         sliding_window: sliding_window,
         bidirectional_context: bidirectional_context,
         bidirectional_left_context: left_context,
         bidirectional_right_context: right_context,
         initial_context_length: initial_context_length,
         default_n_ctx: default_n_ctx,
         max_position_embeddings: max_position_embeddings,
         rope_theta: rope_theta,
         rope_scaling_factor: rope_scaling_factor,
         rope_ntk_alpha: rope_ntk_alpha,
         rope_ntk_beta: rope_ntk_beta,
         torch_ops_batch: torch_ops_batch,
         param_dtype: normalize_param_dtype(param_dtype),
         category_version: category_version,
         span_class_names: span_class_names,
         ner_class_names: ner_class_names
       }}
    end
  end

  defp normalize_payload(payload, opts) do
    payload
    |> normalize_hf_privacy_filter_encoding(opts)
    |> normalize_hf_privacy_filter_counts()
    |> normalize_hf_privacy_filter_rope()
    |> normalize_hf_privacy_filter_bidirectional_context()
    |> normalize_hf_privacy_filter_labels()
    |> normalize_hf_privacy_filter_dtype()
  end

  defp normalize_hf_privacy_filter_encoding(payload, opts) do
    cond do
      Map.has_key?(payload, "encoding") ->
        payload

      is_binary(Keyword.get(opts, :encoding)) ->
        Map.put(payload, "encoding", Keyword.fetch!(opts, :encoding))

      Map.get(payload, "model_type") == "openai_privacy_filter" and
          Map.get(payload, "pad_token_id") == 199_999 ->
        # Hugging Face privacy-filter configs omit the original OpenAI
        # runtime's `encoding` field. The published checkpoint uses the
        # o200k tokenizer family and exposes the o200k EOT/pad token.
        Map.put(payload, "encoding", "o200k_base")

      true ->
        payload
    end
  end

  defp normalize_hf_privacy_filter_counts(payload) do
    payload
    |> put_new_from("num_experts", "num_local_experts")
    |> put_new_from("experts_per_token", "num_experts_per_tok")
    |> put_new_lazy("num_labels", fn ->
      case Map.get(payload, "id2label") do
        id2label when is_map(id2label) -> map_size(id2label)
        _other -> nil
      end
    end)
  end

  defp normalize_hf_privacy_filter_rope(%{"rope_parameters" => rope} = payload)
       when is_map(rope) do
    payload
    |> Map.put_new("rope_theta", Map.get(rope, "rope_theta"))
    |> Map.put_new("rope_scaling_factor", Map.get(rope, "factor"))
    |> Map.put_new("rope_ntk_alpha", Map.get(rope, "beta_slow"))
    |> Map.put_new("rope_ntk_beta", Map.get(rope, "beta_fast"))
    |> Map.put_new("initial_context_length", Map.get(rope, "original_max_position_embeddings"))
  end

  defp normalize_hf_privacy_filter_rope(payload), do: payload

  defp normalize_hf_privacy_filter_bidirectional_context(payload) do
    if Map.get(payload, "model_type") == "openai_privacy_filter" and
         not Map.has_key?(payload, "bidirectional_context") and
         is_integer(Map.get(payload, "sliding_window")) do
      context = Map.fetch!(payload, "sliding_window")

      payload
      |> Map.put("bidirectional_context", true)
      |> Map.put("bidirectional_left_context", context)
      |> Map.put("bidirectional_right_context", context)
      |> Map.put("sliding_window", context * 2 + 1)
    else
      payload
    end
  end

  defp normalize_hf_privacy_filter_labels(payload) do
    if Map.has_key?(payload, "ner_class_names") do
      payload
    else
      put_hf_labels(payload, Map.get(payload, "id2label"))
    end
  end

  defp put_hf_labels(payload, id2label) when is_map(id2label) do
    labels =
      id2label
      |> Enum.sort_by(fn {index, _label} -> parse_index(index) end)
      |> Enum.map(fn {_index, label} -> label end)

    Map.put(payload, "ner_class_names", labels)
  end

  defp put_hf_labels(payload, _id2label), do: payload

  defp normalize_hf_privacy_filter_dtype(payload) do
    put_new_from(payload, "param_dtype", "dtype")
  end

  defp put_new_from(payload, target, source) do
    case Map.fetch(payload, target) do
      {:ok, _value} ->
        payload

      :error ->
        case Map.get(payload, source) do
          nil -> payload
          value -> Map.put(payload, target, value)
        end
    end
  end

  defp put_new_lazy(payload, target, fun) do
    case Map.fetch(payload, target) do
      {:ok, _value} ->
        payload

      :error ->
        case fun.() do
          nil -> payload
          value -> Map.put(payload, target, value)
        end
    end
  end

  defp parse_index(index) when is_integer(index), do: index
  defp parse_index(index) when is_binary(index), do: String.to_integer(index)

  defp require_keys(payload, context) do
    missing = Enum.reject(@required_keys, &Map.has_key?(payload, &1))

    if missing == [] do
      :ok
    else
      {:error, {:missing_config_keys, context, missing}}
    end
  end

  defp validate_model_type(model_type) do
    if MapSet.member?(@supported_model_types, model_type) do
      :ok
    else
      {:error, {:unsupported_privacy_filter_model_type, model_type}}
    end
  end

  defp normalize_model_type("openai_privacy_filter"), do: "privacy_filter"
  defp normalize_model_type(model_type), do: model_type

  defp validate_param_dtype(value) do
    validate_param_dtype(value, normalize_param_dtype(value))
  end

  defp validate_param_dtype(_value, normalized) when normalized in ["bfloat16", "float32"],
    do: :ok

  defp validate_param_dtype(value, _normalized),
    do: {:error, {:unsupported_param_dtype, value}}

  defp validate_experts_per_token(experts_per_token, num_experts)
       when experts_per_token <= num_experts,
       do: :ok

  defp validate_experts_per_token(experts_per_token, num_experts),
    do: {:error, {:invalid_experts_per_token, experts_per_token, num_experts}}

  defp validate_grouped_query_heads(num_attention_heads, num_key_value_heads) do
    if rem(num_attention_heads, num_key_value_heads) == 0 do
      :ok
    else
      {:error, {:invalid_grouped_query_heads, num_attention_heads, num_key_value_heads}}
    end
  end

  defp validate_even_head_dim(head_dim) do
    if rem(head_dim, 2) == 0 do
      :ok
    else
      {:error, {:invalid_head_dim, head_dim}}
    end
  end

  defp validate_num_labels(num_labels, ner_class_names) do
    actual = length(ner_class_names)

    if num_labels == actual do
      :ok
    else
      {:error, {:invalid_num_labels, num_labels, actual}}
    end
  end

  defp normalize_param_dtype(value) do
    case String.downcase(value) do
      "bf16" -> "bfloat16"
      "bfloat16" -> "bfloat16"
      "fp32" -> "float32"
      "float32" -> "float32"
      other -> other
    end
  end

  defp validate_bidirectional(true, left_context, right_context, sliding_window) do
    expected = left_context + right_context + 1

    if sliding_window == expected do
      :ok
    else
      {:error, {:invalid_bidirectional_window, sliding_window, expected}}
    end
  end

  defp validate_bidirectional(false, _left_context, _right_context, _sliding_window) do
    {:error, :privacy_filter_requires_bidirectional_context}
  end

  defp string_field(payload, key, context) do
    case Map.get(payload, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, {:invalid_config_string, context, key, value}}
    end
  end

  defp bool_field(payload, key, context) do
    case Map.get(payload, key) do
      value when is_boolean(value) -> {:ok, value}
      value -> {:error, {:invalid_config_bool, context, key, value}}
    end
  end

  defp positive_int(payload, key, context) do
    case Map.get(payload, key) do
      value when is_integer(value) and not is_boolean(value) and value > 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_config_positive_integer, context, key, value}}
    end
  end

  defp nonnegative_int(payload, key, context) do
    case Map.get(payload, key) do
      value when is_integer(value) and not is_boolean(value) and value >= 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_config_nonnegative_integer, context, key, value}}
    end
  end

  defp optional_positive_int(payload, key, context) do
    case Map.get(payload, key) do
      nil ->
        {:ok, nil}

      value when is_integer(value) and not is_boolean(value) and value > 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_config_positive_integer, context, key, value}}
    end
  end

  defp optional_positive_int(payload, key, default, context) do
    case Map.get(payload, key, default) do
      value when is_integer(value) and not is_boolean(value) and value > 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_config_positive_integer, context, key, value}}
    end
  end

  defp positive_numeric(payload, key, context) do
    case Map.get(payload, key) do
      value when is_number(value) and not is_boolean(value) and value > 0 ->
        {:ok, :erlang.float(value)}

      value ->
        {:error, {:invalid_config_positive_number, context, key, value}}
    end
  end

  defp optional_positive_numeric(payload, key, default, context) do
    case Map.get(payload, key, default) do
      value when is_number(value) and not is_boolean(value) and value > 0 ->
        {:ok, :erlang.float(value)}

      value ->
        {:error, {:invalid_config_positive_number, context, key, value}}
    end
  end

  defp optional_bool(payload, key, default, context) do
    case Map.get(payload, key, default) do
      value when is_boolean(value) ->
        {:ok, value}

      value ->
        {:error, {:invalid_config_bool, context, key, value}}
    end
  end
end
