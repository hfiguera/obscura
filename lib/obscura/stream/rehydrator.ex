defmodule Obscura.Stream.Rehydrator do
  @moduledoc """
  Streaming-safe vault token rehydration.
  """

  alias Obscura.Telemetry
  alias Obscura.Vault
  alias Obscura.Vault.Token

  @enforce_keys [:vault]
  defstruct [
    :vault,
    buffer: "",
    token_prefix: "<<",
    token_suffix: ">>",
    max_token_length: 128,
    unknown: :keep,
    telemetry: true
  ]

  @type t :: %__MODULE__{
          vault: GenServer.server(),
          buffer: String.t(),
          token_prefix: String.t(),
          token_suffix: String.t(),
          max_token_length: pos_integer(),
          unknown: :keep | :error,
          telemetry: boolean()
        }

  @doc """
  Creates a streaming rehydrator state.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    with {:ok, vault} <- fetch_vault(opts),
         :ok <- validate_options(opts) do
      {:ok,
       %__MODULE__{
         vault: vault,
         token_prefix: Keyword.get(opts, :token_prefix, "<<"),
         token_suffix: Keyword.get(opts, :token_suffix, ">>"),
         max_token_length: Keyword.get(opts, :max_token_length, 128),
         unknown: Keyword.get(opts, :unknown, :keep),
         telemetry: Keyword.get(opts, :telemetry, true)
       }}
    end
  end

  def new(_opts), do: {:error, :invalid_stream_options}

  defp fetch_vault(opts) do
    case Keyword.get(opts, :vault) do
      nil -> {:error, :missing_vault}
      vault -> {:ok, vault}
    end
  end

  defp validate_options(opts) do
    token_opts = [
      token_prefix: Keyword.get(opts, :token_prefix, "<<"),
      token_suffix: Keyword.get(opts, :token_suffix, ">>")
    ]

    with :ok <- validate_known_options(opts),
         :ok <- validate_token_delimiters(token_opts),
         :ok <- validate_positive_integer(Keyword.get(opts, :max_token_length, 128)),
         :ok <- validate_unknown(Keyword.get(opts, :unknown, :keep)),
         true <- is_boolean(Keyword.get(opts, :telemetry, true)) || {:error, :invalid_telemetry} do
      :ok
    end
  end

  defp validate_known_options(opts) do
    allowed = [:vault, :token_prefix, :token_suffix, :max_token_length, :unknown, :telemetry]
    if Keyword.keys(opts) -- allowed == [], do: :ok, else: {:error, :unknown_stream_option}
  end

  defp validate_token_delimiters(opts) do
    defaults = Token.default_options()

    defaults
    |> Keyword.merge(opts)
    |> Token.validate_options()
  end

  defp validate_positive_integer(value) when is_integer(value) and value > 0, do: :ok
  defp validate_positive_integer(_value), do: {:error, :invalid_max_token_length}

  defp validate_unknown(value) when value in [:keep, :error], do: :ok
  defp validate_unknown(_value), do: {:error, :invalid_unknown_token_policy}

  @doc """
  Feeds one streamed chunk and returns text safe to emit.
  """
  @spec feed(t(), String.t()) :: {:ok, String.t(), t()} | {:error, term()}
  def feed(%__MODULE__{} = stream, chunk) when is_binary(chunk) do
    start = System.monotonic_time()

    result =
      stream.buffer
      |> Kernel.<>(chunk)
      |> process(stream, false)
      |> case do
        {:ok, ready, buffer} -> {:ok, ready, %{stream | buffer: buffer}}
        {:error, reason} -> {:error, reason}
      end

    emit_telemetry(stream, start, result)
    result
  end

  def feed(_stream, _chunk), do: {:error, :invalid_stream_arguments}

  @doc """
  Flushes final buffered text.
  """
  @spec flush(t()) :: {:ok, String.t()} | {:error, term()}
  def flush(%__MODULE__{} = stream) do
    start = System.monotonic_time()

    result =
      process(stream.buffer, stream, true)
      |> case do
        {:ok, ready, ""} -> {:ok, ready}
        {:ok, ready, rest} -> {:ok, ready <> rest}
        {:error, reason} -> {:error, reason}
      end

    emit_telemetry(stream, start, result)
    result
  end

  def flush(_stream), do: {:error, :invalid_stream_state}

  defp process(text, stream, final?) do
    do_process(text, stream, final?, [])
  end

  defp do_process("", _stream, _final?, acc),
    do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), ""}

  defp do_process(text, stream, final?, acc) do
    case :binary.match(text, stream.token_prefix) do
      :nomatch ->
        {ready, buffer} = split_prefix_tail(text, stream.token_prefix, final?)
        {:ok, IO.iodata_to_binary(Enum.reverse([ready | acc])), buffer}

      {prefix_start, _prefix_length} ->
        before = binary_part(text, 0, prefix_start)
        candidate = binary_part(text, prefix_start, byte_size(text) - prefix_start)
        process_candidate(candidate, before, stream, final?, acc)
    end
  end

  defp process_candidate(candidate, before, stream, final?, acc) do
    case complete_token(candidate, stream) do
      {:ok, token, rest} -> process_complete_token(token, rest, before, stream, final?, acc)
      :incomplete -> process_incomplete_token(candidate, before, stream, final?, acc)
    end
  end

  defp process_complete_token(token, rest, before, stream, final?, acc) do
    case rehydrate_token(stream, token) do
      {:ok, value} -> do_process(rest, stream, final?, [value, before | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_incomplete_token(candidate, before, _stream, true, acc) do
    {:ok, IO.iodata_to_binary(Enum.reverse([candidate, before | acc])), ""}
  end

  defp process_incomplete_token(candidate, before, stream, false, acc) do
    if byte_size(candidate) > stream.max_token_length do
      {:error, {:token_too_long, stream.max_token_length}}
    else
      {:ok, IO.iodata_to_binary(Enum.reverse([before | acc])), candidate}
    end
  end

  defp complete_token(candidate, stream) do
    suffix_search_start = byte_size(stream.token_prefix)

    search =
      binary_part(candidate, suffix_search_start, byte_size(candidate) - suffix_search_start)

    case :binary.match(search, stream.token_suffix) do
      :nomatch ->
        :incomplete

      {suffix_start, suffix_length} ->
        token_length = suffix_search_start + suffix_start + suffix_length
        token = binary_part(candidate, 0, token_length)
        rest = binary_part(candidate, token_length, byte_size(candidate) - token_length)
        {:ok, token, rest}
    end
  end

  defp rehydrate_token(stream, token) do
    case Vault.lookup_token(stream.vault, token) do
      {:ok, entry} ->
        {:ok, entry.value}

      {:error, _reason} when stream.unknown == :keep ->
        {:ok, token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp split_prefix_tail(text, _prefix, true), do: {text, ""}

  defp split_prefix_tail(text, prefix, false) do
    tail_length = partial_prefix_tail_length(text, prefix)
    ready_length = byte_size(text) - tail_length
    {binary_part(text, 0, ready_length), binary_part(text, ready_length, tail_length)}
  end

  defp partial_prefix_tail_length(text, prefix) do
    max_tail = min(byte_size(text), byte_size(prefix) - 1)

    Enum.find(max_tail..0//-1, 0, fn tail_length ->
      suffix = binary_part(text, byte_size(text) - tail_length, tail_length)
      String.starts_with?(prefix, suffix)
    end)
  end

  defp emit_telemetry(stream, start, result) do
    Telemetry.execute(
      stream.telemetry,
      [:obscura, :stream, :rehydrate, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: status(result), input_type: :stream}
    )
  end

  defp status({:ok, _ready, _stream}), do: :ok
  defp status({:ok, _ready}), do: :ok
  defp status({:error, _reason}), do: :error
end

defimpl Inspect, for: Obscura.Stream.Rehydrator do
  import Inspect.Algebra

  def inspect(stream, opts) do
    safe = %{
      buffered_bytes: byte_size(stream.buffer),
      max_token_length: stream.max_token_length,
      unknown: stream.unknown,
      telemetry: stream.telemetry
    }

    concat(["#Obscura.Stream.Rehydrator<", to_doc(safe, opts), ">"])
  end
end
