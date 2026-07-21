defmodule Obscura.LLM do
  @moduledoc """
  Provider-independent LLM message redaction and rehydration helpers.
  """

  alias Obscura.LLM.Message
  alias Obscura.Telemetry
  alias Obscura.Vault.Memory

  @doc """
  Redacts configured message roles with vault-backed pseudonymization.
  """
  @spec redact_messages([map()], keyword()) ::
          {:ok, [map()], GenServer.server()} | {:error, term()}
  def redact_messages(messages, opts \\ []) when is_list(messages) and is_list(opts) do
    start = System.monotonic_time()

    result =
      with {:ok, vault} <- resolve_vault(opts),
           {:ok, safe_messages, redacted_count} <- redact_each(messages, vault, opts) do
        {:ok, safe_messages, vault, redacted_count}
      end

    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :llm, :redact_messages, :stop],
      %{duration: System.monotonic_time() - start},
      telemetry_metadata(result, length(messages))
    )

    case result do
      {:ok, safe_messages, vault, _redacted_count} -> {:ok, safe_messages, vault}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Rehydrates one LLM provider response string.
  """
  @spec rehydrate_response(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def rehydrate_response(response_text, opts \\ [])
      when is_binary(response_text) and is_list(opts) do
    start = System.monotonic_time()
    result = Obscura.rehydrate(response_text, opts)

    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :llm, :rehydrate_response, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: status(result), input_type: :string}
    )

    result
  end

  @doc """
  Rehydrates message content fields.
  """
  @spec rehydrate_messages([map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def rehydrate_messages(messages, opts \\ []) when is_list(messages) and is_list(opts) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, acc} ->
      reduce_rehydrated_message(message, acc, opts)
    end)
  end

  defp resolve_vault(opts) do
    case Keyword.get(opts, :vault) do
      nil ->
        if Keyword.get(opts, :create_vault, false) do
          Memory.start_link()
        else
          {:error, :missing_vault}
        end

      :memory ->
        Memory.start_link()

      vault ->
        {:ok, vault}
    end
  end

  defp redact_each(messages, vault, opts) do
    roles = Keyword.get(opts, :roles, [:user])

    Enum.reduce_while(messages, {:ok, [], 0}, fn message, {:ok, acc, count} ->
      reduce_redacted_message(message, acc, count, roles, vault, opts)
    end)
  end

  defp reduce_rehydrated_message(message, acc, opts) do
    case Message.content(message) do
      content when is_binary(content) -> rehydrate_message_content(message, content, acc, opts)
      _other -> {:cont, {:ok, acc ++ [message]}}
    end
  end

  defp rehydrate_message_content(message, content, acc, opts) do
    case Obscura.rehydrate(content, opts) do
      {:ok, rehydrated} -> {:cont, {:ok, acc ++ [Message.put_content(message, rehydrated)]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp reduce_redacted_message(message, acc, count, roles, vault, opts) do
    content = Message.content(message)

    if is_binary(content) and Message.role_selected?(message, roles) do
      redact_message_content(message, content, acc, count, vault, opts)
    else
      {:cont, {:ok, acc ++ [message], count}}
    end
  end

  defp redact_message_content(message, content, acc, count, vault, opts) do
    case Obscura.redact(content, redact_opts(vault, opts)) do
      {:ok, result} ->
        {:cont, {:ok, acc ++ [Message.put_content(message, result.text)], count + 1}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp redact_opts(vault, opts) do
    opts
    |> Keyword.drop([:roles, :create_vault])
    |> Keyword.put(:vault, vault)
    |> Keyword.put_new(:operators, %{default: %{type: :pseudonymize}})
  end

  defp telemetry_metadata({:ok, _messages, _vault, redacted_count}, message_count) do
    %{
      status: :ok,
      message_count: message_count,
      redacted_message_count: redacted_count,
      input_type: :messages
    }
  end

  defp telemetry_metadata({:error, _reason}, message_count) do
    %{
      status: :error,
      message_count: message_count,
      redacted_message_count: 0,
      input_type: :messages
    }
  end

  defp status({:ok, _value}), do: :ok
  defp status({:error, _reason}), do: :error
end
