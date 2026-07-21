defmodule Obscura.Vault do
  @moduledoc """
  Facade for reversible pseudonymization vault backends.
  """

  alias Obscura.Input
  alias Obscura.Rehydrator

  @type vault_ref :: GenServer.server()

  @doc """
  Gets or creates a token for an entity/value pair.
  """
  @spec get_or_create(vault_ref() | nil, atom(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def get_or_create(vault, entity, value, opts \\ [])

  def get_or_create(nil, _entity, _value, _opts), do: {:error, :missing_vault}

  def get_or_create(vault, entity, value, opts)
      when is_atom(entity) and not is_nil(entity) and is_binary(value) and is_list(opts) do
    with :ok <- Input.validate_text(value) do
      GenServer.call(vault, {:get_or_create, entity, value, opts})
    end
  catch
    :exit, reason -> {:error, {:vault_unavailable, exit_reason(reason)}}
  end

  def get_or_create(_vault, _entity, _value, _opts), do: {:error, :invalid_vault_arguments}

  @doc """
  Looks up an entry by token.
  """
  @spec lookup_token(vault_ref() | nil, String.t(), keyword()) ::
          {:ok, Obscura.Vault.Entry.t()} | {:error, term()}
  def lookup_token(vault, token, opts \\ [])

  def lookup_token(nil, _token, _opts), do: {:error, :missing_vault}

  def lookup_token(vault, token, opts)
      when is_binary(token) and is_list(opts) do
    with :ok <- Input.validate_text(token) do
      GenServer.call(vault, {:lookup_token, token, opts})
    end
  catch
    :exit, reason -> {:error, {:vault_unavailable, exit_reason(reason)}}
  end

  def lookup_token(_vault, _token, _opts), do: {:error, :invalid_token}

  @doc """
  Looks up an entry by entity and original value.
  """
  @spec lookup_value(vault_ref() | nil, atom(), String.t(), keyword()) ::
          {:ok, Obscura.Vault.Entry.t()} | {:error, term()}
  def lookup_value(vault, entity, value, opts \\ [])

  def lookup_value(nil, _entity, _value, _opts), do: {:error, :missing_vault}

  def lookup_value(vault, entity, value, opts)
      when is_atom(entity) and not is_nil(entity) and is_binary(value) and is_list(opts) do
    with :ok <- Input.validate_text(value) do
      GenServer.call(vault, {:lookup_value, entity, value, opts})
    end
  catch
    :exit, reason -> {:error, {:vault_unavailable, exit_reason(reason)}}
  end

  def lookup_value(_vault, _entity, _value, _opts), do: {:error, :invalid_vault_arguments}

  @doc """
  Rehydrates all known tokens in a string through a vault.
  """
  @spec rehydrate(vault_ref() | nil, String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def rehydrate(vault, text, opts \\ [])

  def rehydrate(nil, _text, _opts), do: {:error, :missing_vault}

  def rehydrate(vault, text, opts) when is_binary(text) and is_list(opts) do
    with :ok <- Input.validate_text(text) do
      Rehydrator.rehydrate(text, Keyword.put(opts, :vault, vault))
    end
  end

  def rehydrate(_vault, _text, _opts), do: {:error, :invalid_rehydrate_arguments}

  @doc """
  Clears all mappings from a vault.
  """
  @spec clear(vault_ref() | nil, keyword()) :: :ok | {:error, term()}
  def clear(vault, opts \\ [])

  def clear(nil, _opts), do: {:error, :missing_vault}

  def clear(vault, opts) when is_list(opts) do
    GenServer.call(vault, {:clear, opts})
  catch
    :exit, reason -> {:error, {:vault_unavailable, exit_reason(reason)}}
  end

  def clear(_vault, _opts), do: {:error, :invalid_vault_arguments}

  @doc """
  Returns backend metadata for a vault.
  """
  @spec info(vault_ref() | nil) :: {:ok, map()} | {:error, term()}
  def info(nil), do: {:error, :missing_vault}

  def info(vault) do
    GenServer.call(vault, :info)
  catch
    :exit, reason -> {:error, {:vault_unavailable, exit_reason(reason)}}
  end

  defp exit_reason({reason, _details}) when is_atom(reason), do: reason
  defp exit_reason(reason) when is_atom(reason), do: reason
  defp exit_reason(_reason), do: :exit
end
