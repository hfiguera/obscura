defmodule Obscura.Structured.Path do
  @moduledoc """
  Structured path helpers.
  """

  @doc """
  Appends a segment to a structured path.
  """
  @spec append([term()], term()) :: [term()]
  def append(path, segment), do: path ++ [segment]
end
