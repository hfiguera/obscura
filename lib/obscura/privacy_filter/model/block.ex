defmodule Obscura.PrivacyFilter.Model.Block do
  @moduledoc """
  One privacy-filter transformer block: attention followed by MoE MLP.
  """

  alias Obscura.PrivacyFilter.Model.Attention
  alias Obscura.PrivacyFilter.Model.MLP

  @spec forward(Nx.Tensor.t(), map(), map(), keyword()) :: Nx.Tensor.t()
  def forward(input, params, config, opts \\ []) do
    input
    |> Attention.forward(Map.fetch!(params, :attn), config, opts)
    |> MLP.forward(Map.fetch!(params, :mlp), config, opts)
  end

  @spec debug(Nx.Tensor.t(), map(), map(), keyword()) :: map()
  def debug(input, params, config, opts \\ []) do
    attention = Attention.debug(input, Map.fetch!(params, :attn), config, opts)
    mlp = MLP.debug(attention.output, Map.fetch!(params, :mlp), config, opts)

    %{
      input: input,
      attention: attention,
      mlp: mlp,
      output: mlp.output
    }
  end
end
