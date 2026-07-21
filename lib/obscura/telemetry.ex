defmodule Obscura.Telemetry do
  @moduledoc """
  Safe telemetry wrapper for Obscura public APIs.
  """

  @measurement_keys [
    :bytes_received,
    :duration,
    :duration_ms,
    :elapsed_ms,
    :latency_ms,
    :percent,
    :sample_count,
    :total_bytes
  ]
  @metadata_keys [
    :backend,
    :cache_directory_source,
    :cache_status,
    :dataset,
    :diagnostic_code,
    :entities,
    :entity,
    :input_count,
    :input_type,
    :lookup,
    :message_count,
    :model_alias,
    :model_count,
    :model_index,
    :profile,
    :recognizer,
    :redacted_message_count,
    :requested_profile,
    :result_count,
    :sample_count,
    :status,
    :stage,
    :token_count,
    :token_created
  ]

  @doc """
  Emits a telemetry event unless disabled.
  """
  @spec execute(boolean(), [atom()], map(), map()) :: :ok
  def execute(false, _event, _measurements, _metadata), do: :ok

  def execute(true, event, measurements, metadata) do
    :telemetry.execute(
      event,
      sanitize_measurements(measurements),
      sanitize_metadata(metadata)
    )
  end

  @doc """
  Returns telemetry-safe metadata through a strict key and value allowlist.
  """
  @spec sanitize_metadata(map()) :: map()
  def sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.take(@metadata_keys)
    |> Map.new(fn {key, value} -> {key, safe_value(value)} end)
  end

  def sanitize_metadata(_metadata), do: %{}

  defp sanitize_measurements(measurements) when is_map(measurements) do
    measurements
    |> Map.take(@measurement_keys)
    |> Map.new(fn
      {key, value} when is_integer(value) or is_float(value) -> {key, value}
      {key, _value} -> {key, 0}
    end)
  end

  defp sanitize_measurements(_measurements), do: %{}

  defp safe_value(value)
       when is_atom(value) or is_integer(value) or is_float(value) or is_boolean(value),
       do: value

  defp safe_value(values) when is_list(values) do
    Enum.map(values, fn
      value when is_atom(value) or is_integer(value) -> value
      _value -> :redacted
    end)
  end

  defp safe_value(_value), do: :redacted
end
