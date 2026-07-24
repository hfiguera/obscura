defmodule Obscura.Context do
  @moduledoc """
  Simple token-window context score enhancement.
  """

  alias Obscura.Analyzer.Explanation
  alias Obscura.Context.Policy
  alias Obscura.Context.Window
  alias Obscura.NLP.Artifacts

  @doc """
  Enhances analyzer result scores when configured context words appear nearby.
  """
  @spec enhance([Obscura.Analyzer.Result.t()], String.t(), Obscura.Analyzer.Options.t()) ::
          [Obscura.Analyzer.Result.t()]
  def enhance(results, _text, %{context: [], profile: :regex_only}), do: results
  def enhance([], _text, _options), do: []

  def enhance(results, text, options) do
    if context_disabled?(options) do
      results
    else
      policy_results = Enum.map(results, &Policy.apply(&1, options.context_policies))

      if context_matching_required?(policy_results, options) do
        artifacts = Map.get(options, :nlp_artifacts) || Artifacts.build(text)

        Enum.map(policy_results, fn result ->
          enhance_result(result, text, artifacts, options)
        end)
      else
        policy_results
      end
    end
  end

  @doc """
  Returns true when a result is acceptable after context enhancement.
  """
  @spec accepted?(map()) :: boolean()
  def accepted?(%{metadata: %{negative_context_matched: true, negative_context_reject: true}}),
    do: false

  def accepted?(%{metadata: %{requires_context: true, context_matched: true}}), do: true
  def accepted?(%{metadata: %{requires_context: true}}), do: false
  def accepted?(_result), do: true

  defp context_disabled?(options) do
    options.context == [] and options.context_boost == 0.0 and
      options.context_policies in [%{}, []]
  end

  defp context_matching_required?(results, options) do
    options.context != [] or Enum.any?(results, &result_has_context_words?/1)
  end

  defp result_has_context_words?(result) do
    metadata = result.metadata || %{}

    Map.get(metadata, :context_words, []) != [] or
      Map.get(metadata, :negative_context_words, []) != []
  end

  defp enhance_result(result, text, artifacts, options) do
    context_words = context_words(result, options.context)
    window = Window.around(text, result.start, result.end, options.context_window)
    negative_matched = matched_negative_words(window, artifacts, result, options)
    matched = matched_words(window, artifacts, result, context_words, options)

    result = apply_negative_context(result, negative_matched)

    if matched == [] do
      result
    else
      apply_boost(
        result,
        matched,
        options.context_boost,
        options.context_min_score,
        options.context_window
      )
    end
  end

  defp context_words(result, user_context) do
    result.metadata
    |> Map.get(:context_words, [])
    |> Kernel.++(user_context)
    |> Enum.map(&to_string/1)
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp matched_words(_window, _artifacts, _result, [], _options), do: []

  defp matched_words(window, _artifacts, _result, words, %{context_match: :substring}) do
    matched_substring_words(window, words)
  end

  defp matched_words(window, artifacts, result, words, options) do
    terms =
      Artifacts.surrounding_terms(artifacts, result.start, result.end,
        prefix_count: options.context_prefix_count,
        suffix_count: options.context_suffix_count
      )

    words
    |> Enum.filter(&whole_word_match?(&1, terms))
    |> case do
      [] -> matched_substring_words(window, words)
      matched -> matched
    end
  end

  defp matched_negative_words(window, artifacts, result, options) do
    words =
      result.metadata
      |> Map.get(:negative_context_words, [])
      |> Enum.map(&to_string/1)
      |> Enum.uniq_by(&String.downcase/1)

    matched_words(window, artifacts, result, words, options)
  end

  defp matched_substring_words(window, words) do
    downcased_window = String.downcase(window)

    Enum.filter(words, fn word ->
      String.contains?(downcased_window, String.downcase(word))
    end)
  end

  defp whole_word_match?(word, terms) do
    word_terms =
      word
      |> Artifacts.build()
      |> Map.fetch!(:normalized_tokens)
      |> Enum.reject(&(&1 == ""))

    cond do
      word_terms == [] -> false
      match?([_term], word_terms) -> hd(word_terms) in terms
      true -> phrase_match?(word_terms, terms)
    end
  end

  defp phrase_match?(phrase_terms, terms) do
    phrase_length = length(phrase_terms)

    terms
    |> Enum.chunk_every(phrase_length, 1, :discard)
    |> Enum.any?(&(&1 == phrase_terms))
  end

  defp apply_boost(result, matched, boost, minimum_score, window) do
    if weak_context_only?(result, matched) do
      apply_weak_context(result, matched)
    else
      apply_strong_context(result, matched, boost, minimum_score, window)
    end
  end

  defp apply_negative_context(result, []), do: result

  defp apply_negative_context(result, matched) do
    metadata =
      result.metadata
      |> Map.put(:negative_context_matched, true)
      |> Map.put(:negative_context_words, matched)
      |> Map.put(:context_strength, :negative)
      |> Map.put(:supportive_context_word, hd(matched))
      |> Map.put_new(:context_source, :nlp_artifacts)

    %{result | metadata: metadata}
  end

  defp apply_strong_context(result, matched, boost, minimum_score, window) do
    original_score = result.score
    score = min(max(original_score + boost, context_min_score(result, minimum_score)), 1.0)
    delta = score - original_score

    metadata =
      result.metadata
      |> Map.put(:context_words, matched)
      |> Map.put(:context_matched, true)
      |> Map.put(:context_strength, :strong)
      |> Map.put(:supportive_context_word, hd(matched))
      |> Map.put(:context_score_delta, delta)

    %{
      result
      | score: score,
        metadata: metadata,
        explanation:
          explanation(result.explanation, result, score, original_score, delta, matched, window)
    }
  end

  defp weak_context_only?(result, matched) do
    weak_words =
      result.metadata
      |> Map.get(:weak_context_words, [])
      |> Enum.map(&String.downcase(to_string(&1)))
      |> MapSet.new()

    MapSet.size(weak_words) > 0 and
      Enum.all?(matched, &(String.downcase(to_string(&1)) in weak_words))
  end

  defp apply_weak_context(result, matched) do
    metadata =
      result.metadata
      |> Map.put(:weak_context_matched, true)
      |> Map.put(:context_strength, :weak)
      |> Map.put(:supportive_context_word, hd(matched))

    %{result | metadata: metadata}
  end

  defp context_min_score(result, minimum_score) do
    result.metadata
    |> Map.get(:context_min_score, minimum_score)
    |> max(0.0)
  end

  defp explanation(nil, _result, _score, _original_score, _delta, _matched, _window), do: nil

  defp explanation(
         %Explanation{} = explanation,
         _result,
         score,
         original_score,
         delta,
         matched,
         window
       ) do
    %{
      explanation
      | score: score,
        original_score: original_score,
        context_words: matched,
        score_context_delta: delta,
        metadata: Map.put(explanation.metadata || %{}, :context_window, window)
    }
  end
end
