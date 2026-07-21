defmodule Obscura.PrivacyFilter.Spans do
  @moduledoc """
  Privacy-filter token label and span reconstruction helpers.
  """

  alias Obscura.Analyzer.Explanation
  alias Obscura.Analyzer.Result
  alias Obscura.PrivacyFilter.DetectedSpan
  alias Obscura.PrivacyFilter.LabelInfo
  alias Obscura.PrivacyFilter.LabelMap
  alias Obscura.Tiktoken.Encoding
  alias Obscura.Tiktoken.Offsets

  @spec decode_text_with_offsets([non_neg_integer()], Encoding.t()) ::
          {:ok, {String.t(), [non_neg_integer()], [non_neg_integer()]}} | {:error, term()}
  def decode_text_with_offsets(token_ids, %Encoding{} = encoding) do
    Offsets.token_char_ranges(token_ids, encoding)
  end

  @spec labels_to_spans(%{non_neg_integer() => non_neg_integer()}, LabelInfo.t()) :: [
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
        ]
  def labels_to_spans(labels_by_index, %LabelInfo{} = label_info) when is_map(labels_by_index) do
    {spans, current_label, start_idx, previous_idx} =
      labels_by_index
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({[], nil, nil, nil}, fn {token_idx, label_id}, acc ->
        consume_label(acc, token_idx, label_id, label_info)
      end)

    spans =
      if not is_nil(current_label) and not is_nil(start_idx) and not is_nil(previous_idx) do
        [{current_label, start_idx, previous_idx + 1} | spans]
      else
        spans
      end

    Enum.reverse(spans)
  end

  @spec token_spans_to_char_spans([{integer(), integer(), integer()}], [integer()], [integer()]) ::
          [{integer(), integer(), integer()}]
  def token_spans_to_char_spans(spans, char_starts, char_ends) do
    Enum.flat_map(spans, &token_span_to_char_span(&1, char_starts, char_ends))
  end

  defp token_span_to_char_span(
         {label_idx, token_start, token_end},
         char_starts,
         char_ends
       )
       when token_start >= 0 and token_start < token_end do
    if token_end <= length(char_starts) do
      char_span(label_idx, Enum.at(char_starts, token_start), Enum.at(char_ends, token_end - 1))
    else
      []
    end
  end

  defp token_span_to_char_span(_span, _char_starts, _char_ends), do: []

  defp char_span(label_idx, char_start, char_end) when char_end > char_start,
    do: [{label_idx, char_start, char_end}]

  defp char_span(_label_idx, _char_start, _char_end), do: []

  @spec trim_char_spans_whitespace([{integer(), integer(), integer()}], String.t()) :: [
          {integer(), integer(), integer()}
        ]
  def trim_char_spans_whitespace(spans, text) when is_list(spans) and is_binary(text) do
    chars = String.graphemes(text)

    Enum.flat_map(spans, fn {label_idx, start, ending} ->
      {trimmed_start, trimmed_end} = trim_span(chars, start, ending)

      if trimmed_end > trimmed_start,
        do: [{label_idx, trimmed_start, trimmed_end}],
        else: []
    end)
  end

  @spec discard_overlapping_spans_by_label([{integer(), integer(), integer()}]) :: [
          {integer(), integer(), integer()}
        ]
  def discard_overlapping_spans_by_label(spans) do
    spans
    |> Enum.group_by(fn {label_idx, _start, _ending} -> label_idx end)
    |> Enum.flat_map(&keep_non_overlapping_label_spans/1)
    |> Enum.sort_by(fn {label_idx, start, ending} -> {start, ending, label_idx} end)
  end

  defp keep_non_overlapping_label_spans({label_idx, label_spans}) do
    label_spans
    |> Enum.sort_by(fn {_label, start, ending} -> {start, -(ending - start)} end)
    |> Enum.reduce([], &keep_span(&1, &2, label_idx))
  end

  defp keep_span({_label, start, ending}, kept, label_idx) do
    if Enum.any?(kept, &overlap?(&1, start, ending)),
      do: kept,
      else: [{label_idx, start, ending} | kept]
  end

  defp overlap?({_label, kept_start, kept_end}, start, ending),
    do: start < kept_end and ending > kept_start

  @spec char_spans_to_detected_spans(
          [{integer(), integer(), integer()}],
          String.t(),
          LabelInfo.t(),
          keyword()
        ) :: {:ok, [DetectedSpan.t()]} | {:error, term()}
  def char_spans_to_detected_spans(spans, text, %LabelInfo{} = label_info, opts \\ []) do
    spans
    |> Enum.reduce_while({:ok, []}, fn {label_idx, start, ending}, {:ok, acc} ->
      label = Enum.at(label_info.span_class_names, label_idx)

      case label_to_detected_span(label, start, ending, text, opts) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, span} -> {:cont, {:ok, [span | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, spans} -> {:ok, Enum.reverse(spans)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec to_results([DetectedSpan.t()]) :: [Result.t()]
  def to_results(spans) when is_list(spans) do
    Enum.map(spans, fn %DetectedSpan{} = span ->
      score = span.score || 1.0

      %Result{
        entity: span.entity,
        start: span.byte_start,
        end: span.byte_end,
        byte_start: span.byte_start,
        byte_end: span.byte_end,
        score: score,
        text: span.text,
        source_entity: span.label,
        recognizer: :privacy_filter_native,
        explanation: %Explanation{
          recognizer: :privacy_filter_native,
          pattern: :privacy_filter_span,
          original_score: score,
          score: score,
          metadata: span.metadata
        },
        metadata: span.metadata
      }
    end)
  end

  defp consume_label(
         {spans, current_label, start_idx, previous_idx},
         token_idx,
         label_id,
         label_info
       ) do
    span_label = Map.get(label_info.token_to_span_label, label_id)
    boundary_tag = Map.get(label_info.token_boundary_tags, label_id)

    {spans, current_label, start_idx} =
      close_discontinuous_span(
        {spans, current_label, start_idx},
        token_idx,
        previous_idx
      )

    consume_boundary(
      {spans, current_label, start_idx, previous_idx},
      token_idx,
      span_label,
      boundary_tag,
      label_info.background_span_label
    )
  end

  defp close_discontinuous_span(state, _token_idx, nil), do: state

  defp close_discontinuous_span({spans, current, start} = state, token_idx, previous_idx) do
    if token_idx == previous_idx + 1 do
      state
    else
      {close_current(spans, current, start, previous_idx + 1), nil, nil}
    end
  end

  defp consume_boundary({spans, current, start, _previous}, token_idx, nil, _tag, _background),
    do: {spans, current, start, token_idx}

  defp consume_boundary(
         {spans, current, start, _previous},
         token_idx,
         span_label,
         _tag,
         background
       )
       when span_label == background do
    {close_current(spans, current, start, token_idx), nil, nil, token_idx}
  end

  defp consume_boundary(
         {spans, current, start, previous},
         token_idx,
         span_label,
         "S",
         _background
       ) do
    spans = close_current(spans, current, start, previous_end(previous, token_idx))
    {[{span_label, token_idx, token_idx + 1} | spans], nil, nil, token_idx}
  end

  defp consume_boundary(
         {spans, current, start, previous},
         token_idx,
         span_label,
         "B",
         _background
       ) do
    spans = close_current(spans, current, start, previous_end(previous, token_idx))
    {spans, span_label, token_idx, token_idx}
  end

  defp consume_boundary(
         {spans, span_label, start, _previous},
         token_idx,
         span_label,
         "I",
         _background
       ),
       do: {spans, span_label, start, token_idx}

  defp consume_boundary(
         {spans, current, start, previous},
         token_idx,
         span_label,
         "I",
         _background
       ) do
    spans = close_current(spans, current, start, previous_end(previous, token_idx))
    {spans, span_label, token_idx, token_idx}
  end

  defp consume_boundary(
         {spans, span_label, start, _previous},
         token_idx,
         span_label,
         "E",
         _background
       )
       when not is_nil(start) do
    {[{span_label, start, token_idx + 1} | spans], nil, nil, token_idx}
  end

  defp consume_boundary(
         {spans, current, start, previous},
         token_idx,
         span_label,
         "E",
         _background
       ) do
    spans = close_current(spans, current, start, previous_end(previous, token_idx))
    {[{span_label, token_idx, token_idx + 1} | spans], nil, nil, token_idx}
  end

  defp consume_boundary(
         {spans, _current, _start, _previous},
         token_idx,
         _label,
         _tag,
         _background
       ),
       do: {spans, nil, nil, token_idx}

  defp close_current(spans, nil, _start, _ending), do: spans
  defp close_current(spans, _current, nil, _ending), do: spans
  defp close_current(spans, current, start, ending), do: [{current, start, ending} | spans]

  defp previous_end(nil, token_idx), do: token_idx
  defp previous_end(previous_idx, _token_idx), do: previous_idx + 1

  defp label_to_detected_span(nil, _start, _ending, _text, _opts), do: {:ok, nil}

  defp label_to_detected_span(label, start, ending, text, opts) do
    case LabelMap.map_label(label, opts) do
      :ignore ->
        {:ok, nil}

      {:ok, entity} ->
        with {:ok, {byte_start, byte_end}} <- Offsets.char_span_to_byte_span(text, start, ending) do
          metadata =
            opts
            |> Keyword.get(:metadata, %{})
            |> Map.merge(%{
              raw_label: label,
              model_label: label,
              mapped_entity: entity,
              char_start: start,
              char_end: ending
            })

          {:ok,
           %DetectedSpan{
             label: label,
             entity: entity,
             start: start,
             end: ending,
             byte_start: byte_start,
             byte_end: byte_end,
             text: char_slice(text, start, ending),
             placeholder: placeholder(label),
             score: Keyword.get(opts, :score, 1.0),
             metadata: metadata
           }}
        end
    end
  end

  defp trim_span(chars, start, ending) do
    {start, ending} = trim_leading(chars, start, ending)
    trim_trailing(chars, start, ending)
  end

  defp trim_leading(chars, start, ending) do
    if start < ending and chars |> Enum.at(start) |> whitespace?(),
      do: trim_leading(chars, start + 1, ending),
      else: {start, ending}
  end

  defp trim_trailing(chars, start, ending) do
    if ending > start and chars |> Enum.at(ending - 1) |> whitespace?(),
      do: trim_trailing(chars, start, ending - 1),
      else: {start, ending}
  end

  defp whitespace?(char), do: is_binary(char) and String.trim(char) == ""

  defp char_slice(text, start, ending) do
    text
    |> String.graphemes()
    |> Enum.slice(start, ending - start)
    |> Enum.join()
  end

  defp placeholder(label) do
    normalized =
      label
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]+/, "_")
      |> String.trim("_")

    "<#{if normalized == "", do: "REDACTED", else: normalized}>"
  end
end
