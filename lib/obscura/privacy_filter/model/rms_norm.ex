defmodule Obscura.PrivacyFilter.Model.RMSNorm do
  @moduledoc """
  RMSNorm used by privacy-filter transformer blocks.

  Mirrors `opf._model.model.RMSNorm`: inputs are normalized over the final
  dimension in float32, multiplied by a learned scale, and returned in the
  original tensor type.
  """

  alias Obscura.PrivacyFilter.Model.BFloat16

  @spec forward(Nx.Tensor.t(), Nx.Tensor.t(), keyword()) :: Nx.Tensor.t()
  def forward(input, scale, opts \\ []) do
    eps = Keyword.get(opts, :eps, 1.0e-5)
    input_type = Nx.type(input)
    t = Nx.as_type(input, {:f, 32})
    mean_square = t |> Nx.pow(2) |> Nx.mean(axes: [-1], keep_axes: true)

    output =
      t
      |> Nx.multiply(Nx.rsqrt(Nx.add(mean_square, eps)))
      |> Nx.multiply(Nx.as_type(scale, {:f, 32}))

    case input_type do
      {:bf, 16} ->
        if Keyword.get(opts, :torch_bf16_parity, false),
          do: BFloat16.round_to_nearest_even(output),
          else: Nx.as_type(output, input_type)

      _other ->
        Nx.as_type(output, input_type)
    end
  end
end
