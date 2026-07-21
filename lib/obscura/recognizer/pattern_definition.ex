defmodule Obscura.Recognizer.PatternDefinition do
  @moduledoc """
  Data-backed custom pattern recognizer definition.
  """

  alias Obscura.Analyzer.Explanation
  alias Obscura.Analyzer.Result
  alias Obscura.Eval.Offset

  @enforce_keys [:name, :entity, :patterns]
  defstruct [:name, :entity, :patterns, :validate, :invalidate, context: [], metadata: %{}]

  @type pattern :: %{
          required(:name) => atom(),
          required(:regex) => Regex.t(),
          required(:score) => float()
        }
  @type t :: %__MODULE__{
          name: atom(),
          entity: atom(),
          patterns: [pattern()],
          validate: (String.t() -> term()) | nil,
          invalidate: (String.t() -> term()) | nil,
          context: [String.t()],
          metadata: map()
        }

  @doc """
  Builds a pattern definition or raises for invalid input.
  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    definition = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      entity: Keyword.fetch!(opts, :entity),
      patterns: Keyword.fetch!(opts, :patterns),
      validate: Keyword.get(opts, :validate),
      invalidate: Keyword.get(opts, :invalidate),
      context: List.wrap(Keyword.get(opts, :context, [])),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    case validate_definition(definition) do
      :ok -> definition
      {:error, reason} -> raise ArgumentError, "invalid pattern definition: #{inspect(reason)}"
    end
  end

  @doc false
  @spec analyze(t(), String.t(), keyword()) :: [Result.t()]
  def analyze(%__MODULE__{} = definition, text, opts) when is_binary(text) do
    Enum.flat_map(definition.patterns, fn pattern ->
      scan_pattern(definition, pattern, text, opts)
    end)
  end

  @doc false
  @spec supported_entities(t()) :: [atom()]
  def supported_entities(%__MODULE__{entity: entity}), do: [entity]

  defp validate_definition(%__MODULE__{} = definition) do
    cond do
      not is_atom(definition.name) -> {:error, :invalid_name}
      not is_atom(definition.entity) -> {:error, :invalid_entity}
      not is_list(definition.patterns) -> {:error, :invalid_patterns}
      not Enum.all?(definition.patterns, &valid_pattern?/1) -> {:error, :invalid_pattern}
      not Enum.all?(definition.context, &is_binary/1) -> {:error, :invalid_context}
      true -> :ok
    end
  end

  defp valid_pattern?(%{name: name, regex: %Regex{}, score: score})
       when is_atom(name) and is_number(score),
       do: true

  defp valid_pattern?(_pattern), do: false

  defp scan_pattern(definition, pattern, text, opts) do
    pattern.regex
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [{start, match_length} | _captures] ->
      value = binary_part(text, start, match_length)

      case validation_result(definition, pattern, value) do
        {:ok, score, validation, metadata} ->
          [
            result(%{
              definition: definition,
              pattern: pattern,
              text: text,
              start: start,
              end_offset: start + byte_size(value),
              value: value,
              score: score,
              validation: validation,
              validation_metadata: metadata,
              opts: opts
            })
          ]

        :drop ->
          []
      end
    end)
  end

  defp validation_result(definition, pattern, value) do
    invalidate = callback_result(definition.invalidate, value, false)

    if invalid?(invalidate) do
      invalid_pattern_result(pattern)
    else
      validate = callback_result(definition.validate, value, true)
      valid_pattern_result(pattern, validate)
    end
  end

  defp callback_result(nil, _value, default), do: default

  defp callback_result(fun, value, _default) when is_function(fun, 1) do
    fun.(value)
  rescue
    _error -> :callback_failed
  catch
    _kind, _reason -> :callback_failed
  end

  defp invalid?(true), do: true
  defp invalid?(:invalid), do: true
  defp invalid?({:invalid, _metadata}), do: true
  defp invalid?({:error, _reason}), do: true
  defp invalid?(_result), do: false

  defp invalid_pattern_result(%{invalid_score: invalid_score} = pattern)
       when is_number(invalid_score) and invalid_score > 0.0 do
    {:ok, invalid_score, :invalid, pattern_metadata(pattern, %{validation: :invalid})}
  end

  defp invalid_pattern_result(_pattern), do: :drop

  defp valid_pattern_result(pattern, result) do
    cond do
      result in [false, :invalid] ->
        :drop

      result in [true, :ok, :valid] ->
        {:ok, pattern.score, :valid, pattern_metadata(pattern, %{})}

      match?({:ok, _metadata}, result) ->
        {:ok, pattern.score, :valid, pattern_metadata(pattern, elem(result, 1))}

      match?({:score, score} when is_number(score), result) ->
        {:score, score} = result
        {:ok, score, :valid, pattern_metadata(pattern, %{validation_score: score})}

      match?({:ok, score, _metadata} when is_number(score), result) ->
        {:ok, score, metadata} = result
        {:ok, score, :valid, pattern_metadata(pattern, metadata)}

      true ->
        :drop
    end
  end

  defp pattern_metadata(pattern, metadata) do
    pattern
    |> Map.take([:requires_context, :context_min_score, :weak])
    |> Map.merge(metadata)
  end

  defp result(%{
         definition: definition,
         pattern: pattern,
         text: text,
         start: start,
         end_offset: end_offset,
         value: value,
         score: score,
         validation: validation,
         validation_metadata: validation_metadata,
         opts: opts
       }) do
    {:ok, char_start} = Offset.byte_to_char(text, start)
    {:ok, char_end} = Offset.byte_to_char(text, end_offset)
    explain? = Keyword.get(opts, :explain, false)

    %Result{
      entity: definition.entity,
      start: start,
      end: end_offset,
      byte_start: start,
      byte_end: end_offset,
      score: score,
      text: value,
      source_entity: Atom.to_string(definition.entity),
      recognizer: definition.name,
      explanation:
        explanation(explain?, definition, pattern, score, validation, validation_metadata),
      metadata:
        Map.merge(definition.metadata, %{
          context_words: definition.context,
          char_start: char_start,
          char_end: char_end
        })
        |> Map.merge(validation_metadata)
    }
  end

  defp explanation(false, _definition, _pattern, _score, _validation, _metadata), do: nil

  defp explanation(true, definition, pattern, score, validation, metadata) do
    %Explanation{
      recognizer: definition.name,
      pattern: pattern.name,
      score: score,
      original_score: score,
      validation: validation,
      context_words: [],
      score_context_delta: 0.0,
      metadata: Map.merge(%{custom: true}, metadata)
    }
  end
end
