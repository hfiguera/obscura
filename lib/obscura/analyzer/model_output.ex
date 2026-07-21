defmodule Obscura.Analyzer.ModelOutput do
  @moduledoc """
  Normalizes model output entries into analyzer results with byte offsets.
  """

  alias Obscura.Analyzer.Explanation
  alias Obscura.Analyzer.Result
  alias Obscura.NLP.Artifacts
  alias Obscura.Recognizer.NER.LabelMap

  @type output :: %{
          required(:label) => String.t(),
          required(:start) => non_neg_integer(),
          required(:end) => non_neg_integer(),
          optional(:offset_unit) => :byte | :character,
          optional(:score) => float()
        }

  @doc """
  Normalizes model outputs for one source text.
  """
  @spec normalize(String.t(), [map()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def normalize(text, outputs, opts \\ [])

  def normalize(text, outputs, opts)
      when is_binary(text) and is_list(outputs) and is_list(opts) do
    Enum.reduce_while(outputs, {:ok, []}, fn output, {:ok, acc} ->
      case normalize_one(text, output, opts) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize(_text, _outputs, _opts), do: {:error, :invalid_model_outputs}

  defp normalize_one(text, output, opts) when is_map(output) do
    with {:ok, label} <- fetch_label(output),
         true <- not ignored_label?(label, opts) || :ignored_label,
         {:ok, entity} <- LabelMap.to_entity(label, opts),
         {:ok, score} <- score(output),
         adjusted_score = adjusted_score(score, label, entity, opts),
         {threshold, threshold_metadata} = threshold_for(label, entity, opts),
         true <- adjusted_score >= threshold || :below_threshold,
         {:ok, {byte_start, byte_end, offset_metadata}} <- offsets(text, output, opts),
         span_text = binary_part(text, byte_start, byte_end - byte_start),
         true <-
           structured_model_entity_valid?(entity, span_text, opts) ||
             :invalid_structured_model_entity do
      include_text = Keyword.get(opts, :include_text, true)
      value = if include_text, do: span_text, else: nil

      metadata_input = %{
        output: output,
        label: label,
        entity: entity,
        original_score: score,
        adjusted_score: adjusted_score,
        threshold: threshold,
        threshold_metadata: threshold_metadata,
        offset_metadata: offset_metadata,
        structured_validation_metadata: structured_validation_metadata(entity, opts)
      }

      {:ok,
       %Result{
         entity: entity,
         start: byte_start,
         end: byte_end,
         byte_start: byte_start,
         byte_end: byte_end,
         score: adjusted_score,
         text: value,
         source_entity: label,
         recognizer: :ner,
         explanation: explanation(label, adjusted_score, opts),
         metadata: model_metadata(metadata_input, opts)
       }}
    else
      :ignored_label -> {:ok, nil}
      :below_threshold -> {:ok, nil}
      :invalid_structured_model_entity -> {:ok, nil}
      {:error, :empty_model_span} -> {:ok, nil}
      {:error, {:unknown_model_label, _label}} = error -> handle_unknown_label(error, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_one(_text, _output, _opts), do: {:error, :invalid_model_output}

  defp handle_unknown_label({:error, _reason}, opts) do
    if Keyword.get(opts, :unknown_labels, :ignore) == :ignore do
      {:ok, nil}
    else
      {:error, :unknown_model_label}
    end
  end

  defp fetch_label(%{label: label}) when is_binary(label), do: {:ok, label}
  defp fetch_label(%{"label" => label}) when is_binary(label), do: {:ok, label}
  defp fetch_label(_output), do: {:error, :missing_model_label}

  defp score(%{score: score}) when is_number(score) and score >= 0.0 and score <= 1.0,
    do: {:ok, score / 1}

  defp score(%{"score" => score}) when is_number(score) and score >= 0.0 and score <= 1.0,
    do: {:ok, score / 1}

  defp score(output) when is_map(output) do
    if Map.has_key?(output, :score) or Map.has_key?(output, "score") do
      {:error, :invalid_model_score}
    else
      {:ok, 1.0}
    end
  end

  defp ignored_label?(label, opts) do
    ignored_labels = Keyword.get(opts, :labels_to_ignore, [])

    label in ignored_labels or base_model_label(label) in ignored_labels
  end

  defp base_model_label(label) when is_binary(label) do
    String.replace(label, ~r/^(B|I|E|S|L|U)-/, "")
  end

  defp adjusted_score(score, label, entity, opts) do
    if label_matches?(label, Keyword.get(opts, :low_score_labels, [])) or
         entity in Keyword.get(opts, :low_score_entity_names, []) do
      score * Keyword.get(opts, :low_confidence_score_multiplier, 0.4)
    else
      score
    end
  end

  defp threshold_for(label, entity, opts) do
    case label_policy_value(label, Keyword.get(opts, :per_label_thresholds, %{})) do
      {threshold, matched_label} ->
        {threshold,
         %{
           model_threshold_scope: :label,
           model_threshold_label: matched_label
         }}

      nil ->
        threshold =
          opts
          |> Keyword.get(:per_entity_thresholds, %{})
          |> Map.get(entity, Keyword.get(opts, :score_threshold, 0.0))

        {threshold, %{model_threshold_scope: :entity}}
    end
  end

  defp model_metadata(input, opts) do
    %{
      model_label: input.label,
      model_entity: input.entity,
      model_original_score: input.original_score,
      model_score_threshold: input.threshold,
      model_aggregation_strategy: Keyword.get(opts, :aggregation_strategy, :same),
      model_alignment_config: Keyword.get(opts, :alignment_mode, :expand),
      model_low_confidence_score_multiplier:
        Keyword.get(opts, :low_confidence_score_multiplier, 0.4),
      offset_unit:
        Map.get(input.output, :offset_unit, Map.get(input.output, "offset_unit", :character))
    }
    |> Map.merge(input.threshold_metadata)
    |> Map.merge(input.offset_metadata)
    |> Map.merge(input.structured_validation_metadata)
    |> Map.merge(runtime_metadata(input.output))
    |> Map.merge(negative_context_metadata(input.label, opts))
    |> Map.merge(context_gate_metadata(input.label, input.entity, input.adjusted_score, opts))
    |> maybe_put_adjusted_score(input.original_score, input.adjusted_score)
  end

  defp runtime_metadata(output) do
    output
    |> Map.take([
      :model_chunking,
      :model_chunk_index,
      :model_chunk_byte_start,
      :model_chunk_byte_end,
      :model_chunk_character_start,
      :model_chunk_character_end,
      :model_chunk_size,
      :model_chunk_overlap
    ])
  end

  defp maybe_put_adjusted_score(metadata, score, score), do: metadata

  defp maybe_put_adjusted_score(metadata, _original_score, adjusted_score),
    do: Map.put(metadata, :model_adjusted_score, adjusted_score)

  defp context_gate_metadata(label, entity, score, opts) do
    {requires_context?, threshold, threshold_metadata} =
      context_gate(label, entity, score, opts)

    if requires_context? do
      %{
        requires_context: true,
        context_required_below_score: threshold,
        context_words: context_words(label, entity, opts),
        weak_context_words: weak_context_words(label, opts),
        negative_context_words: negative_context_words(label, opts),
        negative_context_reject: negative_context_reject?(label, opts),
        context_source: :nlp_artifacts,
        context_matching_mode: :whole_word,
        model_context_gate: :score_below_context_threshold
      }
      |> Map.merge(threshold_metadata)
    else
      %{}
    end
  end

  defp negative_context_metadata(label, opts) do
    words = negative_context_words(label, opts)

    if words == [] do
      %{}
    else
      %{
        negative_context_words: words,
        negative_context_reject: negative_context_reject?(label, opts),
        context_source: :nlp_artifacts,
        context_matching_mode: :whole_word
      }
    end
  end

  defp context_gate(label, entity, score, opts) do
    if label_matches?(label, Keyword.get(opts, :context_required_labels, [])) do
      {true, 1.0,
       %{
         context_required_scope: :label,
         context_required_label: base_model_label(label),
         model_context_gate_policy: :label_always_requires_context
       }}
    else
      {threshold, threshold_metadata} =
        case label_policy_value(label, Keyword.get(opts, :context_required_below_labels, %{})) do
          {threshold, matched_label} ->
            {threshold,
             %{
               context_required_scope: :label,
               context_required_label: matched_label
             }}

          nil ->
            threshold =
              opts
              |> Keyword.get(:context_required_below_thresholds, %{})
              |> Map.get(entity)

            {threshold, %{context_required_scope: :entity}}
        end

      {is_number(threshold) and score < threshold, threshold, threshold_metadata}
    end
  end

  defp label_policy_value(label, policy) when is_binary(label) and is_map(policy) do
    cond do
      Map.has_key?(policy, label) ->
        {Map.fetch!(policy, label), label}

      Map.has_key?(policy, base_model_label(label)) ->
        base_label = base_model_label(label)
        {Map.fetch!(policy, base_label), base_label}

      true ->
        nil
    end
  end

  defp label_policy_value(_label, _policy), do: nil

  defp label_matches?(label, labels) when is_binary(label) and is_list(labels) do
    label in labels or base_model_label(label) in labels
  end

  defp context_words(label, entity, opts) do
    label_words =
      label
      |> label_policy_words(Keyword.get(opts, :context_words_by_label, %{}))

    entity_words =
      opts
      |> Keyword.get(:context_words_by_entity, %{})
      |> Map.get(entity, [])

    (label_words ++ entity_words)
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp weak_context_words(label, opts) do
    label
    |> label_policy_words(Keyword.get(opts, :weak_context_words_by_label, %{}))
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp negative_context_words(label, opts) do
    label
    |> label_policy_words(Keyword.get(opts, :negative_context_words_by_label, %{}))
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp negative_context_reject?(label, opts) do
    label_matches?(label, Keyword.get(opts, :negative_context_reject_labels, []))
  end

  defp label_policy_words(label, policy) when is_binary(label) and is_map(policy) do
    cond do
      Map.has_key?(policy, label) ->
        Map.fetch!(policy, label)

      Map.has_key?(policy, base_model_label(label)) ->
        policy |> Map.fetch!(base_model_label(label))

      true ->
        []
    end
  end

  defp label_policy_words(_label, _policy), do: []

  defp structured_validation_metadata(entity, opts) do
    if Keyword.get(opts, :validate_structured_model_entities, false) and
         structured_entity?(entity) do
      %{model_structured_validation: :passed}
    else
      %{}
    end
  end

  defp structured_model_entity_valid?(entity, value, opts) do
    if Keyword.get(opts, :validate_structured_model_entities, false) and
         structured_entity?(entity) do
      valid_structured_value?(entity, String.trim(value))
    else
      true
    end
  end

  defp structured_entity?(entity)
       when entity in [:email, :phone, :credit_card, :url, :ip_address, :us_ssn],
       do: true

  defp structured_entity?(_entity), do: false

  defp valid_structured_value?(:email, value) do
    Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, value)
  end

  defp valid_structured_value?(:phone, value) do
    digits = only_digits(value)
    byte_size(digits) >= 7 and byte_size(digits) <= 16
  end

  defp valid_structured_value?(:credit_card, value) do
    digits = only_digits(value)
    byte_size(digits) in 13..19 and luhn_valid?(digits)
  end

  defp valid_structured_value?(:url, value) do
    uri = URI.parse(value)
    is_binary(uri.host) or String.starts_with?(value, "www.")
  rescue
    _error -> false
  end

  defp valid_structured_value?(:ip_address, value) do
    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, _address} -> true
      {:error, _reason} -> false
    end
  end

  defp valid_structured_value?(:us_ssn, value) do
    Regex.match?(~r/^\d{3}-?\d{2}-?\d{4}$/, value)
  end

  defp only_digits(value), do: String.replace(value, ~r/\D/, "")

  defp luhn_valid?(digits) do
    digits
    |> String.graphemes()
    |> Enum.reverse()
    |> Stream.with_index()
    |> Enum.reduce(0, fn {digit, index}, acc ->
      acc + luhn_digit_value(String.to_integer(digit), index)
    end)
    |> rem(10)
    |> then(&(&1 == 0))
  end

  defp luhn_digit_value(value, index) do
    if rem(index, 2) == 1 do
      normalized_luhn_double(value)
    else
      value
    end
  end

  defp normalized_luhn_double(value) do
    doubled = value * 2
    if doubled > 9, do: doubled - 9, else: doubled
  end

  defp offsets(text, output, opts) do
    with {:ok, start_offset} <- fetch_offset(output, :start),
         {:ok, end_offset} <- fetch_offset(output, :end),
         {:ok, unit} <- offset_unit(output),
         {:ok, byte_start} <- to_byte_offset(text, start_offset, unit),
         {:ok, byte_end} <- to_byte_offset(text, end_offset, unit),
         :ok <- validate_span(text, byte_start, byte_end),
         {:ok, {aligned_start, aligned_end, metadata}} <-
           align_offsets(text, byte_start, byte_end, Keyword.get(opts, :alignment_mode, :expand)),
         :ok <- validate_span(text, aligned_start, aligned_end),
         {:ok, {normalized_start, normalized_end, normalization_metadata}} <-
           normalize_boundaries(
             text,
             aligned_start,
             aligned_end,
             Keyword.get(opts, :boundary_normalization, :none)
           ),
         :ok <- validate_span(text, normalized_start, normalized_end),
         {:ok, {postprocessed_start, postprocessed_end, postprocess_metadata}} <-
           postprocess_boundaries(
             text,
             normalized_start,
             normalized_end,
             Map.get(output, :label, Map.get(output, "label")),
             opts
           ),
         :ok <- validate_span(text, postprocessed_start, postprocessed_end) do
      {:ok,
       {postprocessed_start, postprocessed_end,
        metadata
        |> Map.merge(normalization_metadata)
        |> Map.merge(postprocess_metadata)}}
    end
  end

  defp fetch_offset(output, key) do
    string_key = Atom.to_string(key)

    cond do
      is_integer(Map.get(output, key)) and Map.get(output, key) >= 0 ->
        {:ok, Map.fetch!(output, key)}

      is_integer(Map.get(output, string_key)) and Map.get(output, string_key) >= 0 ->
        {:ok, Map.fetch!(output, string_key)}

      true ->
        {:error, {:invalid_model_offset, key}}
    end
  end

  defp offset_unit(output) do
    unit = Map.get(output, :offset_unit, Map.get(output, "offset_unit", :character))

    case unit do
      :byte -> {:ok, :byte}
      "byte" -> {:ok, :byte}
      :character -> {:ok, :character}
      "character" -> {:ok, :character}
      _other -> {:error, :invalid_offset_unit}
    end
  end

  defp to_byte_offset(text, offset, :byte) when offset <= byte_size(text), do: {:ok, offset}

  defp to_byte_offset(text, offset, :character) do
    characters = String.graphemes(text)

    if offset <= length(characters) do
      byte_offset =
        characters
        |> Enum.take(offset)
        |> IO.iodata_to_binary()
        |> byte_size()

      {:ok, byte_offset}
    else
      {:error, :model_offset_out_of_bounds}
    end
  end

  defp to_byte_offset(_text, _offset, _unit), do: {:error, :model_offset_out_of_bounds}

  defp validate_span(text, byte_start, byte_end) do
    cond do
      byte_start > byte_end -> {:error, :invalid_model_span}
      byte_end > byte_size(text) -> {:error, :model_offset_out_of_bounds}
      byte_start == byte_end -> {:error, :empty_model_span}
      true -> :ok
    end
  end

  defp align_offsets(_text, byte_start, byte_end, :strict) do
    {:ok,
     {byte_start, byte_end,
      %{
        model_alignment_mode: :strict,
        model_original_byte_start: byte_start,
        model_original_byte_end: byte_end
      }}}
  end

  defp align_offsets(text, byte_start, byte_end, mode) when mode in [:expand, :contract] do
    artifacts = Artifacts.build(text)

    offsets =
      case mode do
        :expand -> intersecting_token_offsets(artifacts, byte_start, byte_end)
        :contract -> contained_token_offsets(artifacts, byte_start, byte_end)
      end

    case offsets do
      [] ->
        {:ok,
         {byte_start, byte_end,
          %{
            model_alignment_mode: mode,
            model_original_byte_start: byte_start,
            model_original_byte_end: byte_end,
            model_boundary_adjusted: false
          }}}

      token_offsets ->
        aligned_start = Enum.min_by(token_offsets, & &1.byte_start).byte_start
        aligned_end = Enum.max_by(token_offsets, & &1.byte_end).byte_end

        {:ok,
         {aligned_start, aligned_end,
          %{
            model_alignment_mode: mode,
            model_original_byte_start: byte_start,
            model_original_byte_end: byte_end,
            model_boundary_adjusted: aligned_start != byte_start or aligned_end != byte_end
          }}}
    end
  end

  defp align_offsets(_text, _byte_start, _byte_end, _mode), do: {:error, :invalid_alignment_mode}

  defp normalize_boundaries(_text, byte_start, byte_end, :none),
    do: {:ok, {byte_start, byte_end, %{model_boundary_normalization: :none}}}

  defp normalize_boundaries(text, byte_start, byte_end, :conservative) do
    {normalized_start, normalized_end} =
      text
      |> binary_part(byte_start, byte_end - byte_start)
      |> conservative_boundary_offsets(byte_start, byte_end)

    if normalized_start < normalized_end do
      {:ok,
       {normalized_start, normalized_end,
        %{
          model_boundary_normalization: :conservative,
          model_boundary_normalized: normalized_start != byte_start or normalized_end != byte_end,
          model_boundary_before_normalization: %{byte_start: byte_start, byte_end: byte_end}
        }}}
    else
      {:ok,
       {byte_start, byte_end,
        %{
          model_boundary_normalization: :conservative,
          model_boundary_normalized: false,
          model_boundary_normalization_rejected: :empty_span
        }}}
    end
  end

  defp normalize_boundaries(_text, _byte_start, _byte_end, _mode),
    do: {:error, :invalid_boundary_normalization}

  defp postprocess_boundaries(text, byte_start, byte_end, label, opts) do
    entity = model_entity(label, opts)

    case run_model_postprocessors(text, byte_start, byte_end, entity, opts) do
      {^byte_start, ^byte_end, []} ->
        {:ok, {byte_start, byte_end, %{}}}

      {new_start, new_end, events} ->
        {:ok,
         {new_start, new_end,
          %{
            model_postprocess_state: postprocess_state(events),
            model_postprocess_events: Enum.reverse(events),
            model_postprocess_before: %{byte_start: byte_start, byte_end: byte_end}
          }}}
    end
  end

  defp model_entity(label, opts) do
    case LabelMap.to_entity(label, opts) do
      {:ok, entity} -> entity
      {:error, _reason} -> :unknown
    end
  end

  defp run_model_postprocessors(text, byte_start, byte_end, entity, opts) do
    opts
    |> Keyword.get(:model_postprocessors, [])
    |> Enum.reduce({byte_start, byte_end, []}, fn postprocessor, {start, finish, events} ->
      apply_model_postprocessor_event(text, start, finish, entity, postprocessor, events)
    end)
  end

  defp apply_model_postprocessor_event(text, start, finish, entity, postprocessor, events) do
    case apply_model_postprocessor(text, start, finish, entity, postprocessor) do
      {:expanded, new_start, new_finish, metadata} ->
        {new_start, new_finish, [metadata | events]}

      {:unchanged, metadata} ->
        {start, finish, [metadata | events]}

      {:rejected, metadata} ->
        {start, finish, [metadata | events]}
    end
  end

  defp postprocess_state(events) do
    cond do
      Enum.any?(events, &(&1.state == :expanded)) -> :expanded
      Enum.any?(events, &(&1.state == :rejected)) -> :rejected
      true -> :unchanged
    end
  end

  defp apply_model_postprocessor(
         text,
         byte_start,
         byte_end,
         :organization,
         :organization_suffix_expansion
       ) do
    suffix_expansion(text, byte_start, byte_end, :organization_suffix_expansion, [
      "bank",
      "corp",
      "corporation",
      "hospital",
      "inc",
      "llc",
      "ltd",
      "university"
    ])
  end

  defp apply_model_postprocessor(
         text,
         byte_start,
         byte_end,
         :location,
         :location_suffix_expansion
       ) do
    suffix_expansion(text, byte_start, byte_end, :location_suffix_expansion, [
      "airport",
      "center",
      "centre",
      "hospital",
      "station",
      "university"
    ])
  end

  defp apply_model_postprocessor(
         _text,
         _byte_start,
         _byte_end,
         entity,
         postprocessor
       ) do
    {:rejected,
     %{
       postprocessor: postprocessor,
       state: :rejected,
       reason: :entity_not_supported,
       entity: entity
     }}
  end

  defp suffix_expansion(text, byte_start, byte_end, postprocessor, suffixes) do
    artifacts = Artifacts.build(text)

    case next_token_offset(artifacts, byte_end) do
      {token, offset} ->
        if Artifacts.normalize_token(token) in suffixes do
          {:expanded, byte_start, offset.byte_end,
           %{
             postprocessor: postprocessor,
             state: :expanded,
             reason: :matched_suffix_token,
             suffix_token: token,
             before: %{byte_start: byte_start, byte_end: byte_end},
             after: %{byte_start: byte_start, byte_end: offset.byte_end}
           }}
        else
          {:unchanged,
           %{
             postprocessor: postprocessor,
             state: :unchanged,
             reason: :next_token_not_suffix,
             next_token: token
           }}
        end

      nil ->
        {:unchanged,
         %{
           postprocessor: postprocessor,
           state: :unchanged,
           reason: :no_next_token
         }}
    end
  end

  defp next_token_offset(%Artifacts{} = artifacts, byte_end) do
    artifacts.tokens
    |> Enum.zip(artifacts.token_offsets)
    |> Enum.find(fn {_token, offset} -> offset.byte_start >= byte_end end)
  end

  defp conservative_boundary_offsets(span_text, base_start, base_end) do
    trimmed = trim_punctuation_offsets(span_text, base_start, base_end)

    span_text
    |> binary_part(elem(trimmed, 0) - base_start, elem(trimmed, 1) - elem(trimmed, 0))
    |> trim_trailing_connector_offsets(elem(trimmed, 0), elem(trimmed, 1))
  end

  defp trim_punctuation_offsets(span_text, base_start, base_end) do
    leading =
      case Regex.run(~r/^\s*[\p{P}\p{S}]*/u, span_text) do
        [match] -> byte_size(match)
        _other -> 0
      end

    trailing =
      case Regex.run(~r/[\s\p{P}\p{S}]*$/u, span_text) do
        [match] -> byte_size(match)
        _other -> 0
      end

    {min(base_start + leading, base_end), max(base_end - trailing, base_start)}
  end

  defp trim_trailing_connector_offsets(span_text, start_offset, end_offset) do
    case Regex.run(~r/\s+(?:and|or|with|at|in|from|to|for)$/iu, span_text, return: :index) do
      [{connector_start, connector_length}] ->
        {start_offset, max(end_offset - connector_length, start_offset + connector_start)}

      _other ->
        {start_offset, end_offset}
    end
  end

  defp intersecting_token_offsets(%Artifacts{} = artifacts, byte_start, byte_end) do
    Enum.filter(artifacts.token_offsets, fn offset ->
      offset.byte_end > byte_start and offset.byte_start < byte_end
    end)
  end

  defp contained_token_offsets(%Artifacts{} = artifacts, byte_start, byte_end) do
    Enum.filter(artifacts.token_offsets, fn offset ->
      offset.byte_start >= byte_start and offset.byte_end <= byte_end
    end)
  end

  defp explanation(label, score, opts) do
    if Keyword.get(opts, :explain, false) do
      %Explanation{
        recognizer: :ner,
        pattern: :model,
        score: score,
        original_score: score,
        metadata: %{model_label: label}
      }
    end
  end
end
