defmodule Obscura.Context.Policy do
  @moduledoc """
  Applies recognizer/entity-specific context policy before global context scoring.
  """

  @type t :: map() | keyword()

  @doc """
  Applies the matching context policy to one analyzer result.
  """
  @spec apply(map(), map() | keyword()) :: map()
  def apply(result, policies) when is_map(result) do
    case policy_for(result, policies) do
      nil -> result
      policy -> apply_policy(result, Map.new(policy))
    end
  end

  defp policy_for(_result, policies) when policies in [%{}, []], do: nil

  defp policy_for(result, policies) when is_list(policies) do
    result
    |> policy_keys()
    |> Enum.find_value(&Keyword.get(policies, &1))
  end

  defp policy_for(result, policies) when is_map(policies) do
    result
    |> policy_keys()
    |> Enum.find_value(&Map.get(policies, &1))
  end

  defp policy_for(_result, _policies), do: nil

  defp policy_keys(result) do
    recognizer = Map.get(result, :recognizer)
    entity = Map.get(result, :entity)

    [
      {recognizer, entity},
      recognizer,
      entity
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp apply_policy(result, policy) do
    result
    |> maybe_add_context_words(policy)
    |> maybe_require_context(policy)
    |> maybe_lower_score(policy)
    |> maybe_reject(policy)
  end

  defp maybe_add_context_words(result, policy) do
    context_words =
      List.wrap(Map.get(policy, :context_words, Map.get(policy, "context_words", [])))

    if context_words == [] do
      result
    else
      metadata =
        (result.metadata || %{})
        |> Map.update(:context_words, context_words, &Enum.uniq(&1 ++ context_words))
        |> maybe_put(
          :context_min_score,
          Map.get(policy, :min_score, Map.get(policy, "min_score"))
        )
        |> Map.put(:context_policy, :context_words)

      %{result | metadata: metadata}
    end
  end

  defp maybe_require_context(result, policy) do
    threshold =
      Map.get(policy, :require_context_below, Map.get(policy, "require_context_below"))

    cond do
      is_nil(threshold) ->
        result

      result.score < threshold ->
        metadata =
          (result.metadata || %{})
          |> Map.put(:requires_context, true)
          |> Map.put(:context_policy, :require_context_below)
          |> Map.put(:context_policy_threshold, threshold)

        %{result | metadata: metadata}

      true ->
        result
    end
  end

  defp maybe_lower_score(result, policy) do
    threshold = Map.get(policy, :lower_below, Map.get(policy, "lower_below"))

    multiplier =
      Map.get(policy, :low_score_multiplier, Map.get(policy, "low_score_multiplier", 1.0))

    if is_number(threshold) and is_number(multiplier) and result.score < threshold do
      score = max(result.score * multiplier, 0.0)

      metadata =
        (result.metadata || %{})
        |> Map.put(:context_policy, :lower_below)
        |> Map.put(:context_policy_threshold, threshold)
        |> Map.put(:context_policy_score_delta, score - result.score)

      %{result | score: score, metadata: metadata}
    else
      result
    end
  end

  defp maybe_reject(result, policy) do
    threshold = Map.get(policy, :reject_below, Map.get(policy, "reject_below"))

    if is_number(threshold) and result.score < threshold do
      metadata =
        (result.metadata || %{})
        |> Map.put(:requires_context, true)
        |> Map.put(:context_policy, :reject_below)
        |> Map.put(:context_policy_threshold, threshold)

      %{result | metadata: metadata}
    else
      result
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
