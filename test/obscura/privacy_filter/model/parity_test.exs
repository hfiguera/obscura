defmodule Obscura.PrivacyFilter.Model.ParityTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.LabelInfo
  alias Obscura.PrivacyFilter.Model
  alias Obscura.PrivacyFilter.Model.Parameters
  alias Obscura.PrivacyFilter.SequenceLabeling
  alias Obscura.PrivacyFilter.SequenceLabeling.TokenizedExample
  alias Obscura.PrivacyFilter.Spans
  alias Obscura.PrivacyFilter.Viterbi

  @fixture "eval/privacy_filter/fixtures/tiny_model_parity.json"

  test "tiny one-block model forward matches Python OPF layer stages and logits" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    config = atomize_keys(fixture["config"])
    params = tensors_from_json(fixture["params"])
    token_ids = Nx.tensor(fixture["token_ids"], type: {:s, 64})

    assert {:ok, model_params} = Parameters.from_map(params, config)

    actual = Model.debug(token_ids, model_params, config)
    tolerance = fixture["tolerance"]

    assert_fixture_stage_close(actual.embedding, fixture, ["embedding"], tolerance)

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :normalized]),
      fixture,
      ["blocks", 0, "attention", "normalized"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :qkv]),
      fixture,
      ["blocks", 0, "attention", "qkv"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :query_rotary]),
      fixture,
      ["blocks", 0, "attention", "query_rotary"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :key_rotary]),
      fixture,
      ["blocks", 0, "attention", "key_rotary"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :value]),
      fixture,
      ["blocks", 0, "attention", "value"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :query_scaled]),
      fixture,
      ["blocks", 0, "attention", "query_scaled"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :key_scaled]),
      fixture,
      ["blocks", 0, "attention", "key_scaled"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :attention]),
      fixture,
      ["blocks", 0, "attention", "attention"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :projection]),
      fixture,
      ["blocks", 0, "attention", "projection"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:attention, :output]),
      fixture,
      ["blocks", 0, "attention", "output"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:mlp, :normalized]),
      fixture,
      ["blocks", 0, "mlp", "normalized"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:mlp, :flat]),
      fixture,
      ["blocks", 0, "mlp", "flat"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:mlp, :gate_logits]),
      fixture,
      ["blocks", 0, "mlp", "gate_logits"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:mlp, :expert_scores]),
      fixture,
      ["blocks", 0, "mlp", "expert_scores"],
      tolerance
    )

    assert_stage_equal(actual.blocks |> hd() |> get_in([:mlp, :expert_indices]), fixture, [
      "blocks",
      0,
      "mlp",
      "expert_indices"
    ])

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:mlp, :expert_weights]),
      fixture,
      ["blocks", 0, "mlp", "expert_weights"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:mlp, :expert_output]),
      fixture,
      ["blocks", 0, "mlp", "expert_output"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> get_in([:mlp, :output]),
      fixture,
      ["blocks", 0, "mlp", "output"],
      tolerance
    )

    assert_fixture_stage_close(
      actual.blocks |> hd() |> Map.fetch!(:output),
      fixture,
      ["blocks", 0, "output"],
      tolerance
    )

    assert_fixture_stage_close(actual.final_norm, fixture, ["final_norm"], tolerance)
    assert_fixture_stage_close(actual.logits, fixture, ["logits"], tolerance)

    assert_stage_close(
      Model.forward(token_ids, model_params, config),
      fixture["python_logits"],
      tolerance
    )
  end

  test "tiny model window construction matches Python OPF" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    [token_ids] = fixture["token_ids"]

    example = %TokenizedExample{
      tokens: List.to_tuple(token_ids),
      labels: token_ids |> Enum.map(fn _ -> 0 end) |> List.to_tuple(),
      example_id: "tiny-model",
      text: "tiny"
    }

    assert {:ok, windows} = SequenceLabeling.example_to_windows(example, 2)

    actual =
      Enum.map(windows, fn window ->
        %{
          "example_id" => window.example_id,
          "tokens" => Tuple.to_list(window.tokens),
          "labels" => Tuple.to_list(window.labels),
          "offsets" => window.offsets |> Tuple.to_list() |> Enum.map(&identity/1),
          "token_example_ids" =>
            window.token_example_ids |> Tuple.to_list() |> Enum.map(&identity/1),
          "mask" => Tuple.to_list(window.mask)
        }
      end)

    assert actual == fixture["windows"]
  end

  test "tiny postprocessing matches Python OPF labels, spans, and entity mapping" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    postprocessing = fixture["postprocessing"]
    assert {:ok, label_info} = LabelInfo.build(postprocessing["class_names"])

    decoded_labels = Viterbi.decode(Viterbi.new(label_info), postprocessing["token_logprobs"])

    assert decoded_labels == postprocessing["decoded_labels"]

    labels_by_index =
      decoded_labels
      |> Enum.with_index()
      |> Map.new(fn {label, index} -> {index, label} end)

    assert stringify_integer_keys(labels_by_index) == postprocessing["labels_by_index"]

    token_spans = Spans.labels_to_spans(labels_by_index, label_info)
    assert tuple_spans_to_lists(token_spans) == postprocessing["token_spans"]

    char_spans =
      Spans.token_spans_to_char_spans(
        token_spans,
        postprocessing["char_starts"],
        postprocessing["char_ends"]
      )

    assert tuple_spans_to_lists(char_spans) == postprocessing["char_spans"]

    trimmed = Spans.trim_char_spans_whitespace(char_spans, postprocessing["text"])
    assert tuple_spans_to_lists(trimmed) == postprocessing["trimmed_char_spans"]

    kept = Spans.discard_overlapping_spans_by_label(trimmed)
    assert tuple_spans_to_lists(kept) == postprocessing["kept_char_spans"]

    assert {:ok, detected} =
             Spans.char_spans_to_detected_spans(kept, postprocessing["text"], label_info)

    actual_entities =
      Enum.map(detected, fn span ->
        %{
          "label" => span.label,
          "entity" => Atom.to_string(span.entity),
          "start" => span.start,
          "end" => span.end,
          "text" => span.text
        }
      end)

    assert actual_entities == postprocessing["mapped_entities"]
  end

  defp tensors_from_json(params) do
    Map.new(params, fn {name, value} -> {name, Nx.tensor(value, type: {:f, 32})} end)
  end

  defp atomize_keys(map) do
    Map.new(map, fn {key, value} -> {String.to_atom(key), value} end)
  end

  defp assert_fixture_stage_close(actual, fixture, path, tolerance) do
    expected = fetch_stage(fixture["python_stages"], path)
    assert_stage_close(actual, expected, tolerance, Enum.map_join(path, ".", &to_string/1))
  end

  defp assert_stage_close(actual, expected, tolerance) do
    assert_stage_close(actual, expected, tolerance, "tensor")
  end

  defp assert_stage_close(actual, expected, tolerance, label) do
    expected = Nx.tensor(expected, type: {:f, 32})

    assert Nx.all_close(actual, expected,
             atol: tolerance["atol"],
             rtol: tolerance["rtol"]
           ),
           "#{label} differs from Python OPF"
  end

  defp assert_stage_equal(actual, fixture, path) do
    expected = fetch_stage(fixture["python_stages"], path)
    assert Nx.to_list(actual) == expected
  end

  defp fetch_stage(value, []), do: value

  defp fetch_stage(value, [key | rest]) when is_map(value),
    do: value |> Map.fetch!(key) |> fetch_stage(rest)

  defp fetch_stage(value, [index | rest]) when is_list(value) and is_integer(index),
    do: value |> Enum.at(index) |> fetch_stage(rest)

  defp tuple_spans_to_lists(spans), do: Enum.map(spans, &Tuple.to_list/1)

  defp stringify_integer_keys(map) do
    Map.new(map, fn {key, value} -> {Integer.to_string(key), value} end)
  end

  defp identity(value), do: value
end
