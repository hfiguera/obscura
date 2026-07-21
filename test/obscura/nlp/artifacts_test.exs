defmodule Obscura.NLP.ArtifactsTest do
  use ExUnit.Case, async: true

  alias Obscura.NLP.Artifacts

  test "builds dependency-light tokens, offsets, normalized tokens, and keywords" do
    artifacts = Artifacts.build("Phone Rachel at 202-555-0188.")

    assert artifacts.tokens == ["Phone", "Rachel", "at", "202-555-0188"]
    assert artifacts.normalized_tokens == ["phone", "rachel", "at", "202-555-0188"]
    assert %{byte_start: 0, byte_end: 5} = hd(artifacts.token_offsets)
    assert "phone" in artifacts.keywords
    refute "at" in artifacts.keywords
  end

  test "returns prefix and suffix terms around a span" do
    artifacts = Artifacts.build("Call me at 202-555-0188 tomorrow")
    {start, byte_length} = :binary.match("Call me at 202-555-0188 tomorrow", "202-555-0188")

    terms =
      Artifacts.surrounding_terms(artifacts, start, start + byte_length,
        prefix_count: 2,
        suffix_count: 1
      )

    assert terms == ["me", "at", "tomorrow"]
  end

  test "can carry precomputed model outputs for artifact-backed recognizers" do
    artifacts = Artifacts.build("Rachel works in Paris")
    outputs = [%{label: "PER", start: 0, end: 6, score: 0.99}]

    assert {:ok, artifacts} = Artifacts.put_model_outputs(artifacts, outputs)
    assert artifacts.model_outputs == outputs
    assert artifacts.model_outputs_ready == true
  end

  test "distinguishes default empty outputs from model-ran empty outputs" do
    artifacts = Artifacts.build("No model outputs here")

    assert artifacts.model_outputs == []
    assert artifacts.model_outputs_ready == false

    assert {:ok, artifacts} = Artifacts.put_model_outputs(artifacts, [])
    assert artifacts.model_outputs == []
    assert artifacts.model_outputs_ready == true
  end
end
