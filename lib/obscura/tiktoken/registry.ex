defmodule Obscura.Tiktoken.Registry do
  @moduledoc false

  alias Obscura.Tiktoken.OpenAI

  @constructors %{
    "gpt2" => {OpenAI, :gpt2},
    "r50k_base" => {OpenAI, :r50k_base},
    "p50k_base" => {OpenAI, :p50k_base},
    "p50k_edit" => {OpenAI, :p50k_edit},
    "cl100k_base" => {OpenAI, :cl100k_base},
    "o200k_base" => {OpenAI, :o200k_base},
    "o200k_harmony" => {OpenAI, :o200k_harmony}
  }

  @model_prefix_to_encoding %{
    "o1-" => "o200k_base",
    "o3-" => "o200k_base",
    "o4-mini-" => "o200k_base",
    "gpt-5-" => "o200k_base",
    "gpt-4.5-" => "o200k_base",
    "gpt-4.1-" => "o200k_base",
    "chatgpt-4o-" => "o200k_base",
    "gpt-4o-" => "o200k_base",
    "gpt-4-" => "cl100k_base",
    "gpt-3.5-turbo-" => "cl100k_base",
    "gpt-35-turbo-" => "cl100k_base",
    "gpt-oss-" => "o200k_harmony",
    "ft:gpt-4o" => "o200k_base",
    "ft:gpt-4" => "cl100k_base",
    "ft:gpt-3.5-turbo" => "cl100k_base",
    "ft:davinci-002" => "cl100k_base",
    "ft:babbage-002" => "cl100k_base"
  }

  @model_to_encoding %{
    "o1" => "o200k_base",
    "o3" => "o200k_base",
    "o4-mini" => "o200k_base",
    "gpt-5" => "o200k_base",
    "gpt-4.1" => "o200k_base",
    "gpt-4o" => "o200k_base",
    "gpt-4" => "cl100k_base",
    "gpt-3.5-turbo" => "cl100k_base",
    "gpt-3.5" => "cl100k_base",
    "gpt-35-turbo" => "cl100k_base",
    "davinci-002" => "cl100k_base",
    "babbage-002" => "cl100k_base",
    "text-embedding-ada-002" => "cl100k_base",
    "text-embedding-3-small" => "cl100k_base",
    "text-embedding-3-large" => "cl100k_base",
    "text-davinci-003" => "p50k_base",
    "text-davinci-002" => "p50k_base",
    "text-davinci-001" => "r50k_base",
    "text-curie-001" => "r50k_base",
    "text-babbage-001" => "r50k_base",
    "text-ada-001" => "r50k_base",
    "davinci" => "r50k_base",
    "curie" => "r50k_base",
    "babbage" => "r50k_base",
    "ada" => "r50k_base",
    "code-davinci-002" => "p50k_base",
    "code-davinci-001" => "p50k_base",
    "code-cushman-002" => "p50k_base",
    "code-cushman-001" => "p50k_base",
    "davinci-codex" => "p50k_base",
    "cushman-codex" => "p50k_base",
    "text-davinci-edit-001" => "p50k_edit",
    "code-davinci-edit-001" => "p50k_edit",
    "gpt2" => "gpt2",
    "gpt-2" => "gpt2"
  }

  @spec get_encoding(String.t() | atom()) ::
          {:ok, Obscura.Tiktoken.Encoding.t()} | {:error, term()}
  def get_encoding(name) when is_atom(name), do: name |> Atom.to_string() |> get_encoding()

  def get_encoding(name) when is_binary(name) do
    normalized = String.trim(name)
    cache_key = {__MODULE__, normalized}

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        with {:ok, {module, function}} <- fetch_constructor(normalized),
             {:ok, encoding} <- apply(module, function, []) do
          :persistent_term.put(cache_key, encoding)
          {:ok, encoding}
        end

      encoding ->
        {:ok, encoding}
    end
  end

  @spec list_encoding_names() :: [String.t()]
  def list_encoding_names do
    @constructors
    |> Map.keys()
    |> Enum.sort()
  end

  @spec encoding_name_for_model(String.t()) :: {:ok, String.t()} | {:error, term()}
  def encoding_name_for_model(model_name) when is_binary(model_name) do
    cond do
      Map.has_key?(@model_to_encoding, model_name) ->
        {:ok, Map.fetch!(@model_to_encoding, model_name)}

      prefix_encoding = prefix_encoding(model_name) ->
        {:ok, prefix_encoding}

      true ->
        {:error, {:unknown_model, model_name}}
    end
  end

  defp fetch_constructor(name) do
    case Map.fetch(@constructors, name) do
      {:ok, constructor} -> {:ok, constructor}
      :error -> {:error, :unknown_encoding}
    end
  end

  defp prefix_encoding(model_name) do
    @model_prefix_to_encoding
    |> Enum.find_value(fn {prefix, encoding} ->
      if String.starts_with?(model_name, prefix), do: encoding
    end)
  end
end
