defmodule Obscura.Conflict do
  @moduledoc """
  Deterministic overlap resolution for analyzer results and anonymizer spans.
  """

  @doc """
  Resolves overlapping spans.
  """
  @spec resolve([map() | struct()], atom()) :: [map() | struct()]
  def resolve(spans, :none), do: sort(spans)
  def resolve(spans, false), do: sort(spans)

  def resolve(spans, strategy) when strategy in [:aggressive, :prefer_longer] do
    spans
    |> Enum.sort_by(&{-span_length(&1), -score(&1), start(&1), end_offset(&1), entity(&1)})
    |> keep_non_overlapping([], false)
    |> maybe_tag_policy(:prefer_longer, %{})
  end

  def resolve(spans, :prefer_higher_confidence) do
    spans
    |> Enum.sort_by(&{-score(&1), -span_length(&1), start(&1), end_offset(&1), entity(&1)})
    |> keep_non_overlapping([], false)
    |> maybe_tag_policy(:prefer_higher_confidence, %{})
  end

  def resolve(spans, _strategy) do
    resolved =
      spans
      |> remove_model_overlaps_with_structured()
      |> remove_exact_duplicates()
      |> remove_contained_same_entity()
      |> sort()

    if length(resolved) == length(spans) do
      resolved
    else
      tag_policy(resolved, :presidio_like, %{
        conflict_dropped_count: length(spans) - length(resolved),
        conflict_reason: :exact_duplicate_contained_or_structured_precedence
      })
    end
  end

  @spec overlaps?(map() | struct(), map() | struct()) :: boolean()
  def overlaps?(left, right),
    do: start(left) < end_offset(right) and start(right) < end_offset(left)

  defp keep_non_overlapping([], kept, dropped?), do: {sort(kept), dropped?}

  defp keep_non_overlapping([span | rest], kept, dropped?) do
    if Enum.any?(kept, &overlaps?(span, &1)) do
      keep_non_overlapping(rest, kept, true)
    else
      keep_non_overlapping(rest, [span | kept], dropped?)
    end
  end

  defp remove_exact_duplicates(spans) do
    spans
    |> Enum.sort_by(&{-score(&1), -span_length(&1), start(&1), end_offset(&1), entity(&1)})
    |> Enum.uniq_by(&{start(&1), end_offset(&1), entity(&1)})
  end

  defp remove_contained_same_entity(spans) do
    spans
    |> Enum.sort_by(&{-score(&1), -span_length(&1), start(&1), end_offset(&1), entity(&1)})
    |> Enum.reduce([], fn span, kept ->
      if Enum.any?(kept, &contained_same_entity?(span, &1)) do
        kept
      else
        [span | Enum.reject(kept, &contained_same_entity?(&1, span))]
      end
    end)
    |> Enum.reverse()
  end

  defp remove_model_overlaps_with_structured(spans) do
    structured = Enum.filter(spans, &structured_deterministic?/1)

    Enum.reject(spans, fn span ->
      model_span?(span) and Enum.any?(structured, &overlaps?(span, &1))
    end)
  end

  defp contained_same_entity?(left, right) do
    entity(left) == entity(right) and start(left) >= start(right) and
      end_offset(left) <= end_offset(right) and
      {start(left), end_offset(left)} != {start(right), end_offset(right)}
  end

  defp sort(spans), do: Enum.sort_by(spans, &{start(&1), end_offset(&1), entity(&1)})

  defp start(span), do: Map.get(span, :start, Map.get(span, :byte_start))
  defp end_offset(span), do: Map.get(span, :end, Map.get(span, :byte_end))
  defp score(span), do: Map.get(span, :score, 1.0) || 1.0
  defp span_length(span), do: end_offset(span) - start(span)
  defp entity(span), do: Map.get(span, :entity)

  defp structured_deterministic?(span) do
    entity(span) in [:email, :phone, :credit_card, :iban, :us_ssn, :ip_address, :domain, :url] and
      Map.get(span, :recognizer) != :ner and
      not Map.has_key?(metadata(span), :model_label)
  end

  defp model_span?(span), do: Map.has_key?(metadata(span), :model_label)

  defp metadata(span), do: Map.get(span, :metadata, %{}) || %{}

  defp maybe_tag_policy({spans, false}, _policy, _metadata), do: spans

  defp maybe_tag_policy({spans, true}, policy, metadata) do
    tag_policy(spans, policy, metadata)
  end

  defp tag_policy(spans, policy, extra_metadata) do
    Enum.map(spans, fn span ->
      Map.update(span, :metadata, %{conflict_policy: policy}, fn metadata ->
        metadata
        |> Kernel.||(%{})
        |> Map.put_new(:conflict_policy, policy)
        |> Map.merge(extra_metadata)
      end)
    end)
  end
end
