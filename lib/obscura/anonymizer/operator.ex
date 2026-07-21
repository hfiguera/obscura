defmodule Obscura.Anonymizer.Operator do
  @moduledoc """
  Validates and dispatches anonymizer operators.

  Every configuration is validated before replacement starts. Errors use
  `Obscura.Anonymizer.Error` and omit source values and unsafe callback details.
  """

  import Kernel, except: [apply: 3]

  alias Obscura.Anonymizer.Error
  alias Obscura.Operator.Custom
  alias Obscura.Operator.Hash
  alias Obscura.Operator.Mask
  alias Obscura.Operator.Pseudonymize
  alias Obscura.Operator.Redact
  alias Obscura.Operator.Replace

  @reserved_keys [:conflict_policy, :merge_whitespace]

  @doc """
  Validates an operator collection without applying any replacement.
  """
  @spec validate_configs(map(), map()) :: :ok | {:error, Error.t()}
  def validate_configs(configs, context \\ %{})

  def validate_configs(configs, context) when is_map(configs) and is_map(context) do
    Enum.reduce_while(configs, :ok, fn
      {key, _value}, :ok when key in @reserved_keys ->
        {:cont, :ok}

      {entity, config}, :ok when is_atom(entity) ->
        case validate_config(config, context) do
          :ok -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end

      {_entity, _config}, :ok ->
        {:halt,
         {:error,
          Error.new(:invalid_operator_collection,
            field: :operators,
            reason: :expected_atom_entity_keys
          )}}
    end)
  end

  def validate_configs(_configs, _context) do
    {:error,
     Error.new(:invalid_operator_collection,
       field: :operators,
       reason: :expected_map
     )}
  end

  @doc """
  Validates one operator configuration.
  """
  @spec validate_config(map(), map()) :: :ok | {:error, Error.t()}
  def validate_config(config, context \\ %{})

  def validate_config(%{type: :replace} = config, _context), do: Replace.validate(config)
  def validate_config(%{type: :redact} = config, _context), do: Redact.validate(config)
  def validate_config(%{type: :mask} = config, _context), do: Mask.validate(config)
  def validate_config(%{type: :hash} = config, _context), do: Hash.validate(config)
  def validate_config(%{type: :custom} = config, _context), do: Custom.validate(config)

  def validate_config(%{type: :pseudonymize} = config, context),
    do: Pseudonymize.validate(config, context)

  def validate_config(%{type: type}, _context) when is_atom(type) do
    {:error, Error.new(:unsupported_operator, operator: type, field: :type)}
  end

  def validate_config(%{type: _type}, _context) do
    {:error,
     Error.new(:invalid_operator_option,
       field: :type,
       reason: :expected_atom
     )}
  end

  def validate_config(config, _context) when is_map(config) do
    {:error,
     Error.new(:missing_operator_option,
       field: :type,
       reason: :required
     )}
  end

  def validate_config(_config, _context),
    do: {:error, Error.new(:invalid_operator_config, reason: :expected_map)}

  @doc """
  Applies an operator config to a source value.
  """
  @spec apply(String.t(), map()) ::
          {atom(), String.t(), map()} | {:error, Error.t()}
  def apply(value, config), do: apply(value, config, %{})

  @doc """
  Applies an operator config to a source value with anonymizer context.
  """
  @spec apply(String.t(), map(), map()) ::
          {atom(), String.t(), map()} | {:error, Error.t()}
  def apply(value, config, context) when is_binary(value) and is_map(context) do
    with :ok <- validate_config(config, context),
         {:ok, type, replacement, metadata} <- dispatch(value, config, context) do
      {type, replacement, metadata}
    end
  end

  def apply(_value, _config, _context) do
    {:error,
     Error.new(:invalid_operator_option,
       field: :source,
       reason: :expected_binary
     )}
  end

  defp dispatch(value, %{type: :replace} = config, _context),
    do: wrap(:replace, Replace.apply(value, config))

  defp dispatch(value, %{type: :redact} = config, _context),
    do: wrap(:redact, Redact.apply(value, config))

  defp dispatch(value, %{type: :mask} = config, _context),
    do: wrap(:mask, Mask.apply(value, config))

  defp dispatch(value, %{type: :hash} = config, _context),
    do: wrap(:hash, Hash.apply(value, config))

  defp dispatch(value, %{type: :custom} = config, context),
    do: wrap(:custom, Custom.run(value, config, context))

  defp dispatch(value, %{type: :pseudonymize} = config, context),
    do: wrap(:pseudonymize, Pseudonymize.apply(value, config, context))

  defp wrap(type, {:ok, replacement, metadata}),
    do: {:ok, type, replacement, metadata}

  defp wrap(_type, {:error, %Error{} = error}), do: {:error, error}
end
