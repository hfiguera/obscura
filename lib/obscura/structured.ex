defmodule Obscura.Structured do
  @moduledoc """
  Public structured data redaction API.
  """

  alias Obscura.Structured.Engine

  @doc """
  Recursively analyzes structured data and returns redaction items.
  """
  @spec analyze(term(), keyword()) :: {:ok, [Obscura.Structured.Item.t()]} | {:error, term()}
  def analyze(data, opts \\ []) when is_list(opts) do
    with {:ok, result} <- redact(data, Keyword.put(opts, :dry_run, true)) do
      {:ok, result.items}
    end
  end

  @doc """
  Recursively redacts structured data.
  """
  @spec redact(term(), keyword()) :: {:ok, Obscura.Structured.Result.t()} | {:error, term()}
  def redact(data, opts \\ []) when is_list(opts) do
    Engine.redact(data, opts)
  end

  @doc false
  @spec redact_derived(struct(), keyword(), keyword()) ::
          {:ok, term(), [Obscura.Structured.Item.t()]} | {:error, term()}
  def redact_derived(struct, derive_opts, runtime_opts) do
    opts =
      runtime_opts
      |> Keyword.put(:field_policies, Keyword.get(derive_opts, :fields, []))
      |> Keyword.put(:traverse_structs, true)
      |> Keyword.put(:skip_protocol, true)

    with {:ok, result} <- redact(struct, opts) do
      {:ok, result.data, result.items}
    end
  end
end
