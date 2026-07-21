defmodule Obscura.PrivacyFilter.Model.BFloat16 do
  @moduledoc false

  import Bitwise, only: [&&&: 2, >>>: 2]

  @spec round_to_nearest_even(Nx.Tensor.t()) :: Nx.Tensor.t()
  def round_to_nearest_even(tensor) do
    bits = tensor |> Nx.as_type({:f, 32}) |> Nx.bitcast({:u, 32})
    lsb = bits |> Nx.right_shift(16) |> Nx.bitwise_and(1)
    bias = Nx.add(0x7FFF, lsb)

    bits
    |> Nx.add(bias)
    |> Nx.bitwise_and(0xFFFF0000)
    |> Nx.bitcast({:f, 32})
  end

  @spec round_scalar_to_nearest_even(number()) :: float()
  def round_scalar_to_nearest_even(value) when is_number(value) do
    <<bits::32-native>> = <<:erlang.float(value)::float-32-native>>
    lsb = bits >>> 16 &&& 1
    rounded = bits + 0x7FFF + lsb &&& 0xFFFF0000
    <<result::float-32-native>> = <<rounded::32-native>>
    result
  end
end
