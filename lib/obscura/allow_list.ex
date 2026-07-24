defmodule Obscura.AllowList do
  @moduledoc """
  Filters analyzer results that match configured safe values or patterns.
  """

  @doc """
  Removes analyzer results that are present in the allow list.
  """
  @spec filter([Obscura.Analyzer.Result.t()], list() | nil) :: [Obscura.Analyzer.Result.t()]
  def filter(results, nil), do: results
  def filter(results, []), do: results

  def filter(results, allow_list) when is_list(allow_list) do
    Enum.reject(results, &allowed?(&1, allow_list))
  end

  defp allowed?(result, allow_list) do
    Enum.any?(allow_list, &entry_allows?(&1, result))
  end

  defp entry_allows?(%{} = entry, result) do
    entity_matches?(entry, result.entity) and
      (value_allowed?(entry, result.text) or regex_allowed?(entry, result.text))
  end

  defp entity_matches?(entry, entity) do
    case Map.get(entry, :entity) do
      nil -> true
      ^entity -> true
      _other -> false
    end
  end

  defp value_allowed?(entry, value) when is_binary(value) do
    case Map.get(entry, :values) do
      values when is_list(values) ->
        case_sensitive? = Map.get(entry, :case_sensitive, true)
        Enum.any?(values, &same_value?(&1, value, case_sensitive?))

      _values ->
        false
    end
  end

  defp value_allowed?(_entry, _value), do: false

  defp regex_allowed?(entry, value) when is_binary(value) do
    entry
    |> Map.get(:patterns, [])
    |> List.wrap()
    |> Enum.any?(&regex_match?(&1, value))
  end

  defp regex_allowed?(_entry, _value), do: false

  defp same_value?(left, right, true) when is_binary(left), do: left == right

  defp same_value?(left, right, false) when is_binary(left) do
    String.downcase(left) == String.downcase(right)
  end

  defp same_value?(_left, _right, _case_sensitive?), do: false

  defp regex_match?(%Regex{} = regex, value), do: Regex.match?(regex, value)
  defp regex_match?(_regex, _value), do: false
end
