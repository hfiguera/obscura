defmodule Obscura.Phoenix.Plug do
  @moduledoc """
  Plug-compatible request sanitization helper.
  """

  import Plug.Conn

  alias Obscura.Telemetry

  @doc false
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    start = System.monotonic_time()
    mode = Keyword.get(opts, :mode, :assign_redacted)
    fields = Keyword.get(opts, :fields, [:params])
    assign = Keyword.get(opts, :assign, :obscura_redacted)

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
    Map.new(fields, &redact_field(conn, &1, opts))
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

  defp apply_mode(redacted, conn, _mode, assign), do: {assign(conn, assign, redacted), redacted}
end
