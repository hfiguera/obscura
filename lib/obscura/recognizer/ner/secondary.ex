defmodule Obscura.Recognizer.NER.Secondary do
  @moduledoc """
  Secondary NER recognizer wrapper for opt-in multi-model profiles.

  The standard recognizer registry deduplicates recognizers by module. This
  wrapper lets evaluation profiles run two independent NER servings while
  keeping normal library behavior unchanged.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.NER

  @impl true
  def name, do: :ner_secondary

  @impl true
  def supported_entities, do: NER.supported_entities()

  @impl true
  def analyze(text, opts) do
    if gated_run?(text, opts) do
      NER.analyze(text, opts)
    else
      {:ok, []}
    end
  end

  @impl true
  def analyze_many(texts, opts) do
    texts
    |> Enum.with_index()
    |> Enum.split_with(fn {text, _index} -> gated_run?(text, opts) end)
    |> run_gated_many(texts, opts)
  end

  defp run_gated_many({[], _skipped}, texts, _opts) do
    {:ok, List.duplicate([], length(texts))}
  end

  defp run_gated_many({selected, _skipped}, texts, opts) do
    selected_texts = Enum.map(selected, fn {text, _index} -> text end)

    with {:ok, selected_results} <- NER.analyze_many(selected_texts, opts) do
      selected
      |> Enum.zip(selected_results)
      |> Map.new(fn {{_text, index}, results} -> {index, results} end)
      |> results_by_original_index(length(texts))
      |> then(&{:ok, &1})
    end
  end

  defp results_by_original_index(_selected_by_index, 0), do: []

  defp results_by_original_index(selected_by_index, count) do
    Enum.map(0..(count - 1), &Map.get(selected_by_index, &1, []))
  end

  defp gated_run?(text, opts) do
    case Keyword.get(opts, :secondary_gate) do
      {module, function} when is_atom(module) and is_atom(function) ->
        apply(module, function, [text])

      nil ->
        true
    end
  end
end
