defmodule Obscura.Recognizer.SpanHelpers do
  @moduledoc false

  def prefer_longest(results) do
    results
    |> Enum.sort_by(&{-(&1.end - &1.start), &1.start, &1.end})
    |> Enum.reduce([], fn result, kept ->
      if Enum.any?(kept, &(result.start < &1.end and &1.start < result.end)) do
        kept
      else
        [result | kept]
      end
    end)
    |> Enum.sort_by(&{&1.start, &1.end})
  end

  def invalid_domain_label?(""), do: true
  def invalid_domain_label?(label) when byte_size(label) > 63, do: true

  def invalid_domain_label?(label) do
    String.starts_with?(label, "-") or String.ends_with?(label, "-")
  end
end
