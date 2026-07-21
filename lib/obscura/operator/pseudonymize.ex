defmodule Obscura.Operator.Pseudonymize do
  @moduledoc """
  Vault-backed reversible pseudonymization operator.
  """

  alias Obscura.Anonymizer.Error
  alias Obscura.Vault
  alias Obscura.Vault.Token

  @allowed_options [:type, :vault]

  @doc false
  @spec validate(map(), map()) :: :ok | {:error, Error.t()}
  def validate(config, context) when is_map(config) and is_map(context) do
    with :ok <- validate_options(config),
         :ok <- validate_token_options(Map.get(context, :token_options, [])) do
      validate_vault(Map.get(config, :vault) || Map.get(context, :vault))
    end
  end

  def validate(_config, _context),
    do: {:error, Error.new(:invalid_operator_config, operator: :pseudonymize)}

  @doc """
  Returns a vault token for a source value.
  """
  @spec apply(String.t(), map(), map()) :: {:ok, String.t(), map()} | {:error, term()}
  def apply(value, config, context)
      when is_binary(value) and is_map(config) and is_map(context) do
    with :ok <- validate(config, context),
         {:ok, entity} <- fetch_entity(context) do
      do_apply(value, config, context, entity)
    end
  end

  def apply(_value, _config, _context),
    do: {:error, Error.new(:invalid_operator_config, operator: :pseudonymize)}

  defp do_apply(value, config, context, entity) do
    vault = Map.get(config, :vault) || Map.get(context, :vault)
    token_opts = Map.get(context, :token_options, [])

    with {:ok, before} <- vault_entry(vault, entity, value),
         {:ok, token} <- Vault.get_or_create(vault, entity, value, token_opts),
         {:ok, after_entry} <- Vault.lookup_token(vault, token),
         {:ok, info} <- Vault.info(vault) do
      created? = is_nil(before)

      {:ok, token,
       %{
         vault: Map.get(info, :backend),
         token_created: created?,
         token_length: byte_size(token),
         deterministic: true,
         use_count: after_entry.use_count
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, vault_error(reason)}
    end
  end

  defp validate_options(config) do
    case Map.keys(config) -- @allowed_options do
      [] ->
        :ok

      _unknown ->
        {:error,
         Error.new(:unknown_operator_option,
           operator: :pseudonymize,
           metadata: %{allowed_options: @allowed_options}
         )}
    end
  end

  defp validate_token_options(opts) do
    case Token.validate_options(opts) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         Error.new(:invalid_operator_option,
           operator: :pseudonymize,
           field: :token_options,
           reason: token_error_reason(reason)
         )}
    end
  end

  defp validate_vault(nil) do
    {:error,
     Error.new(:missing_operator_option,
       operator: :pseudonymize,
       field: :vault,
       reason: :required
     )}
  end

  defp validate_vault(vault) do
    case safe_vault_info(vault) do
      {:ok, _info} -> :ok
      {:error, reason} -> {:error, vault_error(reason)}
    end
  end

  defp safe_vault_info(vault) do
    Vault.info(vault)
  rescue
    _exception -> {:error, :invalid_vault}
  catch
    :throw, _reason -> {:error, :invalid_vault}
    :exit, _reason -> {:error, :vault_unavailable}
  end

  defp fetch_entity(%{entity: entity}) when is_atom(entity), do: {:ok, entity}

  defp fetch_entity(_context) do
    {:error,
     Error.new(:invalid_operator_option,
       operator: :pseudonymize,
       field: :entity,
       reason: :expected_atom
     )}
  end

  defp vault_entry(nil, _entity, _value), do: {:error, :missing_vault}

  defp vault_entry(vault, entity, value) do
    case Vault.lookup_value(vault, entity, value) do
      {:ok, entry} -> {:ok, entry}
      {:error, {:value_not_found, ^entity}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp vault_error(reason) do
    Error.new(:operator_failed,
      operator: :pseudonymize,
      field: :vault,
      reason: vault_error_reason(reason)
    )
  end

  defp vault_error_reason(:missing_vault), do: :missing_vault
  defp vault_error_reason(:invalid_vault), do: :invalid_vault
  defp vault_error_reason(:vault_unavailable), do: :vault_unavailable
  defp vault_error_reason({:vault_unavailable, _reason}), do: :vault_unavailable
  defp vault_error_reason({:invalid_entity, _entity}), do: :invalid_entity
  defp vault_error_reason({:value_not_found, _entity}), do: :value_not_found
  defp vault_error_reason({:token_not_found, _token}), do: :token_not_found
  defp vault_error_reason(_reason), do: :vault_operation_failed

  defp token_error_reason(reason) when is_atom(reason), do: reason
end
