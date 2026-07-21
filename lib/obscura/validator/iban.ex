defmodule Obscura.Validator.IBAN do
  @moduledoc """
  IBAN checksum validator for Phase 1 fixture-covered countries.
  """

  @lengths %{
    "DE" => 22,
    "GB" => 22,
    "FR" => 27,
    "NL" => 18
  }

  @doc """
  Returns true when an IBAN has a supported country, length, format, and mod-97 checksum.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(iban) when is_binary(iban) do
    normalized =
      iban
      |> String.replace(" ", "")
      |> String.upcase()

    country = String.slice(normalized, 0, 2)

    with {:ok, expected_length} <- Map.fetch(@lengths, country),
         true <- String.length(normalized) == expected_length,
         true <- Regex.match?(~r/^[A-Z]{2}\d{2}[A-Z0-9]+$/, normalized) do
      checksum_valid?(normalized)
    else
      _other -> false
    end
  end

  def valid?(_iban), do: false

  defp checksum_valid?(normalized) do
    rearranged = String.slice(normalized, 4..-1//1) <> String.slice(normalized, 0, 4)

    rearranged
    |> String.graphemes()
    |> Enum.reduce_while(0, fn char, remainder ->
      case iban_integer(char) do
        {:ok, value} -> {:cont, reduce_digits(Integer.to_string(value), remainder)}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      1 -> true
      _other -> false
    end
  end

  defp iban_integer(<<char>>) when char in ?0..?9, do: {:ok, char - ?0}
  defp iban_integer(<<char>>) when char in ?A..?Z, do: {:ok, char - ?A + 10}
  defp iban_integer(_char), do: :error

  defp reduce_digits(digits, remainder) do
    digits
    |> String.graphemes()
    |> Enum.reduce(remainder, fn digit, acc -> rem(acc * 10 + String.to_integer(digit), 97) end)
  end
end
