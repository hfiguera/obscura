defmodule Obscura.Recognizer.NER.ChunkerTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.Chunker

  test "splits text into overlapping token-boundary chunks" do
    text = "Alice works at North Valley Medical Center in Seattle."

    assert {:ok, [first, second | _rest]} =
             Chunker.chunks(text, model_chunk_size: 28, model_chunk_overlap: 8)

    assert first.index == 0
    assert first.byte_start == 0
    assert first.byte_end <= 28
    assert second.byte_start < first.byte_end
    assert second.byte_start > first.byte_start

    assert binary_part(text, second.byte_start, second.byte_end - second.byte_start) ==
             second.text
  end

  test "shifts byte offsets from chunk-relative outputs to original text offsets" do
    chunk = %{
      index: 1,
      text: "Paris office",
      byte_start: 42,
      byte_end: 54,
      character_start: 42,
      character_end: 54
    }

    outputs = [%{label: "GPE", start: 0, end: 5, score: 0.91, offset_unit: :byte}]

    assert [
             %{
               start: 42,
               end: 47,
               model_chunking: :character,
               model_chunk_index: 1,
               model_chunk_byte_start: 42,
               model_chunk_overlap: 8
             }
           ] =
             Chunker.absolute_outputs(chunk, outputs,
               model_chunk_size: 20,
               model_chunk_overlap: 8
             )
  end

  test "deduplicates overlap predictions by highest score" do
    outputs = [
      %{label: "ORG", start: 10, end: 20, score: 0.80},
      %{label: "ORG", start: 10, end: 20, score: 0.93}
    ]

    assert [%{score: 0.93}] = Chunker.dedupe_outputs(outputs)
  end

  test "does not split multibyte text on invalid UTF-8 boundaries" do
    assert {:ok, chunks} = Chunker.chunks("😀😀😀😀", model_chunk_size: 5, model_chunk_overlap: 1)

    assert Enum.all?(chunks, &String.valid?(&1.text))
  end
end
