defmodule Obscura.Recognizer.GLiNER.Native.WeightsTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Native.Weights

  test "defines the complete pinned Urchade tensor contract" do
    shapes = Weights.expected_shapes()

    assert map_size(shapes) == 224

    assert shapes["token_rep_layer.bert_layer.model.embeddings.word_embeddings.weight"] ==
             {250_105, 768}

    assert shapes[
             "token_rep_layer.bert_layer.model.encoder.layer.11.output.LayerNorm.weight"
           ] == {768}

    assert shapes["span_rep_layer.span_rep_layer.out_project.3.weight"] == {512, 2048}
  end
end
