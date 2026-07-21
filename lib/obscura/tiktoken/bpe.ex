defmodule Obscura.Tiktoken.BPE do
  @moduledoc false

  @max_rank 4_294_967_295

  @spec encode_piece(binary(), %{binary() => non_neg_integer()}) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def encode_piece(<<>>, _ranks), do: {:ok, []}

  def encode_piece(piece, ranks) when is_binary(piece) and is_map(ranks) do
    case Map.fetch(ranks, piece) do
      {:ok, token} ->
        {:ok, [token]}

      :error ->
        encode_split_piece(piece, ranks)
    end
  end

  @spec encode_piece!(binary(), %{binary() => non_neg_integer()}) :: [non_neg_integer()]
  def encode_piece!(piece, ranks) do
    case encode_piece(piece, ranks) do
      {:ok, tokens} -> tokens
      {:error, _reason} -> raise ArgumentError, "failed to BPE encode piece"
    end
  end

  defp encode_split_piece(piece, ranks) do
    size = byte_size(piece)

    cond do
      size == 1 ->
        fetch_rank(piece, ranks)

      size < 100 ->
        {:ok,
         piece
         |> merge_tokens(ranks)
         |> Enum.map(&Map.fetch!(ranks, &1))}

      true ->
        # The simple merge algorithm is still exact; it is slower than
        # tiktoken's heap path, but keeps the first pure Elixir phase small.
        {:ok,
         piece
         |> merge_tokens(ranks)
         |> Enum.map(&Map.fetch!(ranks, &1))}
    end
  rescue
    KeyError -> {:error, :unknown_bpe_piece}
  end

  defp fetch_rank(piece, ranks) do
    case Map.fetch(ranks, piece) do
      {:ok, rank} -> {:ok, [rank]}
      :error -> {:error, :unknown_bpe_piece}
    end
  end

  defp merge_tokens(piece, ranks) do
    piece
    |> byte_tokens()
    |> merge_token_list(ranks)
  end

  defp byte_tokens(piece) do
    for <<byte <- piece>>, do: <<byte>>
  end

  defp merge_token_list([_single] = tokens, _ranks), do: tokens

  defp merge_token_list(tokens, ranks) do
    case best_pair(tokens, ranks) do
      {@max_rank, nil} ->
        tokens

      {_rank, index} ->
        tokens
        |> merge_at(index)
        |> merge_token_list(ranks)
    end
  end

  defp best_pair(tokens, ranks) do
    tokens
    |> Enum.chunk_every(2, 1, :discard)
    |> Stream.with_index()
    |> Enum.reduce({@max_rank, nil}, fn {[left, right], index}, {best_rank, best_index} ->
      rank = Map.get(ranks, left <> right, @max_rank)
      if rank < best_rank, do: {rank, index}, else: {best_rank, best_index}
    end)
  end

  defp merge_at(tokens, index) do
    {prefix, [left, right | suffix]} = Enum.split(tokens, index)
    prefix ++ [left <> right | suffix]
  end
end
