defmodule Obscura.Language do
  @moduledoc """
  Safe language normalization for analyzer options.
  """

  @supported [:en, :es, :fr, :de, :pt, :it, :unknown]

  @doc """
  Returns supported language tags.
  """
  @spec supported() :: [atom()]
  def supported, do: @supported

  @doc """
  Normalizes a caller-provided language without creating atoms dynamically.
  """
  @spec normalize(atom() | String.t()) :: {:ok, atom()} | {:error, term()}
  def normalize(language) when language in @supported, do: {:ok, language}

  def normalize(language) when is_binary(language) do
    case Enum.find(@supported, &(Atom.to_string(&1) == language)) do
      nil -> {:error, :unsupported_language}
      language -> {:ok, language}
    end
  end

  def normalize(_language), do: {:error, :unsupported_language}
end
