defmodule Obscura.Internal.ResultText do
  @moduledoc false

  alias Obscura.Analyzer.Result

  @spec maybe_materialize(String.t(), keyword()) :: String.t() | nil
  def maybe_materialize(value, opts) when is_binary(value) and is_list(opts) do
    if Keyword.get(opts, :include_text, true), do: value, else: nil
  end

  @spec finalize([Result.t()], String.t(), boolean()) :: [Result.t()]
  def finalize(results, _source, false) do
    Enum.map(results, fn
      %Result{text: nil} = result -> result
      %Result{} = result -> %{result | text: nil}
    end)
  end

  def finalize(results, source, true) do
    Enum.map(results, fn %Result{} = result ->
      %{result | text: owned_slice(source, result.byte_start, result.byte_end)}
    end)
  end

  @spec borrowed_slice(String.t(), non_neg_integer(), non_neg_integer()) :: String.t()
  def borrowed_slice(source, byte_start, byte_end)
      when is_binary(source) and is_integer(byte_start) and is_integer(byte_end) do
    binary_part(source, byte_start, byte_end - byte_start)
  end

  @spec owned_slice(String.t(), non_neg_integer(), non_neg_integer()) :: String.t()
  def owned_slice(source, byte_start, byte_end) do
    value = borrowed_slice(source, byte_start, byte_end)

    if :binary.referenced_byte_size(value) > byte_size(value) do
      :binary.copy(value)
    else
      value
    end
  end
end
