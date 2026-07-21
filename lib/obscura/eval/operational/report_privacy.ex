defmodule Obscura.Eval.Operational.ReportPrivacy do
  @moduledoc false

  @spec find_sensitive_key(term(), [String.t()]) :: String.t() | nil
  def find_sensitive_key(term, sensitive_keys) do
    find(term, MapSet.new(sensitive_keys))
  end

  @spec drop_keys(term(), [String.t()]) :: term()
  def drop_keys(term, keys) do
    drop(term, MapSet.new(keys))
  end

  defp find(map, sensitive_keys) when is_map(map) do
    Enum.find_value(map, fn {key, value} ->
      key_string = to_string(key)

      if MapSet.member?(sensitive_keys, key_string),
        do: key_string,
        else: find(value, sensitive_keys)
    end)
  end

  defp find(list, sensitive_keys) when is_list(list),
    do: Enum.find_value(list, &find(&1, sensitive_keys))

  defp find(_value, _sensitive_keys), do: nil

  defp drop(map, keys) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, drop(value, keys)} end)
    |> Map.reject(fn {key, _value} -> MapSet.member?(keys, to_string(key)) end)
  end

  defp drop(list, keys) when is_list(list), do: Enum.map(list, &drop(&1, keys))
  defp drop(value, _keys), do: value
end
