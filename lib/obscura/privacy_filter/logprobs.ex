defmodule Obscura.PrivacyFilter.Logprobs do
  @moduledoc false

  @type mode :: :reference | :raw_logits

  @spec to_tensor(Nx.Tensor.t(), mode()) :: {:ok, Nx.Tensor.t()} | {:error, term()}
  def to_tensor(logits, mode) do
    case Nx.shape(logits) do
      {1, _tokens, _labels} -> {:ok, convert(logits, mode)}
      shape -> {:error, {:privacy_filter_logits_shape_mismatch, shape}}
    end
  rescue
    error -> {:error, {:privacy_filter_logits_decode_failed, error.__struct__}}
  end

  @spec to_rows(Nx.Tensor.t(), mode()) :: {:ok, [list(float())]} | {:error, term()}
  def to_rows(logits, mode) do
    case to_tensor(logits, mode) do
      {:ok, tensor} ->
        [rows] = Nx.to_list(tensor)

        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, {:privacy_filter_logits_decode_failed, error.__struct__}}
  end

  defp convert(logits, :reference), do: reference_log_softmax(logits)
  defp convert(logits, :raw_logits), do: logits

  defp reference_log_softmax(tensor) do
    max_value = Nx.reduce_max(tensor, axes: [-1], keep_axes: true)
    shifted = Nx.subtract(tensor, max_value)
    shifted |> Nx.subtract(Nx.log(Nx.sum(Nx.exp(shifted), axes: [-1], keep_axes: true)))
  end
end
