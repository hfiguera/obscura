defmodule Obscura.Recognizer.GLiNER.Native.InputTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.Inputs
  alias Obscura.Recognizer.GLiNER.Native.Input

  test "builds DeBERTa log-bucketed relative positions" do
    positions = Input.relative_positions(384)

    assert Nx.shape(positions) == {1, 384, 384}
    assert positions[0][0][0] |> Nx.to_number() == 0
    assert positions[0][128][0] |> Nx.to_number() == 128
    assert positions[0][0][128] |> Nx.to_number() == -128
    assert positions[0][383][0] |> Nx.to_number() == 229
    assert positions[0][0][383] |> Nx.to_number() == -229
  end

  test "pads token, word, and span tensors into a reusable shape bucket" do
    config = config()
    {span_indexes, span_mask} = Inputs.span_indexes(2, config.max_width)

    prepared = %{
      tensors: {
        Nx.tensor([[250_103, 10, 11, 12, 13]], type: {:s, 64}),
        Nx.tensor([[1, 1, 1, 1, 1]], type: {:s, 64}),
        Nx.tensor([[0, 0, 0, 1, 2]], type: {:s, 64}),
        Nx.tensor([[2]], type: {:s, 64}),
        Nx.tensor([span_indexes], type: {:s, 64}),
        Nx.tensor([span_mask], type: {:u, 8})
      },
      word_token_indexes: [3, 4]
    }

    assert {:ok, input} =
             Input.build(prepared, config, shape_buckets: [{8, 4}], max_width: 12)

    assert Nx.shape(input["input_ids"]) == {1, 8}
    assert Nx.shape(input["relative_pos"]) == {1, 8, 8}
    assert Nx.shape(input["word_token_indexes"]) == {1, 4}
    assert Nx.to_flat_list(input["word_mask"]) == [1, 1, 0, 0]
    assert Nx.shape(input["span_idx"]) == {1, 48, 2}
    assert Enum.count(Nx.to_flat_list(input["span_mask"]), &(&1 == 1)) == 3
  end

  test "rejects an input larger than every configured bucket" do
    config = config()
    {span_indexes, span_mask} = Inputs.span_indexes(2, config.max_width)

    prepared = %{
      tensors: {
        Nx.tensor([[250_103, 10, 11, 12, 13]], type: {:s, 64}),
        Nx.tensor([[1, 1, 1, 1, 1]], type: {:s, 64}),
        Nx.tensor([[0, 0, 0, 1, 2]], type: {:s, 64}),
        Nx.tensor([[2]], type: {:s, 64}),
        Nx.tensor([span_indexes], type: {:s, 64}),
        Nx.tensor([span_mask], type: {:u, 8})
      },
      word_token_indexes: [3, 4]
    }

    assert {:error, {:gliner_native_input_too_large, {5, 2}, [{4, 2}]}} =
             Input.build(prepared, config, shape_buckets: [{4, 2}], max_width: 12)
  end

  defp config do
    %Config{
      model: :urchade_gliner_multi_pii_v1,
      label_profile: :open_class,
      labels: ["person"],
      threshold: 0.5,
      max_width: 12,
      max_length: 384,
      per_label_thresholds: %{},
      flat_ner: true,
      multi_label: false,
      class_token_index: 250_103,
      embed_ent_token: true,
      span_mode: :span_level
    }
  end
end
