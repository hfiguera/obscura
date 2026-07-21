defmodule Obscura.PrivacyFilter.Model.PythonOriginalParityTest do
  use ExUnit.Case, async: false

  alias Obscura.PrivacyFilter.Model
  alias Obscura.PrivacyFilter.SequenceLabeling
  alias Obscura.PrivacyFilter.SequenceLabeling.TokenizedExample
  alias Obscura.PrivacyFilter.Serving
  alias Obscura.PrivacyFilter.Spans
  alias Obscura.PrivacyFilter.Tokenization
  alias Obscura.PrivacyFilter.Viterbi

  @fixture "eval/privacy_filter/fixtures/python_original_runtime_reference.json"

  @moduletag :real_model
  @moduletag :privacy_filter
  @moduletag timeout: 900_000

  test "Python original checkpoint matches Python tokenization, decoding, and spans" do
    reference = python_original_reference!()
    checkpoint = checkpoint!(reference)

    assert {:ok, serving} =
             Serving.build(
               checkpoint: checkpoint,
               layout: :python_original,
               backend: backend!(),
               n_ctx: reference["n_ctx"],
               decoder: :viterbi
             )

    assert {:ok, tokenization} = Tokenization.from_config(serving.config, reference["text"])
    assert tokenization.token_ids == reference["token_ids"]

    assert {:ok, windows} =
             example_windows(
               tokenization,
               serving.label_info.background_token_label,
               reference["n_ctx"]
             )

    assert Enum.map(windows, &window_to_json/1) == reference["windows"]

    assert {:ok, logits} = forward_logits(serving, tokenization.token_ids)
    expected_logits = Nx.tensor(reference["logits"], type: {:f, 32})
    diff = tensor_diff(logits, expected_logits)

    assert {:ok, logprob_rows} = logits_to_logprobs(logits)

    decoded_labels =
      serving.label_info
      |> Viterbi.new(serving.viterbi_biases)
      |> Viterbi.decode(logprob_rows)

    assert decoded_labels == reference["decoded_labels"]

    labels_by_index =
      decoded_labels |> Enum.with_index() |> Map.new(fn {label, index} -> {index, label} end)

    token_spans = Spans.labels_to_spans(labels_by_index, serving.label_info)

    char_spans =
      Spans.token_spans_to_char_spans(
        token_spans,
        tokenization.char_starts,
        tokenization.char_ends
      )

    trimmed = Spans.trim_char_spans_whitespace(char_spans, reference["text"])
    kept = Spans.discard_overlapping_spans_by_label(trimmed)

    assert {:ok, detected} =
             Spans.char_spans_to_detected_spans(kept, reference["text"], serving.label_info)

    assert tuple_spans_to_lists(token_spans) == reference["token_spans"]
    assert tuple_spans_to_lists(char_spans) == reference["char_spans"]
    assert tuple_spans_to_lists(trimmed) == reference["trimmed_char_spans"]
    assert tuple_spans_to_lists(kept) == reference["kept_char_spans"]
    assert detected_spans_to_json(detected) == reference["detected_spans"]

    refute diff.all_close?,
           "Real Python-original logits unexpectedly matched Python tolerance; update docs and report"

    assert diff.max_abs_diff < 3.0
  end

  defp python_original_reference! do
    reference = @fixture |> File.read!() |> Jason.decode!()

    unless reference["status"] == "completed" do
      flunk("Python original reference fixture is not completed: #{inspect(reference)}")
    end

    reference
  end

  defp checkpoint!(reference) do
    System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT", reference["checkpoint"])
  end

  defp backend! do
    case System.get_env("OBSCURA_PRIVACY_FILTER_BACKEND", "emily") do
      "emily" ->
        Application.put_env(:emily, :fallback, :raise)
        Application.ensure_all_started(:emily)

        unless Code.ensure_loaded?(Emily) and Code.ensure_loaded?(Emily.Backend) and
                 Code.ensure_loaded?(Emily.Compiler) do
          flunk("Set OBSCURA_PRIVACY_FILTER_BACKEND to an available backend; Emily is not loaded")
        end

        :emily

      "binary" ->
        :binary

      other ->
        flunk("Unsupported OBSCURA_PRIVACY_FILTER_BACKEND=#{inspect(other)} for this test")
    end
  end

  defp example_windows(tokenization, background, n_ctx) do
    token_ids = Map.fetch!(tokenization, :token_ids)

    example = %TokenizedExample{
      tokens: List.to_tuple(token_ids),
      labels: List.duplicate(background, length(token_ids)) |> List.to_tuple(),
      example_id: "python-original-reference",
      text: Map.fetch!(tokenization, :text)
    }

    SequenceLabeling.example_to_windows(example, n_ctx)
  end

  defp forward_logits(serving, token_ids) do
    attention_mask = List.duplicate(1, length(token_ids))

    token_ids
    |> then(&Nx.tensor([&1]))
    |> Model.forward_result(serving.params, serving.config,
      attention_mask: Nx.tensor([attention_mask])
    )
  end

  defp logits_to_logprobs(logits) do
    case Nx.shape(logits) do
      {1, _tokens, _labels} ->
        [rows] =
          logits
          |> log_softmax(axis: -1)
          |> Nx.to_list()

        {:ok, rows}

      shape ->
        {:error, {:privacy_filter_logits_shape_mismatch, shape}}
    end
  end

  defp log_softmax(tensor, opts) do
    axis = Keyword.fetch!(opts, :axis)
    max_value = Nx.reduce_max(tensor, axes: [axis], keep_axes: true)
    shifted = Nx.subtract(tensor, max_value)
    shifted |> Nx.subtract(Nx.log(Nx.sum(Nx.exp(shifted), axes: [axis], keep_axes: true)))
  end

  defp tensor_diff(actual, expected) do
    diff = Nx.abs(Nx.subtract(Nx.as_type(actual, {:f, 32}), expected))

    all_close =
      actual
      |> Nx.all_close(expected, atol: 1.0e-4, rtol: 1.0e-4)
      |> Nx.to_number()

    %{
      max_abs_diff: Nx.reduce_max(diff) |> Nx.to_number(),
      all_close?: all_close == 1
    }
  end

  defp window_to_json(window) do
    %{
      "example_id" => window.example_id,
      "tokens" => Tuple.to_list(window.tokens),
      "labels" => Tuple.to_list(window.labels),
      "offsets" => Tuple.to_list(window.offsets),
      "token_example_ids" => Tuple.to_list(window.token_example_ids),
      "mask" => Tuple.to_list(window.mask)
    }
  end

  defp tuple_spans_to_lists(spans), do: Enum.map(spans, &Tuple.to_list/1)

  defp detected_spans_to_json(spans) do
    Enum.map(spans, fn span ->
      %{
        "label" => span.label,
        "start" => span.start,
        "end" => span.end,
        "text" => span.text
      }
    end)
  end
end
