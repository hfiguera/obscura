defmodule Obscura.NLP.Engine.Bumblebee do
  @moduledoc """
  Optional analyzer-level NLP engine for Bumblebee token-classification serving.

  The engine attaches normalized model outputs to `Obscura.NLP.Artifacts` so
  recognizers can consume model evidence without each recognizer invoking model
  serving independently.
  """

  @behaviour Obscura.NLP.Engine

  alias Obscura.NLP.Artifacts
  alias Obscura.Recognizer.Batch
  alias Obscura.Recognizer.NER.BumblebeeOutput
  alias Obscura.Recognizer.NER.Serving

  @impl true
  def build_artifacts(text, opts) when is_binary(text) and is_list(opts) do
    with {:ok, serving} <- resolve_serving(opts),
         {:ok, outputs} <- predict(serving, text, opts),
         artifacts <- Artifacts.build(text) do
      Artifacts.put_model_outputs(artifacts, outputs)
    end
  end

  @impl true
  def build_many(texts, opts) when is_list(texts) and is_list(opts) do
    with {:ok, serving} <- resolve_serving(opts),
         {:ok, outputs_by_text} <- predict_many(serving, texts, opts) do
      put_outputs_by_text(texts, outputs_by_text)
    end
  end

  defp resolve_serving(opts) do
    case Keyword.get(opts, :serving) do
      nil ->
        if Keyword.get(opts, :build_serving, false),
          do: Serving.build(opts),
          else: {:error, :missing_ner_serving}

      serving ->
        {:ok, serving}
    end
  end

  defp predict(%Serving{} = serving, text, opts) do
    with {:ok, output} <- run_serving(serving.serving, text) do
      BumblebeeOutput.normalize(text, output, serving.model_spec, opts)
    end
  end

  defp predict(serving, text, opts) when is_pid(serving) or is_atom(serving) do
    with {:ok, output} <- run_serving(serving, text) do
      BumblebeeOutput.normalize(text, output, opts)
    end
  end

  defp predict(_serving, _text, _opts), do: {:error, :unsupported_ner_serving}

  defp predict_many(%Serving{} = serving, texts, opts) do
    Batch.run_many(texts, &predict(serving, &1, opts))
  end

  defp predict_many(serving, texts, opts) when is_pid(serving) or is_atom(serving) do
    with {:ok, outputs} <- batched_run_serving(serving, texts),
         true <- length(outputs) == length(texts) || :invalid_batch_model_output do
      normalize_outputs_by_text(texts, outputs, opts)
    else
      :invalid_batch_model_output -> {:error, :invalid_batch_model_output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp predict_many(_serving, _texts, _opts), do: {:error, :unsupported_ner_serving}

  defp put_outputs_by_text(texts, outputs_by_text) do
    texts
    |> Enum.zip(outputs_by_text)
    |> Enum.reduce_while({:ok, []}, fn {text, outputs}, {:ok, acc} ->
      case text |> Artifacts.build() |> Artifacts.put_model_outputs(outputs) do
        {:ok, artifacts} -> {:cont, {:ok, [artifacts | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_ok()
  end

  defp normalize_outputs_by_text(texts, outputs, opts) do
    texts
    |> Enum.zip(outputs)
    |> Enum.reduce_while({:ok, []}, fn {text, output}, {:ok, acc} ->
      case BumblebeeOutput.normalize(text, output, opts) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_ok()
  end

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok({:error, reason}), do: {:error, reason}

  defp run_serving(serving, text) do
    serving_module = Module.concat([Nx, "Serving"])

    if Code.ensure_loaded?(serving_module) do
      safe_serving_call(serving_module, :run, [serving, text])
    else
      {:error, {:missing_optional_dependency, :nx}}
    end
  end

  defp batched_run_serving(serving, texts) do
    serving_module = Module.concat([Nx, "Serving"])

    if Code.ensure_loaded?(serving_module) do
      safe_serving_call(serving_module, :batched_run, [serving, texts])
    else
      {:error, {:missing_optional_dependency, :nx}}
    end
  end

  defp safe_serving_call(module, function, args) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    {:ok, apply(module, function, args)}
  rescue
    _error -> {:error, :ner_serving_failed}
  catch
    :exit, _reason -> {:error, :ner_serving_unavailable}
  end
end
