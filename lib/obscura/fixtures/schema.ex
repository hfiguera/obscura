defmodule Obscura.Fixtures.Schema do
  @moduledoc """
  Validates neutral Phase 0 analyzer and operator fixtures.
  """

  alias Obscura.Eval.Offset

  @analyzer_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :text,
    :language,
    :entities,
    :expected,
    :should_match,
    :profile,
    :tags,
    :notes,
    :metadata
  ]

  @operator_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :text,
    :spans,
    :operators,
    :expected_text,
    :expected_items,
    :tags,
    :notes,
    :metadata
  ]

  @structured_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :input,
    :opts,
    :expected_data,
    :expected_items,
    :tags,
    :notes,
    :metadata
  ]

  @context_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :text_without_context,
    :text_with_context,
    :entities,
    :expected_entity,
    :expected_value,
    :expected_context_words,
    :assertions,
    :profile,
    :tags,
    :notes,
    :metadata
  ]

  @vault_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :backend,
    :operations,
    :expected_tokens,
    :expected_rehydrated,
    :assertions,
    :tags,
    :notes,
    :metadata
  ]

  @llm_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :messages,
    :opts,
    :expected_messages,
    :response,
    :expected_rehydrated_response,
    :assertions,
    :tags,
    :notes,
    :metadata
  ]

  @stream_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :setup,
    :chunks,
    :expected_chunks,
    :expected_output,
    :assertions,
    :tags,
    :notes,
    :metadata
  ]

  @ner_keys [
    :id,
    :kind,
    :source,
    :source_license,
    :text,
    :language,
    :entities,
    :model_outputs,
    :expected,
    :should_match,
    :profile,
    :tags,
    :notes,
    :metadata
  ]

  @doc """
  Validates a fixture map.
  """
  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(%{kind: :analyzer} = fixture), do: validate_analyzer(fixture)
  def validate(%{kind: :operator} = fixture), do: validate_operator(fixture)
  def validate(%{kind: :structured} = fixture), do: validate_structured(fixture)
  def validate(%{kind: :context} = fixture), do: validate_context(fixture)
  def validate(%{kind: :vault} = fixture), do: validate_vault(fixture)
  def validate(%{kind: :llm} = fixture), do: validate_llm(fixture)
  def validate(%{kind: :stream} = fixture), do: validate_stream(fixture)
  def validate(%{kind: :nlp} = fixture), do: validate_ner(fixture, :nlp)
  def validate(%{kind: :ner} = fixture), do: validate_ner(fixture, :ner)
  def validate(%{} = fixture), do: {:error, {:unknown_fixture_kind, Map.get(fixture, :kind)}}

  @doc """
  Validates an analyzer fixture.
  """
  @spec validate_analyzer(map()) :: {:ok, map()} | {:error, term()}
  def validate_analyzer(fixture) when is_map(fixture) do
    with :ok <- require_keys(fixture, @analyzer_keys),
         :ok <- validate_common(fixture, :analyzer),
         :ok <- validate_entities(Map.fetch!(fixture, :entities)),
         :ok <-
           validate_expected(
             Map.fetch!(fixture, :text),
             Map.fetch!(fixture, :expected),
             Map.fetch!(fixture, :should_match)
           ) do
      {:ok, fixture}
    end
  end

  @doc """
  Validates an operator fixture.
  """
  @spec validate_operator(map()) :: {:ok, map()} | {:error, term()}
  def validate_operator(fixture) when is_map(fixture) do
    with :ok <- require_keys(fixture, @operator_keys),
         :ok <- validate_common(fixture, :operator),
         :ok <-
           validate_spans(Map.fetch!(fixture, :text), Map.fetch!(fixture, :spans),
             allow_invalid?: has_tag?(fixture, :invalid_span)
           ),
         :ok <- validate_expected_items(Map.fetch!(fixture, :expected_items)),
         :ok <- validate_operator_config(Map.fetch!(fixture, :operators)),
         :ok <- validate_string(Map.fetch!(fixture, :expected_text), :expected_text) do
      {:ok, fixture}
    end
  end

  @doc """
  Validates a structured fixture.
  """
  @spec validate_structured(map()) :: {:ok, map()} | {:error, term()}
  def validate_structured(fixture) when is_map(fixture) do
    with :ok <- require_keys(fixture, @structured_keys),
         :ok <- validate_common(fixture, :structured),
         :ok <- validate_list(Map.fetch!(fixture, :opts), :opts),
         :ok <- validate_expected_items(Map.fetch!(fixture, :expected_items)) do
      {:ok, fixture}
    end
  end

  @doc """
  Validates a context fixture.
  """
  @spec validate_context(map()) :: {:ok, map()} | {:error, term()}
  def validate_context(fixture) when is_map(fixture) do
    with :ok <- require_keys(fixture, @context_keys),
         :ok <- validate_common(fixture, :context),
         :ok <- validate_string(Map.fetch!(fixture, :text_without_context), :text_without_context),
         :ok <- validate_string(Map.fetch!(fixture, :text_with_context), :text_with_context),
         :ok <- validate_entities(Map.fetch!(fixture, :entities)),
         :ok <- validate_atom(Map.fetch!(fixture, :expected_entity), :expected_entity),
         :ok <- validate_string(Map.fetch!(fixture, :expected_value), :expected_value),
         :ok <-
           validate_string_list(
             Map.fetch!(fixture, :expected_context_words),
             :expected_context_words
           ),
         :ok <- validate_tags(Map.fetch!(fixture, :assertions)),
         :ok <- validate_atom(Map.fetch!(fixture, :profile), :profile) do
      {:ok, fixture}
    end
  end

  @doc """
  Validates a vault fixture.
  """
  @spec validate_vault(map()) :: {:ok, map()} | {:error, term()}
  def validate_vault(fixture) when is_map(fixture) do
    with :ok <- require_keys(fixture, @vault_keys),
         :ok <- validate_common(fixture, :vault),
         :ok <- validate_atom(Map.fetch!(fixture, :backend), :backend),
         :ok <- validate_list(Map.fetch!(fixture, :operations), :operations),
         :ok <- validate_string_list(Map.fetch!(fixture, :expected_tokens), :expected_tokens),
         :ok <- validate_string(Map.fetch!(fixture, :expected_rehydrated), :expected_rehydrated),
         :ok <- validate_tags(Map.fetch!(fixture, :assertions)) do
      {:ok, fixture}
    end
  end

  @doc """
  Validates an LLM fixture.
  """
  @spec validate_llm(map()) :: {:ok, map()} | {:error, term()}
  def validate_llm(fixture) when is_map(fixture) do
    with :ok <- require_keys(fixture, @llm_keys),
         :ok <- validate_common(fixture, :llm),
         :ok <- validate_list(Map.fetch!(fixture, :messages), :messages),
         :ok <- validate_list(Map.fetch!(fixture, :opts), :opts),
         :ok <- validate_list(Map.fetch!(fixture, :expected_messages), :expected_messages),
         :ok <- validate_string(Map.fetch!(fixture, :response), :response),
         :ok <-
           validate_string(
             Map.fetch!(fixture, :expected_rehydrated_response),
             :expected_rehydrated_response
           ),
         :ok <- validate_tags(Map.fetch!(fixture, :assertions)) do
      {:ok, fixture}
    end
  end

  @doc """
  Validates a stream fixture.
  """
  @spec validate_stream(map()) :: {:ok, map()} | {:error, term()}
  def validate_stream(fixture) when is_map(fixture) do
    with :ok <- require_keys(fixture, @stream_keys),
         :ok <- validate_common(fixture, :stream),
         :ok <- validate_list(Map.fetch!(fixture, :setup), :setup),
         :ok <- validate_string_list(Map.fetch!(fixture, :chunks), :chunks),
         :ok <- validate_string_list(Map.fetch!(fixture, :expected_chunks), :expected_chunks),
         :ok <- validate_string(Map.fetch!(fixture, :expected_output), :expected_output),
         :ok <- validate_tags(Map.fetch!(fixture, :assertions)) do
      {:ok, fixture}
    end
  end

  @doc """
  Validates NLP/NER fixtures.
  """
  @spec validate_ner(map(), :nlp | :ner) :: {:ok, map()} | {:error, term()}
  def validate_ner(fixture, kind) when is_map(fixture) do
    with :ok <- require_keys(fixture, @ner_keys),
         :ok <- validate_common(fixture, kind),
         :ok <- validate_entities(Map.fetch!(fixture, :entities)),
         :ok <- validate_model_outputs(Map.fetch!(fixture, :model_outputs)),
         :ok <-
           validate_expected(
             Map.fetch!(fixture, :text),
             Map.fetch!(fixture, :expected),
             Map.fetch!(fixture, :should_match)
           ),
         :ok <- validate_atom(Map.fetch!(fixture, :profile), :profile) do
      {:ok, fixture}
    end
  end

  defp validate_common(fixture, kind) do
    with :ok <- validate_string(Map.fetch!(fixture, :id), :id),
         :ok <- validate_string(Map.fetch!(fixture, :source), :source),
         :ok <- validate_string_or_nil(Map.fetch!(fixture, :source_license), :source_license),
         :ok <- validate_optional_text(fixture),
         :ok <- validate_tags(Map.fetch!(fixture, :tags)),
         :ok <- validate_string_or_nil(Map.fetch!(fixture, :notes), :notes),
         :ok <- validate_map(Map.fetch!(fixture, :metadata), :metadata) do
      if Map.fetch!(fixture, :kind) == kind do
        :ok
      else
        {:error, {:invalid_kind, Map.fetch!(fixture, :kind)}}
      end
    end
  end

  defp require_keys(map, keys) do
    case Enum.reject(keys, &Map.has_key?(map, &1)) do
      [] -> :ok
      missing -> {:error, {:missing_keys, missing}}
    end
  end

  defp validate_expected(text, expected, should_match)
       when is_list(expected) and is_boolean(should_match) do
    cond do
      should_match and expected == [] ->
        {:error, :positive_fixture_without_expected_spans}

      not should_match and expected != [] ->
        {:error, :negative_fixture_with_expected_spans}

      true ->
        validate_spans(text, expected, allow_invalid?: false)
    end
  end

  defp validate_expected(_text, _expected, _should_match),
    do: {:error, :invalid_expected_or_should_match}

  defp validate_spans(text, spans, opts) when is_list(spans) do
    allow_invalid? = Keyword.fetch!(opts, :allow_invalid?)

    Enum.reduce_while(spans, :ok, fn span, :ok ->
      with :ok <- validate_span_shape(span),
           :ok <- validate_span_offsets(text, span, allow_invalid?) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_spans(_text, _spans, _opts), do: {:error, :invalid_spans}

  defp validate_span_shape(span) when is_map(span) do
    required = [
      :entity,
      :byte_start,
      :byte_end,
      :char_start,
      :char_end,
      :value,
      :source_entity,
      :metadata
    ]

    with :ok <- require_keys(span, required),
         :ok <- validate_atom(Map.fetch!(span, :entity), :entity),
         :ok <- validate_string_or_nil(Map.fetch!(span, :value), :value),
         :ok <- validate_string_or_nil(Map.fetch!(span, :source_entity), :source_entity) do
      validate_map(Map.fetch!(span, :metadata), :metadata)
    end
  end

  defp validate_span_shape(_span), do: {:error, :invalid_span}

  defp validate_span_offsets(text, span, true) do
    case Offset.validate_span(text, span) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp validate_span_offsets(text, span, false), do: Offset.validate_span(text, span)

  defp validate_expected_items(items) when is_list(items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      required = [
        :entity,
        :operator,
        :source_byte_start,
        :source_byte_end,
        :replacement_byte_start,
        :replacement_byte_end,
        :replacement,
        :metadata
      ]

      with :ok <- require_keys(item, required),
           :ok <- validate_atom(Map.fetch!(item, :entity), :entity),
           :ok <- validate_atom(Map.fetch!(item, :operator), :operator),
           :ok <- validate_string(Map.fetch!(item, :replacement), :replacement),
           :ok <- validate_map(Map.fetch!(item, :metadata), :metadata) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_expected_items(_items), do: {:error, :invalid_expected_items}

  defp validate_model_outputs(outputs) when is_list(outputs) do
    Enum.reduce_while(outputs, :ok, fn output, :ok ->
      with :ok <- validate_model_output_shape(output),
           :ok <- validate_model_offset_unit(Map.get(output, :offset_unit, :character)),
           :ok <- validate_score(Map.get(output, :score, 1.0)) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_model_outputs(_outputs), do: {:error, :invalid_model_outputs}

  defp validate_model_output_shape(output) when is_map(output) do
    with :ok <- require_keys(output, [:label, :start, :end]),
         :ok <- validate_string(Map.fetch!(output, :label), :label) do
      if is_integer(output.start) and output.start >= 0 and is_integer(output.end) and
           output.end > output.start do
        :ok
      else
        {:error, :invalid_model_offsets}
      end
    end
  end

  defp validate_model_output_shape(_output), do: {:error, :invalid_model_output}

  defp validate_model_offset_unit(unit) when unit in [:byte, :character], do: :ok
  defp validate_model_offset_unit(unit), do: {:error, {:invalid_offset_unit, unit}}

  defp validate_score(score) when is_number(score) and score >= 0.0 and score <= 1.0, do: :ok
  defp validate_score(_score), do: {:error, :invalid_model_score}

  defp validate_entities(entities) when is_list(entities) do
    if Enum.all?(entities, &is_atom/1), do: :ok, else: {:error, :invalid_entities}
  end

  defp validate_entities(_entities), do: {:error, :invalid_entities}

  defp validate_operator_config(config) when is_map(config), do: :ok
  defp validate_operator_config(_config), do: {:error, :invalid_operator_config}

  defp validate_tags(tags) when is_list(tags) do
    if Enum.all?(tags, &is_atom/1), do: :ok, else: {:error, :invalid_tags}
  end

  defp validate_tags(_tags), do: {:error, :invalid_tags}

  defp validate_list(value, _key) when is_list(value), do: :ok
  defp validate_list(value, key), do: {:error, {:invalid_list, key, value}}

  defp validate_string_list(value, key) when is_list(value) do
    if Enum.all?(value, &is_binary/1), do: :ok, else: {:error, {:invalid_string_list, key}}
  end

  defp validate_string_list(_value, key), do: {:error, {:invalid_string_list, key}}

  defp validate_string(value, _key) when is_binary(value), do: :ok
  defp validate_string(value, key), do: {:error, {:invalid_string, key, value}}

  defp validate_string_or_nil(nil, _key), do: :ok
  defp validate_string_or_nil(value, key), do: validate_string(value, key)

  defp validate_optional_text(%{text: text}), do: validate_string(text, :text)
  defp validate_optional_text(_fixture), do: :ok

  defp validate_atom(value, _key) when is_atom(value), do: :ok
  defp validate_atom(value, key), do: {:error, {:invalid_atom, key, value}}

  defp validate_map(value, _key) when is_map(value), do: :ok
  defp validate_map(value, key), do: {:error, {:invalid_map, key, value}}

  defp has_tag?(fixture, tag), do: tag in Map.get(fixture, :tags, [])
end
