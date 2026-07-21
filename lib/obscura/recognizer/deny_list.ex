defmodule Obscura.Recognizer.DenyList do
  @moduledoc """
  Data-backed deny-list recognizer.
  """

  alias Obscura.Analyzer.Explanation
  alias Obscura.Analyzer.Result

  @doc """
  Runs configured deny lists against text.
  """
  @spec analyze(String.t(), [map()], keyword()) :: [Result.t()]
  def analyze(text, deny_lists, opts) when is_binary(text) and is_list(deny_lists) do
    Enum.flat_map(deny_lists, &analyze_entry(text, &1, opts))
  end

  @doc """
  Returns entities covered by configured deny lists.
  """
  @spec supported_entities([map()]) :: [atom()]
  def supported_entities(deny_lists) when is_list(deny_lists) do
    deny_lists
    |> Enum.map(&Map.get(&1, :entity))
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end

  defp analyze_entry(text, %{entity: entity, values: values} = entry, opts)
       when is_atom(entity) and is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&matches(text, &1, entry, opts))
  end

  defp analyze_entry(_text, _entry, _opts), do: []

  defp matches(text, value, entry, opts) do
    search_text = comparable(text, entry)
    search_value = comparable(value, entry)

    offsets(search_text, search_value, 0, [])
    |> Enum.map(&result(text, value, &1, entry, opts))
  end

  defp comparable(value, entry) do
    value =
      if Map.get(entry, :case_sensitive, true) do
        value
      else
        String.downcase(value)
      end

    if Map.get(entry, :normalize_whitespace, false) do
      String.replace(value, ~r/\s+/, " ")
    else
      value
    end
  end

  defp offsets(_text, "", _cursor, acc), do: Enum.reverse(acc)

  defp offsets(text, value, cursor, acc) do
    case :binary.match(text, value, scope: {cursor, byte_size(text) - cursor}) do
      {start, length} -> offsets(text, value, start + max(length, 1), [start | acc])
      :nomatch -> Enum.reverse(acc)
    end
  end

  defp result(text, value, start, entry, opts) do
    end_offset = start + byte_size(value)
    entity = Map.fetch!(entry, :entity)
    score = Map.get(entry, :score, 0.95)
    name = Map.get(entry, :name, :deny_list)
    explain? = Keyword.get(opts, :explain, false)

    %Result{
      entity: entity,
      start: start,
      end: end_offset,
      byte_start: start,
      byte_end: end_offset,
      score: score,
      text: binary_part(text, start, byte_size(value)),
      source_entity: Atom.to_string(entity),
      recognizer: name,
      explanation: explanation(explain?, name, score),
      metadata: %{deny_list: true, context_words: Map.get(entry, :context, [])}
    }
  end

  defp explanation(false, _name, _score), do: nil

  defp explanation(true, name, score) do
    %Explanation{
      recognizer: name,
      pattern: :deny_list,
      score: score,
      original_score: score,
      validation: :valid,
      metadata: %{deny_list: true}
    }
  end
end
