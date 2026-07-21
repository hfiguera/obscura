defmodule Obscura.Recognizer.Phone.ExPhoneNumberValidator do
  @moduledoc """
  Optional `ex_phone_number` validator for parser-backed phone recognition.

  This module intentionally keeps `ex_phone_number` optional. If the dependency
  is not available, validation returns a safe missing-dependency error.
  """

  @default_regions ["US", "GB", "DE", "FR", "IL", "IN", "CA", "BR", "JP", "CN"]

  @doc """
  Validates a phone candidate using `ex_phone_number`.
  """
  @spec valid?(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def valid?(value, opts) when is_binary(value) and is_list(opts) do
    if Code.ensure_loaded?(ExPhoneNumber) do
      validate_with_parser(value, opts)
    else
      {:error, {:missing_optional_dependency, :ex_phone_number}}
    end
  end

  defp validate_with_parser(value, opts) do
    value = normalize_extension(value)

    value
    |> regions(opts)
    |> Enum.find_value(&valid_parse(value, &1))
    |> case do
      nil -> {:error, :invalid_phone_number}
      metadata -> {:ok, metadata}
    end
  end

  defp valid_parse(value, region) do
    case ExPhoneNumber.parse(value, region) do
      {:ok, phone_number} ->
        if ExPhoneNumber.is_valid_number?(phone_number) do
          metadata(phone_number, region)
        end

      _error ->
        nil
    end
  rescue
    _error -> nil
  end

  defp metadata(phone_number, parsed_with_region) do
    region = ExPhoneNumber.Metadata.get_region_code_for_number(phone_number)

    %{
      validation: :ex_phone_number,
      phone_region: region,
      parsed_with_region: parsed_with_region,
      phone_e164: ExPhoneNumber.format(phone_number, :e164),
      phone_number_type: ExPhoneNumber.get_number_type(phone_number),
      context_words: ["phone", "number", "telephone", "cell", "cellphone", "mobile", "call"]
    }
  end

  defp regions(value, opts) do
    if String.trim_leading(value) |> String.starts_with?("+") do
      [nil]
    else
      case Keyword.get(opts, :phone_regions, @default_regions) do
        [] -> @default_regions
        regions -> regions
      end
      |> List.wrap()
      |> Enum.map(&normalize_region/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end
  end

  defp normalize_region(region) when is_atom(region),
    do: region |> Atom.to_string() |> normalize_region()

  defp normalize_region("UK"), do: "GB"
  defp normalize_region(region) when is_binary(region), do: String.upcase(region)
  defp normalize_region(_region), do: nil

  defp normalize_extension(value) do
    Regex.replace(~r/\s*(?:ext\.?|extension|x)\s*(\d{1,7})\s*$/iu, value, " ext. \\1")
  end
end
