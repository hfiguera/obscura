defmodule Obscura.Validator.Luhn do
  @moduledoc """
  Luhn checksum validator for credit-card candidates.
  """

  @doc """
  Returns true when a digit string satisfies the Luhn checksum.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(digits) when is_binary(digits) do
    Regex.match?(~r/^\d+$/, digits) and checksum_valid?(digits)
  end

  def valid?(_digits), do: false

  defp checksum_valid?(digits) do
    checksum =
      digits
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.reduce({0, 0}, fn digit, {sum, index} ->
        {sum + luhn_digit(digit, index), index + 1}
      end)
      |> elem(0)

    rem(checksum, 10) == 0
  end

  defp luhn_digit(digit, index) do
    digit
    |> String.to_integer()
    |> maybe_double(index)
  end

  defp maybe_double(value, index) when rem(index, 2) == 1 do
    value
    |> Kernel.*(2)
    |> reduce_doubled()
  end

  defp maybe_double(value, _index), do: value

  defp reduce_doubled(value) when value > 9, do: value - 9
  defp reduce_doubled(value), do: value
end
