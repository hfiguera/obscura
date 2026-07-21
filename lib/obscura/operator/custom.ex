defmodule Obscura.Operator.Custom do
  @moduledoc """
  Behaviour and guarded runtime for application-defined anonymizer operators.

  Custom operators receive the source value, safe anonymizer context, and the
  configured options map. They must return `{:ok, replacement}` or
  `{:ok, replacement, metadata}` with a binary replacement and map metadata.
  """

  alias Obscura.Anonymizer.Error

  @allowed_options [:type, :module, :options]

  @typedoc "Sanitized anonymizer context supplied to a custom operator."
  @type context :: %{required(:entity) => atom()}

  @typedoc "Application-defined options from the operator configuration."
  @type options :: map()

  @typedoc "Accepted custom operator callback return contract."
  @type callback_result ::
          {:ok, String.t()} | {:ok, String.t(), map()} | {:error, term()}

  @callback apply(String.t(), context(), options()) :: callback_result()

  @doc false
  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(config) when is_map(config) do
    with :ok <- validate_options(config),
         {:ok, module} <- fetch_module(config),
         :ok <- validate_module(module) do
      validate_callback_options(Map.get(config, :options, %{}))
    end
  end

  def validate(_config), do: {:error, Error.new(:invalid_operator_config, operator: :custom)}

  @doc false
  @spec run(String.t(), map(), map()) :: {:ok, String.t(), map()} | {:error, Error.t()}
  def run(value, config, context)
      when is_binary(value) and is_map(config) and is_map(context) do
    with :ok <- validate(config),
         {:ok, module} <- fetch_module(config) do
      invoke(module, value, Map.take(context, [:entity]), Map.get(config, :options, %{}))
    end
  end

  def run(_value, _config, _context),
    do: {:error, Error.new(:invalid_operator_config, operator: :custom)}

  defp invoke(module, value, context, options) do
    case module.apply(value, context, options) do
      {:ok, replacement} when is_binary(replacement) ->
        {:ok, replacement, %{custom_module: module}}

      {:ok, replacement, metadata} when is_binary(replacement) and is_map(metadata) ->
        {:ok, replacement, Map.put_new(metadata, :custom_module, module)}

      {:error, _reason} ->
        callback_failure(:callback_error)

      _invalid ->
        {:error,
         Error.new(:invalid_operator_result,
           operator: :custom,
           reason: :invalid_callback_return
         )}
    end
  rescue
    _exception -> callback_failure(:exception)
  catch
    :throw, _reason -> callback_failure(:throw)
    :exit, _reason -> callback_failure(:exit)
  end

  defp validate_options(config) do
    case Map.keys(config) -- @allowed_options do
      [] ->
        :ok

      _unknown ->
        {:error,
         Error.new(:unknown_operator_option,
           operator: :custom,
           metadata: %{allowed_options: @allowed_options}
         )}
    end
  end

  defp fetch_module(config) do
    case Map.fetch(config, :module) do
      {:ok, module} when is_atom(module) ->
        {:ok, module}

      :error ->
        {:error,
         Error.new(:missing_operator_option,
           operator: :custom,
           field: :module,
           reason: :required
         )}

      {:ok, _module} ->
        {:error,
         Error.new(:invalid_operator_option,
           operator: :custom,
           field: :module,
           reason: :expected_module
         )}
    end
  end

  defp validate_module(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :apply, 3) and
         implements_behaviour?(module) do
      :ok
    else
      {:error,
       Error.new(:invalid_operator_option,
         operator: :custom,
         field: :module,
         reason: :callback_unavailable
       )}
    end
  end

  defp implements_behaviour?(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(__MODULE__)
  end

  defp validate_callback_options(options) when is_map(options), do: :ok

  defp validate_callback_options(_options) do
    {:error,
     Error.new(:invalid_operator_option,
       operator: :custom,
       field: :options,
       reason: :expected_map
     )}
  end

  defp callback_failure(reason) do
    {:error, Error.new(:operator_failed, operator: :custom, reason: reason)}
  end
end
