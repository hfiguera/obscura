defmodule Obscura.Test.GLiNERParityAssertions do
  @moduledoc false

  import ExUnit.Assertions

  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.Inputs
  alias Obscura.Recognizer.GLiNER.LabelMap
  alias Obscura.Recognizer.GLiNER.Ortex, as: GLiNEROrtex

  @input_names ~w(input_ids attention_mask words_mask text_lengths span_idx span_mask)

  def assert_parity(serving, model, reference, logit_tolerance \\ 3.0e-3) do
    assert reference["summary"]["passed"]

    for row <- reference["rows"] do
      profile = String.to_existing_atom(row["label_profile"])
      {:ok, config} = Config.new(model: model, label_profile: profile)
      {:ok, prepared} = Inputs.prepare(serving.tokenizer, row["text"], config)

      assert_input_hashes(prepared.tensors, row["inputs"], row)
      assert_raw_logits(serving.model, prepared.tensors, row, logit_tolerance)
      assert_decoded_spans(serving, profile, row)
    end
  end

  defp assert_input_hashes(tensors, expected, row) do
    @input_names
    |> Enum.zip(Tuple.to_list(tensors))
    |> Enum.each(fn {name, tensor} ->
      assert tensor_sha256(tensor) == expected[name]["sha256"],
             "input mismatch for #{row["id"]}/#{row["label_profile"]}/#{name}"
    end)
  end

  defp assert_raw_logits(model, tensors, row, tolerance) do
    ortex = Module.concat([Ortex])
    assert {logits} = ortex.run(model, tensors)
    logits = binary_backend_tensor(logits)
    expected = expected_logits(row["onnx_logits"])
    absolute_difference = Nx.abs(Nx.subtract(logits, expected))
    max_difference = absolute_difference |> Nx.reduce_max() |> Nx.to_number()
    mean_difference = absolute_difference |> Nx.mean() |> Nx.to_number()

    assert max_difference <= tolerance,
           "logit mismatch for #{row["id"]}/#{row["label_profile"]}: max=#{max_difference}, mean=#{mean_difference}"
  end

  defp assert_decoded_spans(serving, profile, row) do
    assert {:ok, actual} =
             GLiNEROrtex.run(serving, row["text"],
               label_profile: profile,
               threshold: row["threshold"]
             )

    expected =
      row["onnx_spans"]
      |> Enum.map(fn span ->
        %{
          byte_start: span["byte_start"],
          byte_end: span["byte_end"],
          text: span["text"],
          entity: LabelMap.to_entity(profile, span["label"]),
          score: span["score"]
        }
      end)
      |> sort_spans()

    actual =
      actual
      |> Enum.map(&Map.take(&1, [:byte_start, :byte_end, :text, :entity, :score]))
      |> sort_spans()

    assert length(actual) == length(expected),
           "span count mismatch for #{row["id"]}/#{row["label_profile"]}"

    Enum.zip(actual, expected)
    |> Enum.each(fn {actual_span, expected_span} ->
      assert Map.drop(actual_span, [:score]) == Map.drop(expected_span, [:score])
      assert_in_delta actual_span.score, expected_span.score, 1.0e-5
    end)
  end

  defp sort_spans(spans), do: Enum.sort_by(spans, &{&1.byte_start, &1.byte_end, &1.entity})

  defp tensor_sha256(tensor) do
    :sha256
    |> :crypto.hash(Nx.to_binary(tensor))
    |> Base.encode16(case: :lower)
  end

  defp expected_logits(reference) do
    reference["base64"]
    |> Base.decode64!()
    |> Nx.from_binary({:f, 32})
    |> Nx.reshape(List.to_tuple(reference["shape"]))
  end

  defp binary_backend_tensor(tensor) do
    tensor
    |> Nx.to_binary()
    |> Nx.from_binary(Nx.type(tensor))
    |> Nx.reshape(Nx.shape(tensor))
  end
end
