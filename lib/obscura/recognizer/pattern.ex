defmodule Obscura.Recognizer.Pattern do
  @moduledoc """
  Helpers for regex-backed Phase 1 recognizers.
  """

  alias Obscura.Analyzer.Explanation
  alias Obscura.Analyzer.Result
  alias Obscura.Eval.Offset
  alias Obscura.Internal.ResultText

  @type validation_fun :: (String.t() -> :ok | {:ok, map()} | {:error, term()})

  @doc """
  Scans text and returns analyzer results for valid regex matches.
  """
  @spec scan(String.t(), Regex.t(), keyword()) :: [Result.t()]
  def scan(text, regex, opts) do
    entity = Keyword.fetch!(opts, :entity)
    source_entity = Keyword.fetch!(opts, :source_entity)
    recognizer = Keyword.fetch!(opts, :recognizer)
    pattern = Keyword.fetch!(opts, :pattern)
    score = Keyword.fetch!(opts, :score)
    explain? = Keyword.get(opts, :explain, false)
    include_text? = Keyword.get(opts, :include_text, true)
    validate = Keyword.get(opts, :validate, fn _value -> :ok end)

    regex
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [{start, match_length} | _captures] ->
      value = binary_part(text, start, match_length)
      {trimmed_start, trimmed_value} = trim_leading(start, value)
      {final_start, final_value} = trim_trailing(trimmed_start, trimmed_value)
      final_end = final_start + byte_size(final_value)

      build_result(text, final_value, final_start, final_end,
        entity: entity,
        source_entity: source_entity,
        recognizer: recognizer,
        pattern: pattern,
        score: score,
        explain: explain?,
        include_text: include_text?,
        validate: validate
      )
    end)
  end

  defp build_result(_text, "", _start, _end_offset, _opts), do: []

  defp build_result(text, value, start, end_offset, opts) do
    validate = Keyword.fetch!(opts, :validate)

    case validate.(value) do
      :ok ->
        [result(text, value, start, end_offset, opts, :valid, %{})]

      {:ok, metadata} ->
        [result(text, value, start, end_offset, opts, :valid, metadata)]

      {:error, _reason} ->
        []
    end
  end

  defp result(text, value, start, end_offset, opts, validation, metadata) do
    entity = Keyword.fetch!(opts, :entity)
    recognizer = Keyword.fetch!(opts, :recognizer)
    pattern = Keyword.fetch!(opts, :pattern)
    score = Keyword.fetch!(opts, :score)
    explain? = Keyword.fetch!(opts, :explain)

    %Result{
      entity: entity,
      start: start,
      end: end_offset,
      byte_start: start,
      byte_end: end_offset,
      score: score * score_adjustment(text, start, end_offset),
      text:
        ResultText.maybe_materialize(value, include_text: Keyword.fetch!(opts, :include_text)),
      source_entity: Keyword.fetch!(opts, :source_entity),
      recognizer: recognizer,
      explanation: explanation(explain?, recognizer, pattern, score, validation, metadata),
      metadata: metadata
    }
  end

  defp explanation(false, _recognizer, _pattern, _score, _validation, _metadata), do: nil

  defp explanation(true, recognizer, pattern, score, validation, metadata) do
    %Explanation{
      recognizer: recognizer,
      pattern: pattern,
      score: score,
      original_score: score,
      validation: validation,
      context_words: [],
      score_context_delta: 0.0,
      metadata: metadata
    }
  end

  defp score_adjustment(text, start, end_offset) do
    with {:ok, value} <- Offset.slice_bytes(text, start, end_offset),
         true <- byte_size(value) > 0 do
      1.0
    else
      _other -> 0.0
    end
  end

  defp trim_leading(start, value) do
    trimmed = String.trim_leading(value)
    {start + byte_size(value) - byte_size(trimmed), trimmed}
  end

  defp trim_trailing(start, value) do
    trimmed = String.trim_trailing(value)
    trimmed = String.trim_trailing(trimmed, ".,;:")
    trimmed = String.trim_trailing(trimmed, ")")
    {start, trimmed}
  end
end
