defmodule Obscura.Analyzer.ArtifactsPipelineTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Result
  alias Obscura.NLP.Artifacts

  defmodule ArtifactAwareRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :artifact_probe

    @impl true
    def supported_entities, do: [:artifact_probe]

    @impl true
    def analyze(text, opts) do
      artifacts = Keyword.fetch!(opts, :nlp_artifacts)
      [first | _rest] = artifacts.tokens

      [
        %Result{
          entity: :artifact_probe,
          start: 0,
          end: byte_size(first),
          byte_start: 0,
          byte_end: byte_size(first),
          score: 1.0,
          text: first,
          source_entity: "ARTIFACT_PROBE",
          recognizer: :artifact_probe,
          metadata: %{token_count: length(artifacts.tokens), original_text: text}
        }
      ]
    end
  end

  defmodule ModelOutputEngine do
    @behaviour Obscura.NLP.Engine

    @impl true
    def build_artifacts(text, _opts) do
      outputs =
        case text do
          "Rachel works in Paris." ->
            [
              %{label: "PER", start: 0, end: 6, score: 0.99},
              %{label: "LOC", start: 16, end: 21, score: 0.98}
            ]

          "Alice" ->
            [%{label: "PER", start: 0, end: 5, score: 0.97}]

          "Denver" ->
            [%{label: "LOC", start: 0, end: 6, score: 0.96}]
        end

      text
      |> Artifacts.build()
      |> Artifacts.put_model_outputs(outputs)
    end

    @impl true
    def build_many(texts, opts) do
      texts
      |> Enum.reduce_while({:ok, []}, fn text, {:ok, acc} ->
        case build_artifacts(text, opts) do
          {:ok, artifacts} -> {:cont, {:ok, [artifacts | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, artifacts} -> {:ok, Enum.reverse(artifacts)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  test "analyzer builds NLP artifacts once and passes them to recognizers" do
    assert {:ok, [result]} =
             Obscura.analyze("Token aware recognizer",
               entities: [:artifact_probe],
               recognizers: [ArtifactAwareRecognizer]
             )

    assert result.text == "Token"
    assert result.metadata.token_count == 3
    assert result.metadata.original_text == "Token aware recognizer"
  end

  test "analyze_many passes per-text artifacts through fallback recognizer execution" do
    assert {:ok, [[first], [second]]} =
             Obscura.analyze_many(["First sample", "Second sample"],
               entities: [:artifact_probe],
               recognizers: [ArtifactAwareRecognizer]
             )

    assert first.text == "First"
    assert first.metadata.token_count == 2
    assert second.text == "Second"
    assert second.metadata.token_count == 2
  end

  test "analyzer-level NLP engine populates model outputs consumed by NER" do
    assert {:ok, [person, location]} =
             Obscura.analyze("Rachel works in Paris.",
               entities: [:person, :location],
               recognizers: [:ner],
               nlp_engine: ModelOutputEngine
             )

    assert person.entity == :person
    assert location.entity == :location
  end

  test "analyze_many uses analyzer-level NLP engine artifacts" do
    assert {:ok, [[person], [location]]} =
             Obscura.analyze_many(["Alice", "Denver"],
               entities: [:person, :location],
               recognizers: [:ner],
               nlp_engine: ModelOutputEngine
             )

    assert person.entity == :person
    assert location.entity == :location
  end
end
