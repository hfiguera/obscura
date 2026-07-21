defmodule Obscura.NLP.Engine do
  @moduledoc """
  Behaviour and dispatcher for analyzer-level NLP artifact engines.

  Presidio runs NLP once and passes shared artifacts to recognizers. Obscura's
  default engine remains dependency-light tokenization, while optional engines
  can attach model outputs for recognizers such as `Obscura.Recognizer.NER`.
  """

  alias Obscura.NLP.Artifacts

  @callback build_artifacts(String.t(), keyword()) :: {:ok, Artifacts.t()} | {:error, term()}
  @callback build_many([String.t()], keyword()) :: {:ok, [Artifacts.t()]} | {:error, term()}

  @optional_callbacks build_many: 2

  @doc """
  Builds artifacts for one text using explicit artifacts, a configured engine,
  or the dependency-light tokenizer.
  """
  @spec build_artifacts(String.t(), keyword()) :: {:ok, Artifacts.t()} | {:error, term()}
  def build_artifacts(text, opts) when is_binary(text) and is_list(opts) do
    case Keyword.get(opts, :nlp_artifacts) do
      nil -> dispatch_one(text, opts)
      %Artifacts{} = artifacts -> {:ok, artifacts}
      _other -> {:error, :invalid_nlp_artifacts}
    end
  end

  @doc """
  Builds artifacts for many texts while preserving input order.
  """
  @spec build_many([String.t()], keyword()) :: {:ok, [Artifacts.t()]} | {:error, term()}
  def build_many(texts, opts) when is_list(texts) and is_list(opts) do
    case Keyword.get(opts, :nlp_artifacts) do
      nil -> dispatch_many(texts, opts)
      artifacts when is_list(artifacts) -> validate_artifacts_many(texts, artifacts)
      _other -> {:error, :invalid_nlp_artifacts}
    end
  end

  defp dispatch_one(text, opts) do
    case engine_spec(opts) do
      nil -> {:ok, Artifacts.build(text)}
      {module, engine_opts} -> call_one(module, text, merge_engine_opts(opts, engine_opts))
    end
  end

  defp dispatch_many(texts, opts) do
    case engine_spec(opts) do
      nil ->
        {:ok, Enum.map(texts, &Artifacts.build/1)}

      {module, engine_opts} ->
        opts = merge_engine_opts(opts, engine_opts)

        if loaded_function?(module, :build_many, 2) do
          module.build_many(texts, opts)
        else
          dispatch_fallback_many(module, texts, opts)
        end
    end
  end

  defp dispatch_fallback_many(module, texts, opts) do
    texts
    |> Enum.reduce_while({:ok, []}, fn text, {:ok, acc} ->
      case call_one(module, text, opts) do
        {:ok, artifacts} -> {:cont, {:ok, [artifacts | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, artifacts} -> {:ok, Enum.reverse(artifacts)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp engine_spec(opts) do
    case Keyword.get(opts, :nlp_engine) do
      nil -> nil
      module when is_atom(module) -> {module, Keyword.get(opts, :nlp_engine_opts, [])}
      {module, engine_opts} -> {module, engine_opts}
    end
  end

  defp merge_engine_opts(opts, engine_opts) do
    opts
    |> Keyword.merge(Keyword.get(opts, :nlp_engine_opts, []))
    |> Keyword.merge(engine_opts)
  end

  defp call_one(module, text, opts) when is_atom(module) do
    if loaded_function?(module, :build_artifacts, 2) do
      module.build_artifacts(text, opts)
    else
      {:error, {:invalid_nlp_engine, module}}
    end
  end

  defp loaded_function?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp validate_artifacts_many(texts, artifacts) when length(texts) == length(artifacts) do
    if Enum.all?(artifacts, &match?(%Artifacts{}, &1)) do
      {:ok, artifacts}
    else
      {:error, :invalid_nlp_artifacts}
    end
  end

  defp validate_artifacts_many(_texts, _artifacts), do: {:error, :invalid_nlp_artifacts}
end
