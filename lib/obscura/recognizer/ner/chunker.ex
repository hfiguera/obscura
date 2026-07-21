defmodule Obscura.Recognizer.NER.Chunker do
  @moduledoc """
  Presidio-style character chunking for local NER model inference.

  Chunks are byte-addressed and prefer token boundaries so model predictions can
  be shifted back to original text offsets after overlapped inference.
  """

  alias Obscura.NLP.Artifacts

  @type chunk :: %{
          index: non_neg_integer(),
          text: String.t(),
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          character_start: non_neg_integer(),
          character_end: non_neg_integer()
        }

  @doc """
  Splits text into byte-positioned chunks.
  """
  @spec chunks(String.t(), keyword()) :: {:ok, [chunk()]} | {:error, term()}
  def chunks(text, opts) when is_binary(text) and is_list(opts) do
    chunk_size = Keyword.get(opts, :model_chunk_size, 400)
    overlap = Keyword.get(opts, :model_chunk_overlap, 40)

    with :ok <- validate_size(chunk_size),
         :ok <- validate_overlap(overlap, chunk_size) do
      {:ok, build_chunks(text, chunk_size, overlap)}
    end
  end

  @doc """
  Shifts chunk-relative model outputs to original text offsets.
  """
  @spec absolute_outputs(chunk(), [map()], keyword()) :: [map()]
  def absolute_outputs(chunk, outputs, opts) when is_list(outputs) do
    overlap = Keyword.get(opts, :model_chunk_overlap, 40)
    chunk_size = Keyword.get(opts, :model_chunk_size, 400)

    Enum.map(outputs, fn output ->
      offset_unit = Map.get(output, :offset_unit, :byte)
      shift = if offset_unit == :character, do: chunk.character_start, else: chunk.byte_start

      output
      |> shift_output(:start, shift)
      |> shift_output(:end, shift)
      |> Map.put(:model_chunking, :character)
      |> Map.put(:model_chunk_index, chunk.index)
      |> Map.put(:model_chunk_byte_start, chunk.byte_start)
      |> Map.put(:model_chunk_byte_end, chunk.byte_end)
      |> Map.put(:model_chunk_character_start, chunk.character_start)
      |> Map.put(:model_chunk_character_end, chunk.character_end)
      |> Map.put(:model_chunk_size, chunk_size)
      |> Map.put(:model_chunk_overlap, overlap)
    end)
  end

  @doc """
  Removes duplicate outputs introduced by overlapping chunks.
  """
  @spec dedupe_outputs([map()]) :: [map()]
  def dedupe_outputs(outputs) when is_list(outputs) do
    outputs
    |> Enum.reduce(%{}, fn output, acc ->
      key = {Map.get(output, :label), Map.get(output, :start), Map.get(output, :end)}

      Map.update(acc, key, output, &higher_scored_output(output, &1))
    end)
    |> Map.values()
    |> Enum.sort_by(fn output -> {Map.get(output, :start, 0), Map.get(output, :end, 0)} end)
  end

  defp higher_scored_output(output, existing) do
    if score(output) > score(existing), do: output, else: existing
  end

  defp validate_size(size) when is_integer(size) and size > 0, do: :ok
  defp validate_size(_size), do: {:error, :invalid_model_chunk_size}

  defp validate_overlap(overlap, size)
       when is_integer(overlap) and overlap >= 0 and overlap < size,
       do: :ok

  defp validate_overlap(_overlap, _size), do: {:error, :invalid_model_chunk_overlap}

  defp build_chunks(text, chunk_size, overlap) do
    total_bytes = byte_size(text)

    if total_bytes <= chunk_size do
      [chunk(text, 0, total_bytes, 0)]
    else
      artifacts = Artifacts.build(text)
      do_build_chunks(text, artifacts.token_offsets, chunk_size, overlap, 0, 0, [])
    end
  end

  defp do_build_chunks(text, token_offsets, chunk_size, overlap, start_byte, index, acc) do
    total_bytes = byte_size(text)

    finish_byte =
      chunk_end(text, token_offsets, start_byte, min(start_byte + chunk_size, total_bytes))

    current = chunk(text, start_byte, finish_byte, index)

    cond do
      finish_byte >= total_bytes ->
        Enum.reverse([current | acc])

      finish_byte <= start_byte ->
        Enum.reverse([current | acc])

      true ->
        next_start = next_start(text, token_offsets, start_byte, finish_byte, overlap)

        do_build_chunks(text, token_offsets, chunk_size, overlap, next_start, index + 1, [
          current | acc
        ])
    end
  end

  defp chunk_end(text, token_offsets, start_byte, desired_end) do
    token_offsets
    |> Enum.filter(&(&1.byte_start >= start_byte and &1.byte_end <= desired_end))
    |> Enum.map(& &1.byte_end)
    |> Enum.max(fn -> safe_boundary(text, desired_end) end)
  end

  defp next_start(text, token_offsets, previous_start, previous_end, overlap) do
    desired_start = max(0, previous_end - overlap)

    token_offsets
    |> Enum.filter(&(&1.byte_start >= desired_start and &1.byte_start < previous_end))
    |> Enum.map(& &1.byte_start)
    |> Enum.min(fn -> safe_boundary(text, desired_start) end)
    |> max(previous_start + 1)
    |> safe_forward_boundary(text)
  end

  defp safe_boundary(_text, byte) when byte <= 0, do: 0

  defp safe_boundary(text, byte) do
    if byte >= byte_size(text) or String.valid?(binary_part(text, 0, byte)) do
      byte
    else
      safe_boundary(text, byte - 1)
    end
  end

  defp safe_forward_boundary(byte, text) do
    cond do
      byte <= 0 ->
        0

      byte >= byte_size(text) ->
        byte_size(text)

      String.valid?(binary_part(text, 0, byte)) ->
        byte

      true ->
        safe_forward_boundary(byte + 1, text)
    end
  end

  defp chunk(text, byte_start, byte_end, index) do
    text_before = binary_part(text, 0, byte_start)
    text_chunk = binary_part(text, byte_start, byte_end - byte_start)
    character_start = String.length(text_before)

    %{
      index: index,
      text: text_chunk,
      byte_start: byte_start,
      byte_end: byte_end,
      character_start: character_start,
      character_end: character_start + String.length(text_chunk)
    }
  end

  defp shift_output(output, key, shift) do
    case Map.fetch(output, key) do
      {:ok, value} when is_integer(value) -> Map.put(output, key, value + shift)
      _other -> output
    end
  end

  defp score(output), do: Map.get(output, :score, 0.0) || 0.0
end
