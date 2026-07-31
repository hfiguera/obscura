defmodule Obscura.Phoenix.Plug do
  @moduledoc """
  Plug-compatible request sanitization helper.

  Integration options are validated and normalized by `init/1`. Invalid modes,
  fields, assign names, telemetry flags, and declarative redaction options fail
  during Plug initialization rather than during a request.
  """

  import Plug.Conn

  alias Obscura.Analyzer.Options
  alias Obscura.Anonymizer
  alias Obscura.Telemetry

  @initialized_option :__obscura_phoenix_plug_initialized__
  @integration_options [:assign, :fields, :mode]
  @supported_fields [:params, :req_headers]
  @supported_modes [:assign_redacted, :replace, :disabled]

  @doc false
  @spec init(keyword()) :: keyword()
  def init(opts) do
    case normalize_options(opts) do
      {:ok, normalized} ->
        normalized

      {:error, {option, reason}} ->
        raise ArgumentError,
              "invalid Obscura.Phoenix.Plug option #{inspect(option)}: #{reason}"
    end
  end

  @doc false
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, [{@initialized_option, true} | _rest] = opts), do: do_call(conn, opts)
  def call(conn, opts), do: call(conn, init(opts))

  defp do_call(conn, opts) do
    start = System.monotonic_time()
    mode = Keyword.fetch!(opts, :mode)
    fields = Keyword.fetch!(opts, :fields)
    assign = Keyword.fetch!(opts, :assign)

    {conn, redacted} =
      if mode == :disabled do
        {conn, %{}}
      else
        redact_fields(conn, fields, opts)
        |> apply_mode(conn, mode, assign)
      end

    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :plug, :call, :stop],
      %{duration: System.monotonic_time() - start},
      %{status: :ok, input_type: :plug_conn, result_count: map_size(redacted)}
    )

    conn
  end

  defp redact_fields(conn, fields, opts) do
    redaction_opts = Keyword.drop(opts, [@initialized_option | @integration_options])
    Map.new(fields, &redact_field(conn, &1, redaction_opts))
  end

  defp redact_field(conn, :params, opts) do
    {:ok, result} =
      Obscura.Structured.redact(conn.params, Keyword.put_new(opts, :telemetry, false))

    {:params, result.data}
  end

  defp redact_field(conn, :req_headers, opts) do
    headers = Map.new(conn.req_headers)
    {:ok, result} = Obscura.Structured.redact(headers, Keyword.put_new(opts, :telemetry, false))
    {:req_headers, result.data}
  end

  defp redact_field(_conn, field, _opts), do: {field, nil}

  defp apply_mode(redacted, conn, :assign_redacted, assign),
    do: {assign(conn, assign, redacted), redacted}

  defp apply_mode(redacted, conn, :replace, _assign) do
    conn =
      redacted
      |> Enum.reduce(conn, fn
        {:params, params}, acc -> %{acc | params: params}
        {:req_headers, headers}, acc -> %{acc | req_headers: Enum.to_list(headers)}
        {_field, _value}, acc -> acc
      end)

    {conn, redacted}
  end

  defp normalize_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      mode = Keyword.get(opts, :mode, :assign_redacted)
      fields = Keyword.get(opts, :fields, [:params])
      assign = Keyword.get(opts, :assign, :obscura_redacted)
      telemetry = Keyword.get(opts, :telemetry, true)

      with :ok <- validate_mode(mode),
           {:ok, fields} <- normalize_fields(fields),
           :ok <- validate_assign(assign),
           :ok <- validate_telemetry(telemetry),
           :ok <- validate_redaction_options(mode, opts) do
        {:ok,
         opts
         |> Keyword.put(:mode, mode)
         |> Keyword.put(:fields, fields)
         |> Keyword.put(:assign, assign)
         |> Keyword.put(:telemetry, telemetry)
         |> Keyword.put(@initialized_option, true)}
      end
    else
      {:error, {:options, "expected a keyword list"}}
    end
  end

  defp normalize_options(_opts), do: {:error, {:options, "expected a keyword list"}}

  defp validate_mode(mode) when mode in @supported_modes, do: :ok

  defp validate_mode(_mode),
    do: {:error, {:mode, "expected :assign_redacted, :replace, or :disabled"}}

  defp normalize_fields(fields) when is_list(fields),
    do: normalize_fields(fields, %{}, [])

  defp normalize_fields(_fields), do: {:error, {:fields, "expected a proper list"}}

  defp normalize_fields([], _seen, normalized), do: {:ok, Enum.reverse(normalized)}

  defp normalize_fields([field | rest], seen, normalized) when field in @supported_fields do
    if Map.has_key?(seen, field) do
      normalize_fields(rest, seen, normalized)
    else
      normalize_fields(rest, Map.put(seen, field, true), [field | normalized])
    end
  end

  defp normalize_fields([_field | _rest], _seen, _normalized),
    do: {:error, {:fields, "contains an unsupported field"}}

  defp normalize_fields(_improper, _seen, _normalized),
    do: {:error, {:fields, "expected a proper list"}}

  defp validate_assign(assign) when is_atom(assign), do: :ok
  defp validate_assign(_assign), do: {:error, {:assign, "expected an atom"}}

  defp validate_telemetry(telemetry) when is_boolean(telemetry), do: :ok
  defp validate_telemetry(_telemetry), do: {:error, {:telemetry, "expected a boolean"}}

  defp validate_redaction_options(:disabled, _opts), do: :ok

  defp validate_redaction_options(_mode, opts) do
    redaction_opts = Keyword.drop(opts, @integration_options)

    with {:ok, _options} <- Options.new(redaction_opts),
         {:ok, _operators} <- Anonymizer.validate_options(redaction_opts),
         {:ok, _probe} <-
           Obscura.Structured.redact(%{}, Keyword.put(redaction_opts, :telemetry, false)) do
      :ok
    else
      _error -> {:error, {:redaction, "contains invalid redaction options"}}
    end
  end
end
