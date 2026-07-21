defmodule Obscura.Tiktoken do
  @moduledoc """
  Tiktoken-compatible byte-pair encodings used by Obscura.

  This module intentionally implements the subset of Python tiktoken that
  Obscura needs for privacy-filter tokenization. It does not fetch assets from
  the network at runtime.
  """

  alias Obscura.Tiktoken.Registry

  @type encoding :: Obscura.Tiktoken.Encoding.t()

  @doc "Loads a supported encoding from verified local assets."
  @spec get_encoding(String.t() | atom()) :: {:ok, encoding()} | {:error, term()}
  def get_encoding(name), do: Registry.get_encoding(name)

  @spec get_encoding!(String.t() | atom()) :: encoding()
  def get_encoding!(name) do
    case get_encoding(name) do
      {:ok, encoding} ->
        encoding

      {:error, _reason} ->
        raise ArgumentError, "failed to load tiktoken encoding"
    end
  end

  @doc "Lists the supported encoding names."
  @spec list_encoding_names() :: [String.t()]
  def list_encoding_names, do: Registry.list_encoding_names()

  @spec encoding_name_for_model(String.t()) :: {:ok, String.t()} | {:error, term()}
  def encoding_name_for_model(model_name) when is_binary(model_name) do
    Registry.encoding_name_for_model(model_name)
  end

  @spec encoding_for_model(String.t()) :: {:ok, encoding()} | {:error, term()}
  def encoding_for_model(model_name) when is_binary(model_name) do
    with {:ok, encoding_name} <- encoding_name_for_model(model_name) do
      get_encoding(encoding_name)
    end
  end
end
