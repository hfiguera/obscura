defmodule Obscura.Recognizer.NER.RealModelSmoke do
  @moduledoc """
  Opt-in smoke checks for real local NER model serving.
  """

  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.ModelSpec
  alias Obscura.Recognizer.NER.Serving
  alias Obscura.Telemetry
  alias Obscura.Vault.Memory

  @default_text "Rachel Green works at Ralph Lauren in New York City."
  @default_entities [:person, :organization, :location]

  @doc """
  Runs a tiny real-model smoke when model dependencies and assets are available.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    start = System.monotonic_time()

    result =
      with {:ok, serving} <- Serving.build(opts),
           text <- Keyword.get(opts, :text, @default_text),
           analyzer_opts <- analyzer_opts(serving, opts),
           {:ok, detections} <- Obscura.analyze(text, analyzer_opts),
           :ok <- require_detection_mix(detections, opts),
           {:ok, redacted} <- Obscura.redact(text, redaction_opts(serving, opts)),
           {:ok, vault} <- Memory.start_link(),
           {:ok, pseudonymized} <- pseudonymize(text, serving, vault, opts),
           {:ok, rehydrated} <- Obscura.rehydrate(pseudonymized.text, vault: vault) do
        {:ok,
         %{
           status: :ran,
           model: ModelSpec.metadata(serving.model_spec),
           result_count: length(detections),
           entities: detections |> Enum.map(& &1.entity) |> Enum.uniq() |> Enum.sort(),
           redacted_changed?: redacted.text != text,
           pseudonymized_changed?: pseudonymized.text != text,
           rehydrated_matches?: rehydrated == text,
           latency_ms: elapsed_ms(start)
         }}
      end

    emit(start, result, opts)
    result
  end

  @doc """
  Returns the deterministic sample used by the smoke task.
  """
  @spec default_text() :: String.t()
  def default_text, do: @default_text

  defp analyzer_opts(serving, opts) do
    [
      entities: Keyword.get(opts, :entities, @default_entities),
      recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
      conflict_strategy: :none,
      include_text: true,
      telemetry: Keyword.get(opts, :telemetry, true),
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 30_000)
    ]
  end

  defp redaction_opts(serving, opts) do
    analyzer_opts(serving, opts)
    |> Keyword.put(:operators, %{default: %{type: :replace, new_value: "[REDACTED]"}})
  end

  defp pseudonymize(text, serving, vault, opts) do
    Obscura.redact(text,
      entities: Keyword.get(opts, :entities, @default_entities),
      recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
      operators: %{default: %{type: :pseudonymize}},
      vault: vault,
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 30_000)
    )
  end

  defp require_detection_mix(detections, opts) do
    required = Keyword.get(opts, :required_entities, @default_entities)
    detected = Enum.map(detections, & &1.entity)

    if Enum.all?(required, &(&1 in detected)) do
      :ok
    else
      {:error, {:missing_required_real_model_entities, required -- detected}}
    end
  end

  defp emit(start, result, opts) do
    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :recognizer, :ner, :real_model, :analyze, :stop],
      %{duration: System.monotonic_time() - start},
      %{
        status: status(result),
        model_alias: Keyword.get(opts, :model, :dslim_bert_base_ner),
        input_count: 1,
        result_count: result_count(result)
      }
    )
  end

  defp status({:ok, _result}), do: :ok
  defp status({:error, _reason}), do: :error

  defp result_count({:ok, result}), do: result.result_count
  defp result_count({:error, _reason}), do: 0

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end
end
