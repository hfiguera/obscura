defmodule Obscura.Analyzer do
  @moduledoc """
  String analyzer facade for Obscura recognizers.
  """

  alias Obscura.Analyzer.Engine
  alias Obscura.Input

  @doc """
  Analyzes text with the configured recognizer registry.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def analyze(text, opts \\ [])

  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    with :ok <- Input.validate_text(text) do
      Engine.analyze(text, opts)
    end
  end

  def analyze(_text, _opts), do: {:error, :invalid_analyze_arguments}

  @doc """
  Analyzes multiple texts with the configured recognizer registry.
  """
  @spec analyze_many([String.t()], keyword()) ::
          {:ok, [[Obscura.Analyzer.Result.t()]]} | {:error, term()}
  def analyze_many(texts, opts \\ [])

  def analyze_many(texts, opts) when is_list(texts) and is_list(opts) do
    with :ok <- Input.validate_texts(texts) do
      Engine.analyze_many(texts, opts)
    end
  end

  def analyze_many(_texts, _opts), do: {:error, :invalid_analyze_many_arguments}
end
