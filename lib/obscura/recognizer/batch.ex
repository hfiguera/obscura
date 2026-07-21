defmodule Obscura.Recognizer.Batch do
  @moduledoc false

  @spec run_many([String.t()], (String.t() -> {:ok, [term()]} | {:error, term()})) ::
          {:ok, [[term()]]} | {:error, term()}
  def run_many(texts, runner) when is_list(texts) and is_function(runner, 1) do
    texts
    |> Enum.reduce_while({:ok, []}, fn text, {:ok, rows} ->
      case runner.(text) do
        {:ok, outputs} -> {:cont, {:ok, [outputs | rows]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, reason} -> {:error, reason}
    end)
  end
end
