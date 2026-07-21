defmodule Obscura.PrivacyFilter.Model.RotaryEmbedding do
  @moduledoc """
  Rotary positional embedding helpers for privacy-filter attention.

  The implementation follows the YaRN-style scaling path from the Python
  privacy-filter reference.
  """

  alias Obscura.PrivacyFilter.Model.BFloat16

  @type options :: [
          head_dim: pos_integer(),
          base: number(),
          initial_context_length: pos_integer(),
          scaling_factor: number(),
          ntk_alpha: number(),
          ntk_beta: number(),
          round_bf16: boolean()
        ]

  @spec cos_sin(pos_integer(), options()) :: {Nx.Tensor.t(), Nx.Tensor.t()}
  def cos_sin(num_tokens, opts) when is_integer(num_tokens) and num_tokens > 0 do
    {concentration, inv_freq} = concentration_and_inv_freq(opts)
    half_dim = div(Keyword.fetch!(opts, :head_dim), 2)
    positions = Nx.iota({num_tokens}, type: {:f, 32}) |> Nx.reshape({num_tokens, 1})
    inv_freq = Nx.reshape(inv_freq, {1, half_dim})
    freqs = Nx.multiply(positions, inv_freq)

    {Nx.multiply(Nx.cos(freqs), concentration), Nx.multiply(Nx.sin(freqs), concentration)}
  end

  @spec apply_flattened(Nx.Tensor.t(), Nx.Tensor.t(), options()) :: {Nx.Tensor.t(), Nx.Tensor.t()}
  def apply_flattened(query, key, opts) do
    head_dim = Keyword.fetch!(opts, :head_dim)
    {batch, tokens, query_width} = Nx.shape(query)
    {_batch, _tokens, key_width} = Nx.shape(key)

    query_heads = div(query_width, head_dim)
    key_heads = div(key_width, head_dim)

    query = Nx.reshape(query, {batch, tokens, query_heads, head_dim})
    key = Nx.reshape(key, {batch, tokens, key_heads, head_dim})

    {cos, sin} = cos_sin(tokens, opts)
    cos = Nx.reshape(cos, {1, tokens, 1, div(head_dim, 2)})
    sin = Nx.reshape(sin, {1, tokens, 1, div(head_dim, 2)})
    {cos, sin} = maybe_round_bf16({cos, sin}, opts)

    {
      query
      |> apply_to_heads(cos, sin, Keyword.get(opts, :round_bf16, false))
      |> maybe_round_bf16(opts)
      |> Nx.reshape({batch, tokens, query_width}),
      key
      |> apply_to_heads(cos, sin, Keyword.get(opts, :round_bf16, false))
      |> maybe_round_bf16(opts)
      |> Nx.reshape({batch, tokens, key_width})
    }
  end

  defp maybe_round_bf16({left, right}, opts) do
    if Keyword.get(opts, :round_bf16, false) do
      {BFloat16.round_to_nearest_even(left), BFloat16.round_to_nearest_even(right)}
    else
      {left, right}
    end
  end

  defp maybe_round_bf16(tensor, opts) when is_list(opts) do
    if Keyword.get(opts, :round_bf16, false),
      do: BFloat16.round_to_nearest_even(tensor),
      else: tensor
  end

  defp maybe_round_bf16(tensor, true), do: BFloat16.round_to_nearest_even(tensor)
  defp maybe_round_bf16(tensor, false), do: tensor

  defp apply_to_heads(tensor, cos, sin, round_bf16?) do
    shape = Nx.shape(tensor)
    width = elem(shape, tuple_size(shape) - 1)

    x1 = Nx.slice_along_axis(tensor, 0, width, axis: -1, strides: 2)
    x2 = Nx.slice_along_axis(tensor, 1, width - 1, axis: -1, strides: 2)

    o1 =
      x1
      |> Nx.multiply(cos)
      |> maybe_round_bf16(round_bf16?)
      |> Nx.subtract(x2 |> Nx.multiply(sin) |> maybe_round_bf16(round_bf16?))
      |> maybe_round_bf16(round_bf16?)

    o2 =
      x2
      |> Nx.multiply(cos)
      |> maybe_round_bf16(round_bf16?)
      |> Nx.add(x1 |> Nx.multiply(sin) |> maybe_round_bf16(round_bf16?))
      |> maybe_round_bf16(round_bf16?)

    [o1, o2]
    |> Nx.stack(axis: -1)
    |> Nx.reshape(shape)
  end

  defp concentration_and_inv_freq(opts) do
    head_dim = Keyword.fetch!(opts, :head_dim)
    base = Keyword.fetch!(opts, :base)
    initial_context_length = Keyword.fetch!(opts, :initial_context_length)
    scaling_factor = Keyword.get(opts, :scaling_factor, 1.0)
    ntk_alpha = Keyword.get(opts, :ntk_alpha, 1.0)
    ntk_beta = Keyword.get(opts, :ntk_beta, 32.0)

    positions = Nx.multiply(Nx.iota({div(head_dim, 2)}, type: {:f, 32}), 2)
    freq = Nx.pow(Nx.broadcast(base, Nx.shape(positions)), Nx.divide(positions, head_dim))

    if scaling_factor > 1.0 do
      concentration = 0.1 * :math.log(scaling_factor) + 1.0
      half_dim = head_dim / 2

      low =
        half_dim *
          :math.log(initial_context_length / (ntk_beta * 2 * :math.pi())) /
          :math.log(base)

      high =
        half_dim *
          :math.log(initial_context_length / (ntk_alpha * 2 * :math.pi())) /
          :math.log(base)

      interpolation = Nx.divide(1.0, Nx.multiply(scaling_factor, freq))
      extrapolation = Nx.divide(1.0, freq)

      ramp =
        Nx.iota({div(head_dim, 2)}, type: {:f, 32})
        |> Nx.subtract(low)
        |> Nx.divide(Nx.subtract(high, low))

      mask = Nx.subtract(1, Nx.clip(ramp, 0, 1))

      inv_freq =
        interpolation
        |> Nx.multiply(Nx.subtract(1, mask))
        |> Nx.add(Nx.multiply(extrapolation, mask))

      {concentration, inv_freq}
    else
      {1.0, Nx.divide(1.0, freq)}
    end
  end
end
