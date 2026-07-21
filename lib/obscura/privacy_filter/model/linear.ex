defmodule Obscura.PrivacyFilter.Model.Linear do
  @moduledoc false

  alias Obscura.PrivacyFilter.Model.BFloat16

  @spec apply(Nx.Tensor.t(), Nx.Tensor.t(), Nx.Tensor.t() | nil, keyword()) :: Nx.Tensor.t()
  def apply(input, weight, bias \\ nil, opts \\ []) do
    output = Nx.dot(input, [-1], Nx.transpose(weight), [0])

    output =
      if is_nil(bias) do
        output
      else
        Nx.add(output, bias)
      end

    case Nx.type(weight) do
      {:bf, 16} ->
        if Keyword.get(opts, :torch_bf16_parity, false),
          do: BFloat16.round_to_nearest_even(output),
          else: output

      _other ->
        output
    end
  end
end
