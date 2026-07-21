defmodule Obscura.Recognizer.GLiNER.Ortex.CoreML do
  @moduledoc false

  @defaults [
    model_format: :ml_program,
    compute_units: :cpu_and_gpu,
    require_static_input_shapes: false,
    enable_on_subgraphs: false
  ]

  @allowed_options Keyword.keys(@defaults)
  @model_formats [:ml_program, :neural_network]
  @compute_units [:all, :cpu_only, :cpu_and_gpu, :cpu_and_neural_engine]

  @spec default_options() :: keyword()
  def default_options, do: @defaults

  @spec validate_options(keyword()) :: {:ok, keyword()} | {:error, term()}
  def validate_options(options) when is_list(options) do
    unknown = Keyword.keys(options) -- @allowed_options
    merged = Keyword.merge(@defaults, options)

    cond do
      unknown != [] ->
        {:error, {:unknown_coreml_options, unknown}}

      merged[:model_format] not in @model_formats ->
        {:error, {:invalid_coreml_model_format, merged[:model_format]}}

      merged[:compute_units] not in @compute_units ->
        {:error, {:invalid_coreml_compute_units, merged[:compute_units]}}

      not is_boolean(merged[:require_static_input_shapes]) ->
        {:error,
         {:invalid_coreml_require_static_input_shapes, merged[:require_static_input_shapes]}}

      not is_boolean(merged[:enable_on_subgraphs]) ->
        {:error, {:invalid_coreml_enable_on_subgraphs, merged[:enable_on_subgraphs]}}

      true ->
        {:ok, merged}
    end
  end

  def validate_options(options), do: {:error, {:invalid_coreml_options, options}}

  @spec summarize_profile(Path.t()) :: {:ok, map()} | {:error, term()}
  def summarize_profile(path) when is_binary(path) do
    with {:ok, encoded} <- File.read(path),
         {:ok, decoded} <- Jason.decode(encoded),
         {:ok, events} <- trace_events(decoded) do
      {:ok, summarize_events(events, path)}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_onnx_profile, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec summarize_events([map()], Path.t() | nil) :: map()
  def summarize_events(events, path \\ nil) when is_list(events) do
    node_events = Enum.filter(events, &node_event?/1)
    provider_events = Enum.filter(node_events, &(provider_name(&1) != nil))

    provider_counts =
      Enum.frequencies_by(provider_events, &provider_name/1)

    provider_duration_us =
      Enum.reduce(provider_events, %{}, fn event, acc ->
        provider = provider_name(event)
        duration = numeric_value(event["dur"])
        Map.update(acc, provider, duration, &(&1 + duration))
      end)

    coreml_events = Map.get(provider_counts, "CoreMLExecutionProvider", 0)
    cpu_events = Map.get(provider_counts, "CPUExecutionProvider", 0)
    provider_event_count = length(provider_events)
    provider_duration = provider_duration_us |> Map.values() |> Enum.sum()
    coreml_duration = Map.get(provider_duration_us, "CoreMLExecutionProvider", 0)

    status =
      cond do
        coreml_events > 0 -> :coreml_participation_verified
        provider_events == [] -> :provider_assignment_unavailable
        true -> :coreml_not_assigned
      end

    %{
      status: status,
      profile_path: path,
      node_event_count: length(node_events),
      provider_event_count: provider_event_count,
      unassigned_node_event_count: length(node_events) - length(provider_events),
      provider_event_counts: provider_counts,
      provider_duration_us: provider_duration_us,
      coreml_event_count: coreml_events,
      cpu_event_count: cpu_events,
      coreml_provider_event_fraction: ratio(coreml_events, provider_event_count),
      coreml_provider_duration_fraction: ratio(coreml_duration, provider_duration),
      coreml_participated: coreml_events > 0,
      cpu_fallback_observed: cpu_events > 0,
      gpu_only_proven: false,
      gpu_only_limitation: :coreml_has_no_gpu_only_compute_unit
    }
  end

  defp trace_events(events) when is_list(events), do: {:ok, events}
  defp trace_events(%{"traceEvents" => events}) when is_list(events), do: {:ok, events}
  defp trace_events(_decoded), do: {:error, :invalid_onnx_profile_shape}

  defp node_event?(%{"cat" => "Node"}), do: true
  defp node_event?(_event), do: false

  defp provider_name(%{"args" => args}) when is_map(args) do
    args["provider"] || args["execution_provider"]
  end

  defp provider_name(_event), do: nil

  defp numeric_value(value) when is_integer(value), do: value
  defp numeric_value(value) when is_float(value), do: value
  defp numeric_value(_value), do: 0

  defp ratio(_value, 0), do: 0.0
  defp ratio(value, total), do: value / total
end
