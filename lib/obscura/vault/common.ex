defmodule Obscura.Vault.Common do
  @moduledoc false

  alias Obscura.Telemetry
  alias Obscura.Vault.Token

  @spec start_link(module(), keyword(), [atom()]) :: GenServer.on_start()
  def start_link(module, opts, extra_keys \\ []) do
    with :ok <- validate_start_options(opts, extra_keys),
         :ok <- validate_token_options(opts) do
      GenServer.start_link(module, opts, name: Keyword.get(opts, :name))
    end
  end

  @spec validate_start_options(term(), [atom()]) :: :ok | {:error, atom()}
  def validate_start_options(opts, extra_keys) when is_list(opts) and is_list(extra_keys) do
    allowed = [:name | Keyword.keys(Token.default_options())] ++ extra_keys

    cond do
      List.improper?(opts) -> {:error, :invalid_vault_options}
      not Keyword.keyword?(opts) -> {:error, :invalid_vault_options}
      Keyword.keys(opts) -- allowed != [] -> {:error, :unknown_vault_option}
      not valid_name?(Keyword.get(opts, :name)) -> {:error, :invalid_vault_name}
      true -> :ok
    end
  end

  def validate_start_options(_opts, _extra_keys), do: {:error, :invalid_vault_options}

  defp validate_token_options(opts) do
    opts
    |> Keyword.take(Keyword.keys(Token.default_options()))
    |> Token.validate_options()
  end

  @spec touch(Obscura.Vault.Entry.t()) :: Obscura.Vault.Entry.t()
  def touch(entry) do
    %{entry | last_used_at: System.monotonic_time(), use_count: entry.use_count + 1}
  end

  @spec token_shape(String.t()) :: map()
  def token_shape(token) do
    %{bytes: byte_size(token), token_like: Token.token_like?(token)}
  end

  @spec emit_token_telemetry(atom(), integer(), atom(), boolean(), term()) :: :ok
  def emit_token_telemetry(backend, start, entity, created?, reply) do
    Telemetry.execute(
      true,
      [:obscura, :vault, :token, :stop],
      %{duration: System.monotonic_time() - start},
      %{
        status: status(reply),
        entity: entity,
        backend: backend,
        token_created: created?
      }
    )
  end

  @spec emit_lookup_telemetry(atom(), integer(), atom(), term()) :: :ok
  def emit_lookup_telemetry(backend, start, lookup, reply) do
    Telemetry.execute(
      true,
      [:obscura, :vault, :lookup, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: status(reply), backend: backend, lookup: lookup}
    )
  end

  defp status({:ok, _value}), do: :ok
  defp status({:error, _reason}), do: :error

  defp valid_name?(nil), do: true
  defp valid_name?(name) when is_atom(name), do: true
  defp valid_name?({:global, _term}), do: true
  defp valid_name?({:via, module, _term}) when is_atom(module), do: true
  defp valid_name?(_name), do: false
end
