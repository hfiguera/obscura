defmodule Obscura.Context.Window do
  @moduledoc """
  Byte-window helpers for context enhancement.
  """

  @doc """
  Returns nearby text around a byte span.
  """
  @spec around(String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: String.t()
  def around(text, start, end_offset, window)
      when is_binary(text) and is_integer(start) and is_integer(end_offset) and is_integer(window) do
    left = max(start - window, 0)
    right = min(end_offset + window, byte_size(text))
    byte_length = right - left

    binary_part(text, left, byte_length)
  rescue
    ArgumentError -> ""
  end
end
