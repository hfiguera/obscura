defmodule Obscura.Tiktoken.Loader do
  @moduledoc false

  @spec load_tiktoken_bpe(Path.t(), keyword()) ::
          {:ok, %{binary() => non_neg_integer()}} | {:error, term()}
  def load_tiktoken_bpe(path, opts \\ []) when is_binary(path) do
    expected_hash = Keyword.get(opts, :expected_hash)

    with {:ok, contents} <- File.read(path),
         :ok <- validate_hash(contents, expected_hash),
         {:ok, ranks} <- parse(contents) do
      {:ok, ranks}
    else
      {:error, %File.Error{} = error} -> {:error, {:file_error, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec check_hash(binary(), String.t()) :: boolean()
  def check_hash(contents, expected_hash) when is_binary(contents) and is_binary(expected_hash) do
    actual_hash = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
    actual_hash == String.downcase(expected_hash)
  end

  defp validate_hash(_contents, nil), do: :ok

  defp validate_hash(contents, expected_hash) do
    if check_hash(contents, expected_hash) do
      :ok
    else
      actual_hash = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
      {:error, {:hash_mismatch, expected_hash, actual_hash}}
    end
  end

  defp parse(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}, MapSet.new()}, &parse_entry/2)
    |> case do
      {:ok, ranks, _seen_ranks} -> {:ok, ranks}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_entry({line, line_number}, {:ok, ranks, seen_ranks}) do
    case parse_line(line) do
      {:ok, token, rank} -> put_rank(token, rank, line_number, ranks, seen_ranks)
      {:error, reason} -> {:halt, {:error, {:invalid_bpe_line, line_number, reason}}}
    end
  end

  defp put_rank(token, rank, line_number, ranks, seen_ranks) do
    cond do
      Map.has_key?(ranks, token) ->
        {:halt, {:error, {:duplicate_bpe_token, line_number}}}

      MapSet.member?(seen_ranks, rank) ->
        {:halt, {:error, {:duplicate_bpe_rank, line_number, rank}}}

      true ->
        {:cont, {:ok, Map.put(ranks, token, rank), MapSet.put(seen_ranks, rank)}}
    end
  end

  defp parse_line(line) do
    case String.split(line) do
      [encoded_token, rank_text] ->
        with {:ok, token} <- Base.decode64(encoded_token),
             {rank, ""} <- Integer.parse(rank_text),
             true <- rank >= 0 do
          {:ok, token, rank}
        else
          :error -> {:error, :invalid_base64}
          false -> {:error, :invalid_rank}
          _ -> {:error, :invalid_rank}
        end

      _other ->
        {:error, :invalid_column_count}
    end
  end
end
