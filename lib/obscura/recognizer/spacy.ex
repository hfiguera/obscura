defmodule Obscura.Recognizer.Spacy do
  @moduledoc "Experimental pinned spaCy NER recognizer using a prepared native CPU pool."
  @behaviour Obscura.Recognizer
  alias Obscura.Analyzer.ModelOutput
  alias Obscura.Spacy.Boundaries
  alias Obscura.Spacy.Serving

  @impl true
  def name, do: :spacy_cpu
  @impl true
  def supported_entities, do: [:person, :location]

  @impl true
  def analyze(text, opts) do
    with {:ok, predictions} <- Serving.predict(Keyword.get(opts, :serving), text) do
      predictions =
        if Keyword.get(opts, :boundary_policy) == :efficient_v1,
          do: Boundaries.normalize(text, predictions),
          else: predictions

      outputs =
        predictions
        |> Enum.filter(&(&1["label"] in ["PERSON", "GPE", "LOC", "FAC"]))
        |> Enum.map(fn p ->
          %{
            label: p["label"],
            start: p["byte_start"],
            end: p["byte_end"],
            score: 0.85,
            offset_unit: :byte
          }
        end)

      ModelOutput.normalize(text, outputs,
        include_text: Keyword.get(opts, :include_text, true),
        label_map: %{person: ["PERSON"], location: ["GPE", "LOC", "FAC"]},
        unknown_labels: :error
      )
    end
  end
end
