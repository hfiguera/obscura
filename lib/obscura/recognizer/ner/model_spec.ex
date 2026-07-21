defmodule Obscura.Recognizer.NER.ModelSpec do
  @moduledoc """
  Normalized configuration for an optional local NER model.
  """

  @enforce_keys [
    :id,
    :model,
    :tokenizer,
    :task,
    :aggregation,
    :label_map,
    :entities,
    :license,
    :required?,
    :policy
  ]
  defstruct [
    :id,
    :model,
    :tokenizer,
    :task,
    :aggregation,
    :label_map,
    :entities,
    :license,
    :required?,
    :policy,
    :notes,
    offset_unit: :byte,
    status: :supported
  ]

  @type hf_ref :: {:hf, String.t()} | {:hf, String.t(), keyword()}

  @type t :: %__MODULE__{
          id: atom(),
          model: hf_ref(),
          tokenizer: hf_ref(),
          task: :token_classification,
          aggregation: atom(),
          label_map: atom(),
          entities: [atom()],
          license: String.t(),
          required?: boolean(),
          policy: keyword(),
          notes: String.t() | nil,
          offset_unit: :byte | :character,
          status: :supported | :experimental | :evaluation
        }

  @doc """
  Builds a model spec from registry data.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- fetch_atom(attrs, :id),
         {:ok, model} <- fetch_hf_ref(attrs, :model),
         {:ok, tokenizer} <- fetch_hf_ref(attrs, :tokenizer),
         {:ok, task} <- fetch_atom(attrs, :task),
         :ok <- require_task(task),
         {:ok, aggregation} <- fetch_atom(attrs, :aggregation),
         {:ok, label_map} <- fetch_atom(attrs, :label_map),
         {:ok, entities} <- fetch_entities(attrs),
         {:ok, license} <- fetch_binary(attrs, :license),
         {:ok, required?} <- fetch_boolean(attrs, :required?),
         {:ok, policy} <- fetch_policy(attrs) do
      {:ok,
       %__MODULE__{
         id: id,
         model: model,
         tokenizer: tokenizer,
         task: task,
         aggregation: aggregation,
         label_map: label_map,
         entities: entities,
         license: license,
         required?: required?,
         policy: policy,
         notes: Map.get(attrs, :notes),
         offset_unit: Map.get(attrs, :offset_unit, :byte),
         status: Map.get(attrs, :status, :supported)
       }}
    end
  end

  def new(_attrs), do: {:error, :invalid_model_spec}

  @doc """
  Returns a safe metadata map for telemetry and reports.
  """
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{} = spec) do
    %{
      model_alias: spec.id,
      model_id: hf_id(spec.model),
      tokenizer_id: hf_id(spec.tokenizer),
      model_license: spec.license,
      model_status: spec.status,
      model_policy: Map.new(spec.policy),
      entities: spec.entities
    }
  end

  @doc """
  Returns the Hugging Face identifier from a reference.
  """
  @spec hf_id(hf_ref()) :: String.t()
  def hf_id({:hf, id}), do: id
  def hf_id({:hf, id, _opts}), do: id

  defp fetch_atom(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_atom(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_model_spec_field, key, value}}
      :error -> {:error, {:missing_model_spec_field, key}}
    end
  end

  defp fetch_binary(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_model_spec_field, key, value}}
      :error -> {:error, {:missing_model_spec_field, key}}
    end
  end

  defp fetch_boolean(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_boolean(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_model_spec_field, key, value}}
      :error -> {:error, {:missing_model_spec_field, key}}
    end
  end

  defp fetch_hf_ref(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, {:hf, id} = ref} when is_binary(id) -> {:ok, ref}
      {:ok, {:hf, id, opts} = ref} when is_binary(id) and is_list(opts) -> {:ok, ref}
      {:ok, value} -> {:error, {:invalid_model_spec_field, key, value}}
      :error -> {:error, {:missing_model_spec_field, key}}
    end
  end

  defp fetch_entities(attrs) do
    case Map.fetch(attrs, :entities) do
      {:ok, entities} when is_list(entities) ->
        validate_entities(entities)

      {:ok, value} ->
        {:error, {:invalid_model_spec_field, :entities, value}}

      :error ->
        {:error, {:missing_model_spec_field, :entities}}
    end
  end

  defp fetch_policy(attrs) do
    case Map.get(attrs, :policy, []) do
      policy when is_list(policy) ->
        {:ok, policy}

      policy when is_map(policy) ->
        {:ok, Map.to_list(policy)}

      policy ->
        {:error, {:invalid_model_spec_field, :policy, policy}}
    end
  end

  defp validate_entities(entities) do
    if entities != [] and Enum.all?(entities, &is_atom/1) do
      {:ok, entities}
    else
      {:error, {:invalid_model_spec_field, :entities, entities}}
    end
  end

  defp require_task(:token_classification), do: :ok
  defp require_task(task), do: {:error, {:unsupported_model_task, task}}
end
