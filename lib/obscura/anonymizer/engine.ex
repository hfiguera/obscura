defmodule Obscura.Anonymizer.Engine do
  @moduledoc """
  Applies anonymization operators to validated byte spans.
  """

  alias Obscura.Anonymizer.Error
  alias Obscura.Anonymizer.Item
  alias Obscura.Anonymizer.Operator
  alias Obscura.Anonymizer.Result
  alias Obscura.Conflict
  alias Obscura.Eval.Offset
  alias Obscura.Input
  alias Obscura.Telemetry

  @default_operators %{
    default: %{type: :replace, value: "[REDACTED]"},
    email: %{type: :replace, value: "[EMAIL]"},
    phone: %{type: :replace, value: "[PHONE]"},
    credit_card: %{type: :replace, value: "[CREDIT_CARD]"},
    iban: %{type: :replace, value: "[IBAN]"},
    us_ssn: %{type: :replace, value: "[US_SSN]"},
    ip_address: %{type: :replace, value: "[IP_ADDRESS]"},
    url: %{type: :replace, value: "[URL]"},
    domain: %{type: :replace, value: "[DOMAIN]"}
  }

  @token_option_keys [
    :token_prefix,
    :token_suffix,
    :token_separator,
    :token_width,
    :token_case,
    :token_strategy
  ]

  @doc """
  Anonymizes a string using source byte offsets.
  """
  @spec anonymize(String.t(), [map() | struct()], keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def anonymize(text, spans, opts) when is_binary(text) and is_list(spans) and is_list(opts) do
    start = System.monotonic_time()
    telemetry? = Keyword.get(opts, :telemetry, true)

    result =
      with :ok <- Input.validate_text(text),
           {:ok, operators} <- validate_options(opts),
           {:ok, normalized} <- normalize_spans(text, spans) do
        conflict_strategy = conflict_strategy(operators, opts)

        merge_whitespace? =
          Keyword.get(opts, :merge_whitespace, Map.get(operators, :merge_whitespace, false))

        normalized
        |> maybe_merge_whitespace(text, merge_whitespace?)
        |> Conflict.resolve(conflict_strategy)
        |> apply_replacements(text, operators, opts)
      end

    emit_telemetry(telemetry?, start, result)
    result
  end

  def anonymize(_text, _spans, _opts) do
    {:error,
     Error.new(:invalid_operator_collection,
       field: :options,
       reason: :invalid_anonymize_arguments
     )}
  end

  @doc false
  @spec validate_options(keyword()) :: {:ok, map()} | {:error, Error.t()}
  def validate_options(opts) when is_list(opts) do
    with {:ok, operators} <- normalize_operators(Keyword.get(opts, :operators, %{})),
         :ok <- validate_merge_whitespace(operators, opts),
         :ok <- validate_conflict_strategy(operators, opts),
         :ok <- Operator.validate_configs(operators, validation_context(opts)) do
      {:ok, operators}
    end
  end

  def validate_options(_opts) do
    {:error,
     Error.new(:invalid_operator_collection,
       field: :options,
       reason: :expected_keyword_list
     )}
  end

  defp normalize_operators(operators) when is_map(operators) and map_size(operators) == 0,
    do: {:ok, @default_operators}

  defp normalize_operators(operators) when is_map(operators),
    do: {:ok, Map.put_new(operators, :default, Map.fetch!(@default_operators, :default))}

  defp normalize_operators(_operators) do
    {:error,
     Error.new(:invalid_operator_collection,
       field: :operators,
       reason: :expected_map
     )}
  end

  defp validate_merge_whitespace(operators, opts) do
    value = Keyword.get(opts, :merge_whitespace, Map.get(operators, :merge_whitespace, false))

    if is_boolean(value) do
      :ok
    else
      {:error,
       Error.new(:invalid_operator_option,
         field: :merge_whitespace,
         reason: :expected_boolean
       )}
    end
  end

  defp validate_conflict_strategy(operators, opts) do
    strategy = conflict_strategy(operators, opts)

    if strategy in [
         false,
         :none,
         :aggressive,
         :prefer_longer,
         :prefer_higher_confidence,
         :presidio_like
       ] do
      :ok
    else
      {:error,
       Error.new(:invalid_operator_option,
         field: :conflict_strategy,
         reason: :unsupported_conflict_strategy
       )}
    end
  end

  defp validation_context(opts) do
    %{
      vault: Keyword.get(opts, :vault),
      token_options: Keyword.take(opts, @token_option_keys)
    }
  end

  defp conflict_strategy(operators, opts) do
    Keyword.get(opts, :conflict_strategy, Map.get(operators, :conflict_policy, :aggressive))
  end

  defp normalize_spans(text, spans) do
    Enum.reduce_while(spans, {:ok, []}, fn span, {:ok, acc} ->
      with {:ok, normalized} <- normalize_span(span),
           :ok <- Offset.validate_span(text, offset_validation_span(normalized)) do
        {:cont, {:ok, [normalized | acc]}}
      else
        {:error, reason} ->
          {:halt, {:error, {:invalid_span, sanitize_span_error(reason)}}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp offset_validation_span(span) do
    Map.take(span, [:byte_start, :byte_end, :char_start, :char_end])
  end

  defp normalize_span(span) when is_map(span) do
    start = Map.get(span, :start, Map.get(span, :byte_start))
    end_offset = Map.get(span, :end, Map.get(span, :byte_end))
    value = Map.get(span, :value, Map.get(span, :text))

    case Map.get(span, :entity) do
      entity when is_atom(entity) and not is_nil(entity) ->
        {:ok,
         %{
           entity: entity,
           start: start,
           end: end_offset,
           byte_start: start,
           byte_end: end_offset,
           char_start: Map.get(span, :char_start),
           char_end: Map.get(span, :char_end),
           value: value,
           score: Map.get(span, :score, 1.0),
           source_entity: Map.get(span, :source_entity),
           metadata: Map.get(span, :metadata, %{})
         }}

      _invalid ->
        {:error, :invalid_entity}
    end
  end

  defp normalize_span(_span), do: {:error, :expected_map}

  defp sanitize_span_error({:value_mismatch, _details}), do: :value_mismatch
  defp sanitize_span_error(reason) when is_atom(reason), do: reason

  defp sanitize_span_error(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.map(fn
      value when is_atom(value) or is_integer(value) -> value
      _value -> :invalid
    end)
    |> List.to_tuple()
  end

  defp maybe_merge_whitespace(spans, _text, false), do: spans
  defp maybe_merge_whitespace(spans, text, true), do: merge_whitespace(spans, text)

  defp merge_whitespace(spans, text) do
    spans
    |> Enum.sort_by(&{&1.byte_start, &1.byte_end})
    |> Enum.reduce([], &merge_whitespace_span(text, &1, &2))
    |> Enum.reverse()
  end

  defp merge_whitespace_span(_text, span, []), do: [span]

  defp merge_whitespace_span(text, span, [previous | rest] = acc) do
    between = Offset.slice_bytes(text, previous.byte_end, span.byte_start)

    if mergeable_whitespace_spans?(previous, span, between) do
      [merge_spans(previous, span) | rest]
    else
      [span | acc]
    end
  end

  defp mergeable_whitespace_spans?(previous, span, between) do
    previous.entity == span.entity and whitespace_slice?(between)
  end

  defp merge_spans(previous, span) do
    %{
      previous
      | end: span.end,
        byte_end: span.byte_end,
        value: nil,
        metadata: Map.put(previous.metadata, :merged, true)
    }
  end

  defp whitespace_slice?({:ok, value}), do: String.trim(value) == ""
  defp whitespace_slice?({:error, _reason}), do: false

  defp apply_replacements(spans, text, operators, opts) do
    sorted_spans = Enum.sort_by(spans, &{&1.byte_start, &1.byte_end})
    multiple_replacements? = multiple_replacements?(sorted_spans)

    sorted_spans
    |> Enum.reduce_while({[], [], 0, 0}, fn span, {parts, items, source_cursor, output_cursor} ->
      {:ok, prefix} = Offset.slice_bytes(text, source_cursor, span.byte_start)
      {:ok, source_value} = Offset.slice_bytes(text, span.byte_start, span.byte_end)
      operator_config = operator_for(span.entity, operators)
      context = operator_context(span, opts)

      case Operator.apply(source_value, operator_config, context) do
        {:error, reason} ->
          {:halt, {:error, reason}}

        {operator_type, replacement, operator_metadata} ->
          replacement_start = output_cursor + byte_size(prefix)
          replacement_end = replacement_start + byte_size(replacement)

          item = %Item{
            entity: span.entity,
            operator: operator_type,
            source_byte_start: span.byte_start,
            source_byte_end: span.byte_end,
            replacement_byte_start: replacement_start,
            replacement_byte_end: replacement_end,
            replacement: replacement,
            metadata: item_metadata(span.metadata, operator_metadata, multiple_replacements?)
          }

          {:cont,
           {
             [replacement, prefix | parts],
             [item | items],
             span.byte_end,
             replacement_end
           }}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      state -> {:ok, finalize_result(state, text)}
    end
  end

  defp operator_context(span, opts) do
    %{
      entity: span.entity,
      span: span,
      opts: opts,
      vault: Keyword.get(opts, :vault),
      token_options: Keyword.take(opts, @token_option_keys)
    }
  end

  defp multiple_replacements?([_, _ | _rest]), do: true
  defp multiple_replacements?(_spans), do: false

  defp item_metadata(span_metadata, operator_metadata, true) do
    span_metadata
    |> Map.put_new(:replacement_order, :right_to_left)
    |> Map.merge(operator_metadata)
  end

  defp item_metadata(span_metadata, operator_metadata, false) do
    Map.merge(span_metadata, operator_metadata)
  end

  defp finalize_result({parts, items, source_cursor, _output_cursor}, text) do
    {:ok, suffix} = Offset.slice_bytes(text, source_cursor, byte_size(text))

    %Result{
      text: IO.iodata_to_binary(Enum.reverse([suffix | parts])),
      items: Enum.reverse(items),
      status: :ran
    }
  end

  defp operator_for(entity, operators),
    do: Map.get(operators, entity, Map.fetch!(operators, :default))

  defp emit_telemetry(telemetry?, start, {:ok, result}) do
    Telemetry.execute(
      telemetry?,
      [:obscura, :anonymize, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: result.status, input_type: :string, result_count: length(result.items)}
    )
  end

  defp emit_telemetry(telemetry?, start, {:error, _reason}) do
    Telemetry.execute(
      telemetry?,
      [:obscura, :anonymize, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: :error, input_type: :string, result_count: 0}
    )
  end
end
