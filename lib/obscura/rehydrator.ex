defmodule Obscura.Rehydrator do
  @moduledoc """
  Rehydrates vault tokens in strings.
  """

  alias Obscura.Input
  alias Obscura.Telemetry
  alias Obscura.Vault
  alias Obscura.Vault.Token

  @doc """
  Replaces known vault tokens in text with original values.
  """
  @spec rehydrate(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def rehydrate(text, opts \\ [])

  def rehydrate(text, opts) when is_binary(text) and is_list(opts) do
    start = System.monotonic_time()
    vault = Keyword.get(opts, :vault)
    unknown = Keyword.get(opts, :unknown, :keep)

    result = validate_and_rehydrate(text, vault, unknown, opts)

    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :rehydrate, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: status(result), input_type: :string, token_count: token_count(text, opts)}
    )

    result
  end

  def rehydrate(_text, _opts), do: {:error, :invalid_rehydrate_arguments}

  defp validate_and_rehydrate(text, vault, unknown, opts) do
    token_opts = token_options(opts)

    with :ok <- Input.validate_text(text),
         :ok <- validate_vault(vault),
         :ok <- validate_unknown(unknown),
         :ok <- Token.validate_options(token_opts) do
      do_rehydrate(text, vault, unknown, token_opts)
    end
  end

  defp validate_vault(nil), do: {:error, :missing_vault}
  defp validate_vault(_vault), do: :ok

  defp validate_unknown(unknown) when unknown in [:keep, :error], do: :ok
  defp validate_unknown(_unknown), do: {:error, :invalid_unknown_token_policy}

  defp do_rehydrate(text, vault, unknown, token_opts) do
    tokens = Regex.scan(token_regex(token_opts), text) |> Enum.map(&List.first/1)

    Enum.reduce_while(tokens, {:ok, text}, fn token, {:ok, acc} ->
      case Vault.lookup_token(vault, token) do
        {:ok, entry} ->
          {:cont, {:ok, String.replace(acc, token, entry.value)}}

        {:error, _reason} when unknown == :keep ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp token_regex(opts) do
    prefix = opts |> Keyword.fetch!(:token_prefix) |> Regex.escape()
    suffix = opts |> Keyword.fetch!(:token_suffix) |> Regex.escape()

    Regex.compile!("#{prefix}[A-Za-z0-9_]+#{suffix}")
  end

  defp token_options(opts) do
    Token.default_options()
    |> Keyword.merge(Keyword.take(opts, Keyword.keys(Token.default_options())))
  end

  defp token_count(text, opts) do
    token_options = token_options(opts)
    token_options |> token_regex() |> Regex.scan(text) |> length()
  end

  defp status({:ok, _value}), do: :ok
  defp status({:error, _reason}), do: :error
end
