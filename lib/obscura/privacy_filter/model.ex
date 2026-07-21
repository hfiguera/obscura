defmodule Obscura.PrivacyFilter.Model do
  @moduledoc """
  Native privacy-filter transformer forward pass.

  This module executes a loaded privacy-filter checkpoint represented as Nx
  tensors. It is intentionally separate from checkpoint loading and serving so
  each layer can be tested independently.
  """

  alias Obscura.PrivacyFilter.Model.Block
  alias Obscura.PrivacyFilter.Model.Linear
  alias Obscura.PrivacyFilter.Model.RMSNorm

  @spec forward_result(Nx.Tensor.t(), map(), map(), keyword()) ::
          {:ok, Nx.Tensor.t()} | {:error, term()}
  def forward_result(token_ids, params, config, opts \\ []) do
    {:ok, forward(token_ids, params, config, opts)}
  rescue
    error ->
      {:error, {:privacy_filter_model_forward_failed, error.__struct__}}
  end

  @spec forward(Nx.Tensor.t(), map(), map(), keyword()) :: Nx.Tensor.t()
  def forward(token_ids, params, config, opts \\ []) do
    if tuple_size(Nx.shape(token_ids)) != 2 do
      raise ArgumentError, "privacy-filter model expects token ids with shape [batch, tokens]"
    end

    hidden =
      params
      |> Map.fetch!(:embedding)
      |> Nx.take(token_ids)

    hidden =
      params
      |> Map.fetch!(:blocks)
      |> Enum.reduce(hidden, fn block_params, acc ->
        Block.forward(acc, block_params, config, opts)
      end)

    hidden
    |> RMSNorm.forward(Map.fetch!(params, :norm_scale), opts)
    |> Linear.apply(
      Map.fetch!(params, :unembedding_weight),
      Map.get(params, :unembedding_bias),
      opts
    )
  end

  @spec debug(Nx.Tensor.t(), map(), map(), keyword()) :: map()
  def debug(token_ids, params, config, opts \\ []) do
    if tuple_size(Nx.shape(token_ids)) != 2 do
      raise ArgumentError, "privacy-filter model expects token ids with shape [batch, tokens]"
    end

    input =
      params
      |> Map.fetch!(:embedding)
      |> Nx.take(token_ids)

    {hidden, blocks} =
      params
      |> Map.fetch!(:blocks)
      |> Enum.map_reduce(input, fn block_params, acc ->
        block = Block.debug(acc, block_params, config, opts)
        {block, block.output}
      end)
      |> then(fn {blocks, hidden} -> {hidden, blocks} end)

    final_norm = RMSNorm.forward(hidden, Map.fetch!(params, :norm_scale), opts)

    logits =
      Linear.apply(
        final_norm,
        Map.fetch!(params, :unembedding_weight),
        Map.get(params, :unembedding_bias)
      )

    %{
      embedding: input,
      blocks: blocks,
      final_norm: final_norm,
      logits: logits
    }
  end
end
