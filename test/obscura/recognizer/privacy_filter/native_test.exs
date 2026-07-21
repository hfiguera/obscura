defmodule Obscura.Recognizer.PrivacyFilter.NativeTest do
  use ExUnit.Case, async: true

  alias Obscura.Internal.StageDiagnostics
  alias Obscura.PrivacyFilter.Serving
  alias Obscura.Recognizer.PrivacyFilter.Native

  test "analyze runs through a prebuilt native privacy-filter serving" do
    serving = synthetic_serving!()

    assert {:ok, [result]} = Native.analyze("Ada", serving: serving)
    assert result.entity == :person
    assert result.text == "Ada"
    assert result.recognizer == :privacy_filter_native
  end

  test "analyzer can use the opt-in native privacy-filter recognizer" do
    serving = synthetic_serving!()

    assert {:ok, results} =
             Obscura.Analyzer.analyze("Ada",
               entities: [:person],
               recognizers: [{:privacy_filter_native, serving: serving}]
             )

    assert [%{entity: :person, text: "Ada"}] = results
  end

  test "analyzer can run native privacy-filter without deterministic built-ins" do
    serving = empty_serving!()

    assert {:ok, []} =
             Obscura.Analyzer.analyze("Email ada@example.com",
               entities: [:email],
               built_ins: false,
               recognizers: [{:privacy_filter_native, serving: serving}]
             )
  end

  test "hybrid-style privacy-filter execution still runs deterministic built-ins" do
    serving = empty_serving!()

    assert {:ok, results} =
             Obscura.Analyzer.analyze("Email ada@example.com",
               entities: [:email],
               recognizers: [:default, {:privacy_filter_native, serving: serving}]
             )

    assert Enum.any?(results, &(&1.entity == :email and &1.text == "ada@example.com"))
  end

  test "analyze_many reuses one serving across texts" do
    serving = synthetic_serving!()

    assert {:ok, [[first], [second]]} = Native.analyze_many(["Ada", "Alan"], serving: serving)
    assert first.text == "Ada"
    assert second.text == "Alan"
  end

  test "analyze requires explicit serving or checkpoint options" do
    assert {:error, :missing_privacy_filter_checkpoint_or_config} = Native.analyze("Ada", [])
  end

  test "analyze emits serving timings when a timing recipient and ref are provided" do
    ref = make_ref()

    serving = synthetic_serving!()

    assert {:ok, [_result]} =
             Native.analyze("Ada",
               serving: serving,
               timing_recipient: self(),
               timing_ref: ref
             )

    assert_receive {:privacy_filter_serving_timings, ^ref, timings}
    assert timings.tokenization_ms >= 0.0
    assert timings.model_ms >= 0.0
    assert timings.decode_ms >= 0.0
    assert timings.total_ms >= 0.0
  end

  test "diagnostic capture records host-visible stages and fused device limitations" do
    serving = synthetic_serving!()

    {{:ok, [_result]}, diagnostics} =
      StageDiagnostics.capture(true, fn ->
        Native.analyze("Ada", serving: serving)
      end)

    assert diagnostics.stages.tokenization.count == 1
    assert diagnostics.stages.token_packing.count == 1
    assert diagnostics.stages.model_serving.count == 1
    assert diagnostics.stages.logprob_conversion.count == 1
    assert diagnostics.stages.viterbi_logprob_decode.count == 1
    assert diagnostics.stages.span_reconstruction_entity_mapping.count == 1
    assert diagnostics.metadata.token_count > 0
    assert diagnostics.metadata.window_count == 1
    assert diagnostics.metadata.model_packed_tokens == diagnostics.metadata.token_count
    assert diagnostics.metadata.model_padding_tokens == 0
    assert diagnostics.metadata.model_padding_ratio == 0.0

    assert diagnostics.unavailable.privacy_filter_attention ==
             :fused_compiled_device_graph

    assert diagnostics.unavailable.privacy_filter_moe == :fused_compiled_device_graph
  end

  defp synthetic_serving! do
    {:ok, serving} =
      Serving.build(
        config: config(),
        decoder: :argmax,
        model_fun: fn token_ids, _attention_mask ->
          flat_token_ids = Nx.to_flat_list(token_ids)
          single_person_first_token_logits(length(flat_token_ids))
        end
      )

    serving
  end

  defp empty_serving! do
    {:ok, serving} =
      Serving.build(
        config: config(),
        decoder: :argmax,
        model_fun: fn token_ids, _attention_mask ->
          flat_token_ids = Nx.to_flat_list(token_ids)
          all_outside_logits(length(flat_token_ids))
        end
      )

    serving
  end

  defp config do
    %{
      encoding: "cl100k_base",
      ner_class_names: [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person"
      ]
    }
  end

  defp single_person_first_token_logits(tokens) do
    rows =
      for index <- 0..(tokens - 1) do
        if index == 0 do
          [-10.0, -10.0, -10.0, -10.0, 10.0]
        else
          [10.0, -10.0, -10.0, -10.0, -10.0]
        end
      end

    Nx.tensor([rows])
  end

  defp all_outside_logits(tokens) do
    rows =
      for _index <- 0..(tokens - 1) do
        [10.0, -10.0, -10.0, -10.0, -10.0]
      end

    Nx.tensor([rows])
  end
end
