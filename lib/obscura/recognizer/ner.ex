defmodule Obscura.Recognizer.NER do
  @moduledoc """
  Explicit NER recognizer for open-class entities.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Analyzer.ModelOutput
  alias Obscura.Internal.StageDiagnostics
  alias Obscura.NLP.Artifacts
  alias Obscura.Recognizer.Batch
  alias Obscura.Recognizer.NER.BumblebeeOutput
  alias Obscura.Recognizer.NER.Chunker
  alias Obscura.Recognizer.NER.Config
  alias Obscura.Recognizer.NER.FakeServing
  alias Obscura.Recognizer.NER.LabelMap
  alias Obscura.Recognizer.NER.Serving, as: NERServing
  alias Obscura.Telemetry

  @impl true
  def name, do: :ner

  @impl true
  def supported_entities, do: LabelMap.known_entities()

  @doc """
  Returns optional PHI-like entities supported by the label map.
  """
  @spec phi_entities() :: [atom()]
  def phi_entities, do: [:medical_condition, :medication, :patient_id, :provider]

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    start = System.monotonic_time()

    result =
      with {:ok, config} <- Config.new(opts),
           {:ok, outputs} <-
             StageDiagnostics.measure(:model_serving, fn -> resolve_outputs(text, config) end),
           {:ok, results} <-
             StageDiagnostics.measure(:span_reconstruction_entity_mapping, fn ->
               ModelOutput.normalize(text, outputs, config)
             end) do
        {:ok, filter_entities(results, Keyword.get(config, :entities, supported_entities()))}
      end

    emit(:analyze, start, result, opts)
    result
  end

  @doc """
  Analyzes many texts with a batch-capable serving when available.
  """
  @spec analyze_many([String.t()], keyword()) ::
          {:ok, [[Obscura.Analyzer.Result.t()]]} | {:error, term()}
  @impl true
  def analyze_many(texts, opts) when is_list(texts) and is_list(opts) do
    start = System.monotonic_time()

    result =
      with {:ok, config} <- Config.new(opts),
           {:ok, serving} <- resolve_serving(config),
           {:ok, outputs_by_text} <- predict_many(serving, texts, config),
           {:ok, results_by_text} <- normalize_many(texts, outputs_by_text, config) do
        entities = Keyword.get(config, :entities, supported_entities())
        {:ok, Enum.map(results_by_text, &filter_entities(&1, entities))}
      end

    emit(:analyze_many, start, result, opts)
    result
  end

  defp resolve_outputs(text, config) do
    case artifact_model_outputs(config) do
      {:ok, outputs} ->
        {:ok, outputs}

      :none ->
        with {:ok, serving} <- resolve_serving(config) do
          predict(serving, text, config)
        end
    end
  end

  defp artifact_model_outputs(config) do
    case Keyword.get(config, :nlp_artifacts) do
      %Artifacts{text: text, model_outputs: outputs, model_outputs_ready: true}
      when is_list(outputs) ->
        {:ok, ensure_text_metadata(outputs, text)}

      _other ->
        :none
    end
  end

  defp ensure_text_metadata(outputs, text) do
    Enum.map(outputs, fn output ->
      Map.put_new(output, :artifact_text, text)
    end)
  end

  defp resolve_serving(opts) do
    Keyword.get(opts, :serving)
    |> case do
      nil -> {:error, :missing_ner_serving}
      serving -> {:ok, serving}
    end
  end

  defp predict(%FakeServing{} = serving, text, opts), do: FakeServing.predict(serving, text, opts)

  defp predict(%NERServing{} = serving, text, opts) do
    record_ner_input_shape(serving, text)
    record_model_sequence_length(serving)
    StageDiagnostics.metadata(:window_count, 1)
    StageDiagnostics.unavailable(:privacy_filter_attention, :not_privacy_filter_profile)
    StageDiagnostics.unavailable(:privacy_filter_moe, :not_privacy_filter_profile)

    case Keyword.get(opts, :model_chunking, :none) do
      :none -> predict_full_text(serving, text, opts)
      :character -> predict_chunked(serving, text, opts)
    end
  end

  defp predict(serving, text, opts) when is_pid(serving) or is_atom(serving) do
    call_batched_serving(serving, [text], opts)
    |> case do
      {:ok, [outputs]} -> {:ok, outputs}
      {:ok, outputs} when is_list(outputs) -> {:ok, outputs}
      {:error, reason} -> {:error, reason}
    end
  end

  defp predict(_serving, _text, _opts), do: {:error, :unsupported_ner_serving}

  defp record_model_sequence_length(%NERServing{sequence_length: sequence_length})
       when is_integer(sequence_length) and sequence_length > 0,
       do: StageDiagnostics.metadata(:model_sequence_length, sequence_length)

  defp record_model_sequence_length(%NERServing{}),
    do: StageDiagnostics.unavailable(:model_sequence_length, :compile_shape_unavailable)

  defp record_ner_input_shape(%NERServing{tokenizer: nil}, _text) do
    StageDiagnostics.unavailable(:token_count, :tokenizer_not_retained)
  end

  defp record_ner_input_shape(%NERServing{tokenizer: tokenizer}, text) do
    if StageDiagnostics.enabled?() do
      StageDiagnostics.measure(
        :diagnostic_token_count_probe,
        fn -> probe_token_count(tokenizer, text) end
      )
    end
  rescue
    _error -> StageDiagnostics.unavailable(:token_count, :tokenizer_probe_failed)
  end

  defp probe_token_count(tokenizer, text) do
    inputs =
      Nx.with_default_backend(Nx.BinaryBackend, fn ->
        Bumblebee.apply_tokenizer(tokenizer, [text])
      end)

    case Map.get(inputs, "input_ids") do
      %Nx.Tensor{} = tensor -> StageDiagnostics.metadata(:token_count, Nx.size(tensor))
      _other -> StageDiagnostics.unavailable(:token_count, :tokenizer_output_unavailable)
    end
  end

  defp predict_full_text(%NERServing{} = serving, text, opts) do
    case call_serving(serving.serving, text, opts) do
      {:ok, output} -> BumblebeeOutput.normalize(text, output, serving.model_spec, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp predict_chunked(%NERServing{} = serving, text, opts) do
    with {:ok, chunks} <- Chunker.chunks(text, opts),
         {:ok, outputs} <- predict_chunks(serving, chunks, opts) do
      {:ok, Chunker.dedupe_outputs(outputs)}
    end
  end

  defp predict_chunks(serving, chunks, opts) do
    chunks
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      reduce_chunk_prediction(predict_chunk(serving, chunk, opts), acc)
    end)
    |> case do
      {:ok, outputs} -> {:ok, Enum.reverse(outputs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp predict_chunk(serving, chunk, opts) do
    with {:ok, output} <- call_serving(serving.serving, chunk.text, opts),
         {:ok, chunk_outputs} <-
           BumblebeeOutput.normalize(chunk.text, output, serving.model_spec, opts) do
      {:ok, Chunker.absolute_outputs(chunk, chunk_outputs, opts)}
    end
  end

  defp reduce_chunk_prediction({:ok, outputs}, acc), do: {:cont, {:ok, outputs ++ acc}}
  defp reduce_chunk_prediction({:error, reason}, _acc), do: {:halt, {:error, reason}}

  defp predict_many(%FakeServing{} = serving, texts, opts),
    do: FakeServing.predict_many(serving, texts, opts)

  defp predict_many(%NERServing{} = serving, texts, opts) do
    Batch.run_many(texts, &predict(serving, &1, opts))
  end

  defp predict_many(serving, texts, opts) when is_pid(serving) or is_atom(serving),
    do: call_batched_serving(serving, texts, opts)

  defp predict_many(_serving, _texts, _opts), do: {:error, :unsupported_ner_serving}

  defp call_serving(serving, text, _opts) do
    module = Module.concat([Nx, "Serving"])

    if Code.ensure_loaded?(module) do
      try do
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        {:ok, apply(module, :run, [serving, text])}
      rescue
        error -> {:error, {:ner_serving_failed, error.__struct__}}
      catch
        :exit, _reason -> {:error, {:ner_serving_unavailable, :exit}}
      end
    else
      {:error, {:missing_optional_dependency, :nx}}
    end
  end

  defp call_batched_serving(serving, texts, _opts) do
    module = Module.concat([Nx, "Serving"])

    if Code.ensure_loaded?(module) do
      try do
        {
          :ok,
          # credo:disable-for-next-line Credo.Check.Refactor.Apply
          apply(module, :batched_run, [serving, texts])
        }
      rescue
        error -> {:error, {:ner_serving_failed, error.__struct__}}
      catch
        :exit, _reason -> {:error, {:ner_serving_unavailable, :exit}}
      end
    else
      {:error, {:missing_optional_dependency, :nx}}
    end
  end

  defp normalize_many(texts, outputs_by_text, opts)
       when length(texts) == length(outputs_by_text) do
    texts
    |> Enum.zip(outputs_by_text)
    |> Enum.reduce_while({:ok, []}, fn {text, outputs}, {:ok, acc} ->
      case ModelOutput.normalize(text, outputs, opts) do
        {:ok, results} -> {:cont, {:ok, [results | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_many(_texts, _outputs_by_text, _opts), do: {:error, :invalid_batch_model_output}

  defp filter_entities(results, entities) do
    known_entities = supported_entities() ++ phi_entities()

    requested =
      Enum.filter(entities, &(&1 in known_entities))

    Enum.filter(results, &(&1.entity in requested))
  end

  defp emit(kind, start, result, opts) do
    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :recognizer, :ner, kind, :stop],
      %{duration: System.monotonic_time() - start},
      %{
        status: status(result),
        recognizer: :ner,
        backend: backend(Keyword.get(opts, :serving)),
        result_count: result_count(result),
        entities: Keyword.get(opts, :entities, LabelMap.known_entities()),
        profile: Keyword.get(opts, :profile, :regex_only)
      }
    )
  end

  defp status({:ok, _results}), do: :ok
  defp status({:error, _reason}), do: :error

  defp result_count({:ok, results}) when is_list(results) do
    if Enum.all?(results, &is_list/1),
      do: results |> List.flatten() |> length(),
      else: length(results)
  end

  defp result_count({:error, _reason}), do: 0

  defp backend(%FakeServing{}), do: :fake
  defp backend(nil), do: :none
  defp backend(_serving), do: :serving
end
