defmodule Obscura.Recognizer.NER.BumblebeeOutput do
  @moduledoc """
  Converts Bumblebee token-classification output into Obscura model output maps.
  """

  alias Obscura.Recognizer.NER.ModelSpec

  @doc """
  Normalizes one model output value.
  """
  @spec normalize(String.t(), term(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def normalize(text, output, opts \\ [])

  def normalize(text, output, opts) when is_binary(text) and is_list(opts) do
    offset_unit = Keyword.get(opts, :offset_unit, :byte)

    output
    |> entities()
    |> case do
      {:ok, entities} ->
        normalize_entities(
          text,
          entities,
          offset_unit,
          Keyword.get(opts, :strict_phrase_validation, false)
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  def normalize(_text, _output, _opts), do: {:error, :invalid_bumblebee_output}

  @doc """
  Normalizes output using model spec defaults.
  """
  @spec normalize(String.t(), term(), ModelSpec.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def normalize(text, output, %ModelSpec{} = spec, opts) when is_binary(text) and is_list(opts) do
    normalize(text, output, Keyword.put_new(opts, :offset_unit, spec.offset_unit))
  end

  defp entities(%{entities: entities}) when is_list(entities), do: {:ok, entities}
  defp entities(%{"entities" => entities}) when is_list(entities), do: {:ok, entities}
  defp entities(entities) when is_list(entities), do: {:ok, entities}
  defp entities(_output), do: {:error, :invalid_bumblebee_output}

  defp normalize_entities(text, entities, offset_unit, strict_phrase_validation?) do
    Enum.reduce_while(entities, {:ok, []}, fn entity, {:ok, acc} ->
      case normalize_entity(text, entity, offset_unit, strict_phrase_validation?) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_entity(text, entity, offset_unit, strict_phrase_validation?)
       when is_map(entity) do
    with {:ok, label} <- fetch_binary(entity, :label),
         {:ok, start} <- fetch_offset(entity, :start),
         {:ok, finish} <- fetch_offset(entity, :end),
         {:ok, score} <- fetch_score(entity),
         :ok <-
           validate_phrase(text, entity, start, finish, offset_unit, strict_phrase_validation?) do
      {:ok,
       %{
         label: label,
         start: start,
         end: finish,
         offset_unit: offset_unit,
         score: score
       }}
    end
  end

  defp normalize_entity(_text, _entity, _offset_unit, _strict_phrase_validation?),
    do: {:error, :invalid_bumblebee_entity}

  defp fetch_binary(map, key) do
    string_key = Atom.to_string(key)

    case Map.get(map, key, Map.get(map, string_key)) do
      value when is_binary(value) -> {:ok, value}
      _value -> {:error, {:missing_bumblebee_field, key}}
    end
  end

  defp fetch_offset(map, key) do
    string_key = Atom.to_string(key)

    case Map.get(map, key, Map.get(map, string_key)) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _value -> {:error, {:invalid_bumblebee_offset, key}}
    end
  end

  defp fetch_score(map) do
    case Map.get(map, :score, Map.get(map, "score", 1.0)) do
      value when is_number(value) and value >= 0.0 and value <= 1.0 -> {:ok, value / 1}
      _value -> {:error, :invalid_bumblebee_score}
    end
  end

  defp validate_phrase(text, entity, start, finish, :byte, true) do
    phrase = Map.get(entity, :phrase, Map.get(entity, "phrase"))

    cond do
      not is_binary(phrase) ->
        :ok

      finish > byte_size(text) or start > finish ->
        {:error, :bumblebee_phrase_span_out_of_bounds}

      binary_part(text, start, finish - start) == phrase ->
        :ok

      true ->
        {:error, :bumblebee_phrase_mismatch}
    end
  end

  defp validate_phrase(_text, _entity, _start, _finish, _offset_unit, _strict_phrase_validation?),
    do: :ok
end
