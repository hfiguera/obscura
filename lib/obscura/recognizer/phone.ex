defmodule Obscura.Recognizer.Phone do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Internal.ResultText
  alias Obscura.Recognizer.Pattern
  alias Obscura.Recognizer.SpanHelpers

  @patterns [
    {:us_e164, ~r/(?<!\d)\+1[ .-]\d{3}[ .-]\d{3}[ .-]\d{4}(?!\d)/},
    {:us_parens, ~r/(?<!\d)\(\d{3}\)[ .-]\d{3}[ .-]\d{4}(?!\d)/},
    {:us_separated, ~r/(?<!\d)\d{3}[-. ]\d{3}[-. ]\d{4}(?!\d)/},
    {:us_separated_extension, ~r/(?<!\d)\d{3}[-. ]\d{3}[-. ]\d{4}x\d+(?!\d)/},
    {:us_compact, ~r/(?<!\d)\d{10}(?!\d)/},
    {:short_international_parens, ~r/(?<!\d)\(\d{2}\)[ .-]\d{3}[ .-]\d{3}(?!\d)/},
    {:short_international_parens_long, ~r/(?<!\d)\(\d{2}\)[ .-]\d{4}[ .-]\d{4}(?!\d)/},
    {:international_trunk_extension, ~r/(?<!\d)001-\d{3}-\d{3}-\d{4}x\d+(?!\d)/},
    {:e164_extension, ~r/(?<!\d)\+1-\d{3}-\d{3}-\d{4}x\d+(?!\d)/},
    {:us_parens_compact_extension, ~r/(?<!\d)\(\d{3}\)\d{3}-\d{4}x\d+(?!\d)/},
    {:generated_short_dashed, ~r/(?<!\d)\d{3}-\d{3}-\d{3}(?!\d)/},
    {:generated_local_7, ~r/(?<!\d)\d{3}[ .-]\d{4}(?!\d)/},
    {:generated_local_2_8, ~r/(?<!\d)\d{2}-\d{8}(?!\d)/},
    {:generated_local_2_2_2_2, ~r/(?<!\d)\d{2}-\d{2}-\d{2}-\d{2}(?!\d)/},
    {:generated_spaced_3_2_2_2, ~r/(?<!\d)\d{3}\s\d{2}\s\d{2}\s\d{2}(?!\d)/},
    {:generated_spaced_9, ~r/(?<!\d)\d{2}\s\d{3}\s\d{2}\s\d{2}(?!\d)/},
    {:generated_spaced_10, ~r/(?<!\d)\d{3}\s\d{3}\s\d{2}\s\d{2}(?!\d)/},
    {:generated_spaced_12, ~r/(?<!\d)\d{2}\s\d{3}\s\d{3}\s\d{4}(?!\d)/}
  ]
  @parser_candidate ~r/(?<![\w])\+?\d[\d().\- \t]{5,}\d(?:[ \t]*(?:ext\.?|extension|x)[ \t]*\d{1,7})?(?![\w])/iu

  @impl true
  def name, do: :phone

  @impl true
  def supported_entities, do: [:phone]

  @impl true
  def entity, do: :phone

  @impl true
  def analyze(text, opts) do
    (pattern_results(text, opts) ++ parser_candidate_results(text, opts))
    |> SpanHelpers.prefer_longest()
  end

  defp pattern_results(text, opts) do
    Enum.flat_map(@patterns, fn {pattern, regex} ->
      scan(text, regex, pattern, 0.75, opts)
    end)
  end

  defp parser_candidate_results(text, opts) do
    if parser_configured?(opts) do
      scan(text, @parser_candidate, :parser_candidate, 0.8, opts)
    else
      []
    end
  end

  defp scan(text, regex, pattern, score, opts) do
    Pattern.scan(text, regex,
      entity: :phone,
      source_entity: "PHONE_NUMBER",
      recognizer: :phone,
      pattern: pattern,
      score: score,
      explain: Keyword.get(opts, :explain, false),
      include_text: Keyword.get(opts, :include_text, true),
      allow_list: Keyword.get(opts, :allow_list),
      validate: &validate(&1, opts)
    )
    |> maybe_keep_parser_candidates(text, pattern, opts)
    |> maybe_keep_contextual_generated_phone(text, pattern, opts)
  end

  defp maybe_keep_parser_candidates(results, text, :parser_candidate, opts) do
    if Keyword.get(opts, :phone_parser_filter, :presidio_like) == :none do
      results
    else
      Enum.flat_map(results, &parser_candidate_result(&1, text))
    end
  end

  defp maybe_keep_parser_candidates(results, _text, _pattern, _opts), do: results

  defp parser_candidate_result(result, text) do
    value =
      ResultText.borrowed_slice(text, result.byte_start, result.byte_end)

    cond do
      plus_prefixed?(value) ->
        [put_parser_acceptance(result, :plus_prefixed)]

      extension?(value) ->
        [put_parser_acceptance(result, :extension)]

      parser_phone_context?(text, result) ->
        [put_parser_acceptance(result, :context)]

      true ->
        []
    end
  end

  defp put_parser_acceptance(result, reason) do
    Map.update(result, :metadata, %{phone_parser_acceptance: reason}, fn metadata ->
      metadata
      |> Kernel.||(%{})
      |> Map.put(:phone_parser_acceptance, reason)
    end)
  end

  defp plus_prefixed?(value), do: value |> String.trim_leading() |> String.starts_with?("+")

  defp extension?(value),
    do: Regex.match?(~r/(?:ext\.?|extension|x)\s*\d{1,7}\s*$/iu, value)

  defp maybe_keep_contextual_generated_phone(results, text, pattern, opts)
       when pattern in [
              :generated_local_7,
              :generated_local_2_8,
              :generated_local_2_2_2_2,
              :generated_spaced_3_2_2_2
            ] do
    if Keyword.get(opts, :profile) == :deterministic_plus do
      Enum.filter(results, &generated_phone_context?(text, &1))
    else
      []
    end
  end

  defp maybe_keep_contextual_generated_phone(results, _text, _pattern, _opts), do: results

  defp generated_phone_context?(text, result) do
    before =
      text
      |> binary_part(0, result.start)
      |> String.slice(-32..-1//1)
      |> String.downcase()

    after_text =
      text
      |> binary_part(result.end, byte_size(text) - result.end)
      |> String.slice(0, 32)
      |> String.downcase()

    Regex.match?(~r/\b(?:phone|mobile|office|desk|fax|tel|call|answering|at)\b/u, before) or
      Regex.match?(~r/\b(?:phone|mobile|office|desk|fax|tel|call)\b/u, after_text)
  end

  defp parser_phone_context?(text, result) do
    before =
      text
      |> binary_part(0, result.start)
      |> String.slice(-40..-1//1)
      |> String.downcase()

    after_text =
      text
      |> binary_part(result.end, byte_size(text) - result.end)
      |> String.slice(0, 40)
      |> String.downcase()

    Regex.match?(
      ~r/\b(?:phone|mobile|office|desk|fax|tel|telephone|cell|cellphone|call|number)\b/u,
      before
    ) or
      Regex.match?(
        ~r/\b(?:phone|mobile|office|desk|fax|tel|telephone|cell|cellphone|call)\b/u,
        after_text
      )
  end

  defp parser_configured?(opts) do
    not is_nil(Keyword.get(opts, :phone_parser)) or
      not is_nil(Keyword.get(opts, :phone_validator))
  end

  defp validate(value, opts) do
    with :ok <- reject_obvious_phone_junk(value) do
      if date_like?(value) do
        {:error, :date_like_phone_candidate}
      else
        validate_non_date_phone(value, opts)
      end
    end
  end

  defp validate_non_date_phone(value, opts) do
    case Keyword.get(opts, :phone_parser) || Keyword.get(opts, :phone_validator) do
      nil -> deterministic_validate(value)
      parser -> parser_validate(parser, value, opts)
    end
  end

  defp date_like?(value) do
    value
    |> String.trim()
    |> then(
      &Regex.match?(
        ~r/^(?:\d{4}[-. \/]\d{1,2}[-. \/]\d{1,2}|\d{1,2}[-. \/]\d{1,2}[-. \/]\d{2,4})$/,
        &1
      )
    )
  end

  defp reject_obvious_phone_junk(value) do
    digits = normalized_phone_digits(value)

    cond do
      byte_size(digits) < 7 -> {:error, :too_short_phone_candidate}
      repeated_digits?(digits) -> {:error, :repeated_digits}
      sequential_digits?(digits) -> {:error, :sequential_digits}
      true -> :ok
    end
  end

  defp parser_validate(parser, value, opts) when is_atom(parser) do
    if Code.ensure_loaded?(parser) do
      cond do
        function_exported?(parser, :valid?, 2) ->
          parser_result(parser.valid?(value, opts))

        function_exported?(parser, :valid?, 1) ->
          parser_result(parser.valid?(value))

        function_exported?(parser, :parse, 2) ->
          parser_result(parser.parse(value, opts))

        true ->
          deterministic_validate(value)
      end
    else
      {:error, {:missing_optional_dependency, parser}}
    end
  end

  defp parser_validate(parser, value, opts) when is_function(parser, 2) do
    parser_result(parser.(value, opts))
  end

  defp parser_validate(parser, value, _opts) when is_function(parser, 1) do
    parser_result(parser.(value))
  end

  defp parser_validate(_parser, value, _opts), do: deterministic_validate(value)

  defp parser_result(true), do: {:ok, %{validation: :parser}}
  defp parser_result(false), do: {:error, :parser_rejected}
  defp parser_result(:ok), do: {:ok, %{validation: :parser}}

  defp parser_result({:ok, metadata}) when is_map(metadata),
    do: {:ok, Map.put_new(metadata, :validation, :parser)}

  defp parser_result({:error, reason}), do: {:error, reason}
  defp parser_result(_other), do: {:error, :invalid_parser_result}

  defp deterministic_validate(value) do
    digits = normalized_phone_digits(value)

    area = String.slice(digits, 0, 3)
    exchange = String.slice(digits, 3, 3)

    case deterministic_phone_error(digits, area, exchange) do
      nil -> {:ok, %{country: :us, context_words: ["phone", "mobile", "tel", "call"]}}
      reason -> {:error, reason}
    end
  end

  defp normalized_phone_digits(value) do
    value
    |> String.split(~r/x/i, parts: 2)
    |> hd()
    |> String.replace(~r/\D/, "")
    |> trim_country_prefix()
  end

  defp trim_country_prefix("001" <> rest = digits) when byte_size(digits) == 13, do: rest
  defp trim_country_prefix("1" <> rest = digits) when byte_size(digits) == 11, do: rest
  defp trim_country_prefix(digits), do: digits

  defp deterministic_phone_error(digits, area, exchange) do
    cond do
      String.length(digits) not in [8, 9, 10, 12] -> :invalid_length
      repeated_digits?(digits) -> :repeated_digits
      area in ["000"] -> :invalid_area
      exchange in ["000"] -> :invalid_exchange
      digits == "0000000000" -> :invalid_number
      true -> nil
    end
  end

  defp repeated_digits?(digits) do
    unique_digit_count =
      digits
      |> String.graphemes()
      |> MapSet.new()
      |> MapSet.size()

    unique_digit_count == 1
  end

  defp sequential_digits?(digits) when byte_size(digits) >= 8 do
    digits in ["12345678", "123456789", "1234567890", "98765432", "987654321", "9876543210"]
  end

  defp sequential_digits?(_digits), do: false
end
