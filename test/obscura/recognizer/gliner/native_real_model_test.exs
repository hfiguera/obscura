defmodule Obscura.Recognizer.GLiNER.NativeRealModelTest do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.GLiNER
  alias Obscura.Recognizer.GLiNER.Native

  @moduletag :gliner_native
  @full_oracle_dir ".cache/gliner-native-full-parity"
  @parity_reference "eval/gliner/urchade-parity-reference.json"
  @full_trace_tolerance 5.0e-4
  @cross_runtime_logit_tolerance 3.0e-3
  @score_tolerance 5.0e-6

  setup_all do
    model_dir = System.fetch_env!("OBSCURA_GLINER_NATIVE_MODEL_DIR")
    oracle_dir = System.get_env("OBSCURA_GLINER_NATIVE_ORACLE_DIR", @full_oracle_dir)

    {:ok, serving} = Native.build(model_dir: model_dir)
    oracle = Safetensors.read!(Path.join(oracle_dir, "full_oracle.safetensors"))
    reference = @parity_reference |> File.read!() |> Jason.decode!()

    %{serving: serving, oracle: oracle, reference: reference}
  end

  test "matches every recorded Python layer and head stage", context do
    {:ok, trace, prepared} =
      Native.trace(context.serving, "Rachel works at Google in Paris.")

    assert_input_parity(prepared.tensors, context.oracle)
    assert_close!(trace["embedding"], context.oracle["expected.embedding"], "embedding")

    for layer <- 0..11 do
      assert_close!(
        elem(trace["layers"], layer + 1),
        context.oracle["expected.layer.#{layer}"],
        "layer.#{layer}"
      )
    end

    for stage <- ~w(projected prompts words rnn span prompt logits) do
      assert_close!(trace[stage], context.oracle["expected.#{stage}"], stage)
    end
  end

  test "matches all existing ONNX parity spans, labels, scores, and offsets", context do
    for row <- context.reference["rows"] do
      profile = String.to_existing_atom(row["label_profile"])

      {:ok, trace, _prepared} =
        Native.trace(context.serving, row["text"], label_profile: profile)

      expected_logits = expected_logits(row["onnx_logits"])
      difference = Nx.abs(Nx.subtract(trace["logits"], expected_logits))

      assert Nx.to_number(Nx.reduce_max(difference)) <= @cross_runtime_logit_tolerance,
             "logit mismatch for #{row["id"]}/#{profile}"

      {:ok, actual} =
        Native.run(context.serving, row["text"],
          label_profile: profile,
          threshold: row["threshold"]
        )

      expected = row["onnx_spans"]
      assert length(actual) == length(expected)

      for {actual_span, expected_span} <- Enum.zip(actual, expected) do
        assert actual_span.byte_start == expected_span["byte_start"]
        assert actual_span.byte_end == expected_span["byte_end"]
        assert actual_span.text == expected_span["text"]
        assert actual_span.source_entity == expected_span["label"]
        assert_in_delta actual_span.score, expected_span["score"], @score_tolerance
      end
    end
  end

  test "runs through the recognizer facade with strict GPU metadata", context do
    assert {:ok, results} =
             GLiNER.analyze("Rachel works at Google in Paris.",
               serving: context.serving,
               label_profile: :open_class
             )

    assert Enum.map(results, &{&1.entity, &1.text}) == [
             {:person, "Rachel"},
             {:organization, "Google"},
             {:location, "Paris"}
           ]

    assert Enum.all?(results, fn result ->
             result.metadata.backend == :emily and result.metadata.device == :gpu and
               result.metadata.fallback == :raise and
               result.metadata.adapter == "Obscura.Recognizer.GLiNER.Native"
           end)
  end

  test "reuses one native serving for facade batch analysis", context do
    assert {:ok, [first, second]} =
             GLiNER.analyze_many(
               ["Rachel works in Paris.", "Google has an office in London."],
               serving: context.serving,
               label_profile: :open_class
             )

    assert Enum.any?(first, &(&1.entity == :person and &1.text == "Rachel"))
    assert Enum.any?(second, &(&1.entity == :organization and &1.text == "Google"))
    assert Enum.any?(second, &(&1.entity == :location and &1.text == "London"))
  end

  defp assert_input_parity(tensors, oracle) do
    names = ~w(input_ids attention_mask words_mask text_lengths span_idx span_mask)

    for {name, tensor} <- Enum.zip(names, Tuple.to_list(tensors)) do
      assert Nx.to_binary(tensor) == Nx.to_binary(oracle["input.#{name}"]),
             "input mismatch for #{name}"
    end
  end

  defp assert_close!(actual, expected, stage) do
    difference = Nx.abs(Nx.subtract(actual, expected))
    maximum = difference |> Nx.reduce_max() |> Nx.to_number()

    assert maximum <= @full_trace_tolerance,
           "#{stage} max abs error #{maximum} exceeds #{@full_trace_tolerance}"
  end

  defp expected_logits(reference) do
    reference["base64"]
    |> Base.decode64!()
    |> Nx.from_binary({:f, 32})
    |> Nx.reshape(List.to_tuple(reference["shape"]))
  end
end
