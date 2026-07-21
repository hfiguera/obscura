defmodule Obscura.PrivacyFilter.Weights.MXFP4 do
  @moduledoc """
  MXFP4 tensor decoding helpers for privacy-filter expert weights.

  MXFP4 stores two 4-bit floating point values in each byte plus one exponent
  scale per block row. The low nibble is decoded before the high nibble, matching
  the privacy-filter reference implementation notes.
  """

  @fp4_values [
    0.0,
    0.5,
    1.0,
    1.5,
    2.0,
    3.0,
    4.0,
    6.0,
    -0.0,
    -0.5,
    -1.0,
    -1.5,
    -2.0,
    -3.0,
    -4.0,
    -6.0
  ]

  @spec decode(Nx.Tensor.t(), Nx.Tensor.t()) :: {:ok, Nx.Tensor.t()} | {:error, term()}
  def decode(blocks, scales) do
    block_shape = blocks |> Nx.shape() |> Tuple.to_list()
    scale_shape = scales |> Nx.shape() |> Tuple.to_list()
    {_block_width, block_prefix_shape} = List.pop_at(block_shape, -1)

    if block_prefix_shape == scale_shape do
      {prefix, [groups, block_width]} = Enum.split(block_shape, length(block_shape) - 2)
      output_shape = List.to_tuple(prefix ++ [groups * block_width * 2])

      block_values = blocks |> Nx.as_type({:u, 8}) |> Nx.to_flat_list()
      scale_values = scales |> Nx.as_type({:s, 32}) |> Nx.to_flat_list()

      values =
        block_values
        |> Enum.chunk_every(block_width)
        |> Enum.zip(scale_values)
        |> Enum.flat_map(&decode_row/1)

      {:ok, Nx.tensor(values, type: {:f, 32}) |> Nx.reshape(output_shape)}
    else
      {:error, {:mxfp4_shape_mismatch, block_shape, scale_shape}}
    end
  end

  defp decode_row({row_blocks, scale}) do
    exponent = scale - 127
    Enum.flat_map(row_blocks, &decode_byte(&1, exponent))
  end

  defp decode_byte(byte, exponent) do
    low = Bitwise.band(byte, 0x0F)
    high = Bitwise.bsr(byte, 4)
    [fp4(low, exponent), fp4(high, exponent)]
  end

  defp fp4(index, exponent), do: Enum.at(@fp4_values, index) * :math.pow(2.0, exponent)
end
