defmodule Obscura.Rehydrator.Structured do
  @moduledoc """
  Structured data rehydration for vault tokens.
  """

  alias Obscura.Rehydrator

  @opaque_structs [Date, Time, NaiveDateTime, DateTime, URI, Regex, MapSet, Range]

  @doc """
  Rehydrates binary leaf values in supported structured data.
  """
  @spec rehydrate(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def rehydrate(data, opts \\ []) when is_list(opts) do
    walk(data, opts)
  end

  defp walk(value, opts) when is_binary(value), do: Rehydrator.rehydrate(value, opts)

  defp walk(value, opts) when is_list(value) do
    if Keyword.keyword?(value) do
      walk_keyword(value, opts)
    else
      walk_list(value, opts)
    end
  end

  defp walk(%module{} = value, opts) do
    cond do
      module in @opaque_structs ->
        {:ok, value}

      Keyword.get(opts, :traverse_structs, true) ->
        with {:ok, rehydrated} <- walk_map(Map.from_struct(value), opts) do
          preserve_struct(value, rehydrated, opts)
        end

      true ->
        {:ok, value}
    end
  end

  defp walk(value, opts) when is_map(value), do: walk_map(value, opts)
  defp walk(value, _opts), do: {:ok, value}

  defp preserve_struct(value, rehydrated, opts) do
    if Keyword.get(opts, :preserve_structs, true) do
      {:ok, struct(value.__struct__, rehydrated)}
    else
      {:ok, rehydrated}
    end
  end

  defp walk_list(list, opts) do
    list
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case walk(value, opts) do
        {:ok, rehydrated} -> {:cont, {:ok, acc ++ [rehydrated]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp walk_keyword(keyword, opts) do
    keyword
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case walk(value, opts) do
        {:ok, rehydrated} -> {:cont, {:ok, acc ++ [{key, rehydrated}]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp walk_map(map, opts) do
    map
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case walk(value, opts) do
        {:ok, rehydrated} -> {:cont, {:ok, Map.put(acc, key, rehydrated)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
