defmodule Obscura.Recognizer.GLiNER do
  @moduledoc """
  Optional GLiNER recognizer facade.
  """

  alias Obscura.Analyzer.Explanation
  alias Obscura.Analyzer.Result
  alias Obscura.Recognizer.GLiNER.LabelMap
  alias Obscura.Recognizer.GLiNER.Native
  alias Obscura.Recognizer.GLiNER.Ortex

  @doc """
  Recognizer name.
  """
  @spec name() :: atom()
  def name, do: :gliner

  @doc """
  Supported entities for the default GLiNER label profile.
  """
  @spec supported_entities() :: [atom()]
  def supported_entities, do: LabelMap.supported_entities(:hybrid_core)

  @doc """
  Analyzes text with a GLiNER serving.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def analyze(text, opts \\ []) when is_binary(text) do
    with {:ok, serving} <- serving(opts),
         {:ok, spans} <- run_serving(serving, text, opts) do
      {:ok, Enum.map(spans, &to_result/1)}
    end
  end

  @doc """
  Analyzes multiple texts.
  """
  @spec analyze_many([String.t()], keyword()) :: {:ok, [[Result.t()]]} | {:error, term()}
  def analyze_many(texts, opts \\ []) when is_list(texts) do
    with {:ok, serving} <- serving(opts),
         {:ok, rows} <- run_many_serving(serving, texts, opts) do
      {:ok, Enum.map(rows, fn spans -> Enum.map(spans, &to_result/1) end)}
    end
  end

  defp serving(opts) do
    case Keyword.get(opts, :serving) do
      nil -> build_serving(opts)
      serving -> {:ok, serving}
    end
  end

  defp build_serving(opts) do
    case Keyword.get(opts, :adapter, :ortex) do
      :ortex -> Ortex.build(opts)
      :native -> Native.build(opts)
      adapter -> {:error, {:unsupported_gliner_adapter, adapter}}
    end
  end

  defp run_serving(%Native{} = serving, text, opts), do: Native.run(serving, text, opts)
  defp run_serving(%Ortex{} = serving, text, opts), do: Ortex.run(serving, text, opts)
  defp run_serving(serving, _text, _opts), do: {:error, {:unsupported_gliner_serving, serving}}

  defp run_many_serving(%Native{} = serving, texts, opts),
    do: Native.run_many(serving, texts, opts)

  defp run_many_serving(%Ortex{} = serving, texts, opts), do: Ortex.run_many(serving, texts, opts)

  defp run_many_serving(serving, _texts, _opts),
    do: {:error, {:unsupported_gliner_serving, serving}}

  defp to_result(span) do
    %Result{
      entity: span.entity,
      start: span.byte_start,
      end: span.byte_end,
      byte_start: span.byte_start,
      byte_end: span.byte_end,
      score: span.score,
      text: span.text,
      source_entity: span.source_entity,
      recognizer: :gliner,
      explanation: %Explanation{
        recognizer: :gliner,
        pattern: :gliner_span,
        original_score: span.score,
        score: span.score,
        metadata: span.metadata
      },
      metadata: span.metadata
    }
  end
end
