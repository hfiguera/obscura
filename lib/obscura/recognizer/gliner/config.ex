defmodule Obscura.Recognizer.GLiNER.Config do
  @moduledoc """
  Runtime configuration for the optional GLiNER adapter.
  """

  alias Obscura.Recognizer.GLiNER.LabelMap
  alias Obscura.Recognizer.GLiNER.ModelRegistry

  @enforce_keys [:model, :label_profile, :labels, :threshold, :max_width, :max_length]
  defstruct [
    :model,
    :label_profile,
    :labels,
    :threshold,
    :max_width,
    :max_length,
    :per_label_thresholds,
    :flat_ner,
    :multi_label,
    :class_token_index,
    :embed_ent_token,
    prompt_joiner: " ",
    span_mode: :span_level
  ]

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) do
    model = Keyword.get(opts, :model, :knowledgator_gliner_pii_base_v1)

    with {:ok, spec} <- ModelRegistry.fetch(model),
         {:ok, label_profile} <-
           opts
           |> Keyword.get(:label_profile, spec.default_label_profile)
           |> LabelMap.normalize_profile(),
         {:ok, labels} <- LabelMap.labels(label_profile) do
      {:ok,
       %__MODULE__{
         model: model,
         label_profile: label_profile,
         labels: labels,
         threshold: Keyword.get(opts, :threshold, 0.5),
         max_width: Keyword.get(opts, :max_width, spec.default_max_width),
         max_length: Keyword.get(opts, :max_length, spec.default_max_length),
         per_label_thresholds:
           normalize_thresholds(Keyword.get(opts, :per_label_thresholds, %{})),
         flat_ner: Keyword.get(opts, :flat_ner, true),
         multi_label: Keyword.get(opts, :multi_label, false),
         class_token_index: Keyword.get(opts, :class_token_index),
         embed_ent_token: Keyword.get(opts, :embed_ent_token, true),
         prompt_joiner: spec.prompt_joiner
       }}
    end
  end

  @spec from_model_config_file(String.t(), t()) :: {:ok, t()} | {:error, term()}
  def from_model_config_file(path, %__MODULE__{} = config) do
    with {:ok, binary} <- File.read(path),
         {:ok, decoded} <- Jason.decode(binary),
         {:ok, spec} <- ModelRegistry.fetch(config.model),
         :ok <- validate_model_config(decoded, spec) do
      {:ok,
       %{
         config
         | max_width: Map.get(decoded, "max_width", config.max_width),
           max_length: Map.get(decoded, "max_len", config.max_length),
           span_mode: normalize_span_mode(Map.get(decoded, "span_mode")),
           class_token_index: Map.get(decoded, "class_token_index"),
           embed_ent_token: Map.get(decoded, "embed_ent_token", true)
       }}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_gliner_config_json, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_model_config(config, spec) do
    cond do
      Map.get(config, "model_type") not in spec.accepted_model_types ->
        {:error, {:unsupported_gliner_model_type, Map.get(config, "model_type")}}

      Map.get(config, "span_mode") not in ["markerV0", "token_level"] ->
        {:error, {:unsupported_gliner_span_mode, Map.get(config, "span_mode")}}

      Map.get(config, "words_splitter_type") != "whitespace" ->
        {:error, {:unsupported_gliner_words_splitter, Map.get(config, "words_splitter_type")}}

      true ->
        :ok
    end
  end

  defp normalize_thresholds(thresholds) when is_map(thresholds) do
    Map.new(thresholds, fn {label, threshold} ->
      {label |> to_string() |> String.downcase(), threshold}
    end)
  end

  defp normalize_thresholds(_thresholds), do: %{}

  defp normalize_span_mode("token_level"), do: :token_level
  defp normalize_span_mode(_span_level), do: :span_level
end
