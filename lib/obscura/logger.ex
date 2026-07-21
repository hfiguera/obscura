defmodule Obscura.Logger do
  @moduledoc """
  Logger-safe helpers for redacting terms before applications log them.
  """

  alias Obscura.Telemetry

  @doc """
  Redacts Logger metadata while preserving keyword-list or map shape.
  """
  @spec redact_metadata(keyword() | map(), keyword()) ::
          {:ok, keyword() | map()} | {:error, term()}
  def redact_metadata(metadata, opts \\ []) when is_list(opts) do
    start = System.monotonic_time()

    result =
      metadata
      |> redact_term(opts)
      |> case do
        {:ok, redacted} -> {:ok, redacted}
        {:error, reason} -> {:error, reason}
      end

    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :logger, :redact_metadata, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: status(result), input_type: input_type(metadata), result_count: 0}
    )

    result
  end

  @doc """
  Redacts any term using structured redaction.
  """
  @spec redact_term(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def redact_term(term, opts \\ []) when is_list(opts) do
    with {:ok, result} <-
           Obscura.Structured.redact(term, Keyword.put_new(opts, :telemetry, false)) do
      {:ok, result.data}
    end
  end

  @doc """
  Safely inspects a redacted term.
  """
  @spec safe_inspect(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def safe_inspect(term, opts \\ []) when is_list(opts) do
    with {:ok, redacted} <- redact_term(term, opts) do
      {:ok, inspect(redacted)}
    end
  end

  defp status({:ok, _value}), do: :ok
  defp status({:error, _reason}), do: :error

  defp input_type(value) when is_map(value), do: :map
  defp input_type(value) when is_list(value), do: :list
  defp input_type(_value), do: :term
end
