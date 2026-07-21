defmodule Obscura.Input do
  @moduledoc false

  @spec validate_text(term()) :: :ok | {:error, atom()}
  def validate_text(text) when is_binary(text) do
    if String.valid?(text), do: :ok, else: {:error, :invalid_utf8}
  end

  def validate_text(_text), do: {:error, :invalid_text}

  @spec validate_texts(term()) :: :ok | {:error, atom()}
  def validate_texts(texts) when is_list(texts) do
    cond do
      List.improper?(texts) -> {:error, :invalid_analyze_many_texts}
      not Enum.all?(texts, &is_binary/1) -> {:error, :invalid_analyze_many_texts}
      Enum.all?(texts, &String.valid?/1) -> :ok
      true -> {:error, :invalid_utf8}
    end
  end

  def validate_texts(_texts), do: {:error, :invalid_analyze_many_texts}
end
