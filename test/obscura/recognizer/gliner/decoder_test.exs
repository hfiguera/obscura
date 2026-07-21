defmodule Obscura.Recognizer.GLiNER.DecoderTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.Decoder
  alias Obscura.Recognizer.GLiNER.Inputs
  alias Obscura.Recognizer.GLiNER.TokenSplitter

  test "decodes logits into inclusive token spans and applies greedy overlap" do
    text = "Rachel Green works"
    {:ok, config} = Config.new(threshold: 0.5)

    prepared = %{
      tokens: TokenSplitter.split(text),
      id_to_class: Inputs.id_to_class(config.labels)
    }

    logits = logits([{0, 1, 0, 10.0}, {0, 0, 0, 9.0}], 3, 2, length(config.labels))

    assert {:ok, [span]} = Decoder.decode(logits, prepared, config, text)
    assert span.entity == :person
    assert span.byte_start == 0
    assert span.byte_end == 12
    assert span.text == "Rachel Green"
    assert span.source_entity == "person"
    assert span.metadata.tokenization_mode == :offset_reconstructed_words_mask
  end

  test "uses per-label thresholds" do
    text = "Rachel"
    {:ok, config} = Config.new(threshold: 0.5, per_label_thresholds: %{"person" => 0.99})

    prepared = %{
      tokens: TokenSplitter.split(text),
      id_to_class: Inputs.id_to_class(config.labels)
    }

    logits = logits([{0, 0, 0, 4.0}], 1, 1, length(config.labels))

    assert {:ok, []} = Decoder.decode(logits, prepared, config, text)
  end

  test "decodes token-level Edge logits from start end and inside scores" do
    text = "Rachel works"

    assert {:ok, config} =
             Config.new(
               model: :knowledgator_gliner_pii_edge_v1,
               label_profile: :edge_open_class,
               threshold: 0.5
             )

    prepared = %{
      tokens: TokenSplitter.split(text),
      id_to_class: %{1 => "name"}
    }

    logits =
      Nx.tensor(
        [
          [
            [[2.0, 2.0, 2.0]],
            [[-2.0, -2.0, -2.0]]
          ]
        ],
        type: {:f, 32}
      )

    assert {:ok, [span]} =
             Decoder.decode(logits, prepared, %{config | span_mode: :token_level}, text)

    assert span.entity == :person
    assert span.text == "Rachel"
    assert span.source_entity == "name"
    assert span.metadata.span_mode == :token_level
  end

  defp logits(high_values, text_length, max_width, class_count) do
    values =
      Map.new(high_values, fn {start, width, class_index, value} ->
        {{start, width, class_index}, value}
      end)

    [
      for start <- 0..(text_length - 1) do
        for width <- 0..(max_width - 1) do
          for class_index <- 0..(class_count - 1) do
            Map.get(values, {start, width, class_index}, -10.0)
          end
        end
      end
    ]
    |> Nx.tensor(type: {:f, 32})
  end
end
