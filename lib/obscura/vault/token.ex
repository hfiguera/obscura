defmodule Obscura.Vault.Token do
  @moduledoc """
  Token formatting for reversible pseudonymization vaults.
  """

  @default_options [
    token_prefix: "<<",
    token_suffix: ">>",
    token_separator: "_",
    token_width: 3,
    token_case: :upper,
    token_strategy: :sequential
  ]
  @option_keys Keyword.keys(@default_options)

  @doc """
  Returns default token options.
  """
  @spec default_options() :: keyword()
  def default_options, do: @default_options

  @doc """
  Validates token formatting options without creating a token.
  """
  @spec validate_options(keyword()) :: :ok | {:error, term()}
  def validate_options(opts) when is_list(opts) do
    merged = Keyword.merge(@default_options, opts)

    with :ok <- validate_known_options(opts),
         :ok <- validate_binary_option(merged, :token_prefix),
         :ok <- validate_binary_option(merged, :token_suffix),
         :ok <- validate_binary_option(merged, :token_separator),
         :ok <- validate_width(merged),
         :ok <- validate_case(merged) do
      validate_strategy(merged)
    end
  end

  def validate_options(_opts), do: {:error, :invalid_token_options}

  @doc """
  Formats an entity token for a counter.
  """
  @spec format(atom(), pos_integer(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def format(entity, counter, opts \\ [])

  def format(entity, counter, opts)
      when is_atom(entity) and is_integer(counter) and counter > 0 and is_list(opts) do
    opts = Keyword.merge(@default_options, opts)

    with :ok <- validate_options(opts),
         {:ok, entity_part} <- entity_part(entity, opts),
         {:ok, count_part} <- counter_part(counter, opts) do
      {:ok,
       [
         Keyword.fetch!(opts, :token_prefix),
         entity_part,
         Keyword.fetch!(opts, :token_separator),
         count_part,
         Keyword.fetch!(opts, :token_suffix)
       ]
       |> IO.iodata_to_binary()}
    end
  end

  def format(_entity, _counter, _opts), do: {:error, :invalid_token_arguments}

  @doc """
  Returns true when a token has the configured prefix and suffix.
  """
  @spec token_like?(String.t(), keyword()) :: boolean()
  def token_like?(token, opts \\ []) when is_binary(token) and is_list(opts) do
    opts = Keyword.merge(@default_options, opts)

    case validate_options(opts) do
      :ok ->
        String.valid?(token) and String.starts_with?(token, opts[:token_prefix]) and
          String.ends_with?(token, opts[:token_suffix])

      {:error, _reason} ->
        false
    end
  end

  defp validate_strategy(opts) do
    case Keyword.fetch!(opts, :token_strategy) do
      :sequential -> :ok
      _strategy -> {:error, :unsupported_token_strategy}
    end
  end

  defp validate_known_options(opts) do
    case Keyword.keys(opts) -- @option_keys do
      [] -> :ok
      _unknown -> {:error, :unknown_token_option}
    end
  end

  defp validate_binary_option(opts, key) do
    if is_binary(Keyword.fetch!(opts, key)) do
      :ok
    else
      {:error, :invalid_token_delimiter}
    end
  end

  defp validate_width(opts) do
    width = Keyword.fetch!(opts, :token_width)
    if is_integer(width) and width > 0, do: :ok, else: {:error, :invalid_token_width}
  end

  defp validate_case(opts) do
    if Keyword.fetch!(opts, :token_case) in [:upper, :lower, :preserve] do
      :ok
    else
      {:error, :unsupported_token_case}
    end
  end

  defp entity_part(entity, opts) do
    value = Atom.to_string(entity)

    case Keyword.fetch!(opts, :token_case) do
      :upper -> {:ok, String.upcase(value)}
      :lower -> {:ok, String.downcase(value)}
      :preserve -> {:ok, value}
      token_case -> {:error, {:unsupported_token_case, token_case}}
    end
  end

  defp counter_part(counter, opts) do
    width = Keyword.fetch!(opts, :token_width)

    if is_integer(width) and width > 0 do
      {:ok, counter |> Integer.to_string() |> String.pad_leading(width, "0")}
    else
      {:error, :invalid_token_width}
    end
  end
end
