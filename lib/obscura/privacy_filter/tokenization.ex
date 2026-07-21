defmodule Obscura.PrivacyFilter.Tokenization do
  @moduledoc """
  Tokenization helpers for future native privacy-filter support.
  """

  alias Obscura.Tiktoken
  alias Obscura.Tiktoken.Encoding
  alias Obscura.Tiktoken.Offsets

  @type tokenization :: %{
          text: String.t(),
          encoding_name: String.t(),
          token_ids: [non_neg_integer()],
          pad_token_id: non_neg_integer(),
          decoded_text: String.t(),
          decoded_mismatch: boolean(),
          char_starts: [non_neg_integer()],
          char_ends: [non_neg_integer()]
        }

  @spec from_config(map(), String.t()) :: {:ok, tokenization()} | {:error, term()}
  def from_config(config, text) when is_map(config) and is_binary(text) do
    with {:ok, encoding_name} <- encoding_name(config),
         {:ok, encoding} <- Tiktoken.get_encoding(encoding_name) do
      tokenize(encoding, text)
    end
  end

  @spec tokenize(Encoding.t(), String.t()) :: {:ok, tokenization()} | {:error, term()}
  def tokenize(%Encoding{} = encoding, text) when is_binary(text) do
    with {:ok, token_ids} <- Encoding.encode(encoding, text, allowed_special: :all),
         {:ok, {decoded_text, char_starts, char_ends}} <-
           Offsets.token_char_ranges(token_ids, encoding),
         {:ok, pad_token_id} <- pad_token_id(encoding) do
      {:ok,
       %{
         text: text,
         encoding_name: encoding.name,
         token_ids: token_ids,
         pad_token_id: pad_token_id,
         decoded_text: decoded_text,
         decoded_mismatch: decoded_text != text,
         char_starts: char_starts,
         char_ends: char_ends
       }}
    end
  end

  defp encoding_name(%{"encoding" => encoding}) when is_binary(encoding) and encoding != "" do
    {:ok, encoding}
  end

  defp encoding_name(%{encoding: encoding}) when is_binary(encoding) and encoding != "" do
    {:ok, encoding}
  end

  defp encoding_name(_config), do: {:error, :missing_privacy_filter_encoding}

  defp pad_token_id(%Encoding{eot_token: token}) when is_integer(token), do: {:ok, token}
  defp pad_token_id(%Encoding{name: name}), do: {:error, {:encoding_missing_eot_token, name}}
end
