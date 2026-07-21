defmodule Obscura.Eval.Operational.SystemProbe do
  @moduledoc false

  @spec capture() :: map()
  def capture do
    %{
      process_cpu_percent: process_cpu_percent(),
      beam_runtime: beam_runtime(),
      thermal: thermal(),
      power: power(),
      gpu_activity: gpu_activity()
    }
  end

  @spec capabilities() :: map()
  def capabilities do
    %{
      process_cpu: %{status: :measured, source: :ps},
      beam_runtime: %{status: :measured, source: :erlang_statistics},
      thermal: command_capability("pmset"),
      power: command_capability("pmset"),
      gpu_activity:
        if(superuser?(),
          do: %{status: :available, source: :powermetrics},
          else: %{status: :unavailable, reason: :powermetrics_requires_superuser}
        )
    }
  end

  defp beam_runtime do
    {reductions, _since_last} = :erlang.statistics(:reductions)
    {collections, reclaimed_words, _} = :erlang.statistics(:garbage_collection)

    %{
      process_count: :erlang.system_info(:process_count),
      reductions: reductions,
      garbage_collections: collections,
      garbage_reclaimed_words: reclaimed_words
    }
  end

  defp process_cpu_percent do
    case command("ps", ["-o", "%cpu=", "-p", System.pid()]) do
      {:ok, value} -> parse_number(value)
      {:error, _reason} -> nil
    end
  end

  defp thermal do
    case command("pmset", ["-g", "therm"]) do
      {:ok, output} ->
        limits =
          output
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, &parse_thermal_line/2)

        if map_size(limits) == 0 do
          %{status: :unavailable, reason: :no_numeric_thermal_or_performance_limits}
        else
          Map.merge(%{status: :measured, source: :pmset}, limits)
        end

      {:error, reason} ->
        %{status: :unavailable, reason: reason}
    end
  end

  defp power do
    case command("pmset", ["-g", "batt"]) do
      {:ok, output} ->
        source =
          cond do
            String.contains?(output, "AC Power") -> :ac_power
            String.contains?(output, "Battery Power") -> :battery
            true -> :unknown
          end

        %{status: :measured, source: :pmset, power_source: source}

      {:error, reason} ->
        %{status: :unavailable, reason: reason}
    end
  end

  defp gpu_activity do
    if superuser?() do
      %{
        status: :unavailable,
        reason: :powermetrics_stream_not_enabled_for_embedded_sampler
      }
    else
      %{status: :unavailable, reason: :powermetrics_requires_superuser}
    end
  end

  defp parse_thermal_line(line, acc) do
    case Regex.run(
           ~r/^\s*(CPU_Speed_Limit|GPU_Speed_Limit|Thermal_Level|Performance_Level)\s*=\s*(\d+)/,
           line
         ) do
      [_, name, value] ->
        Map.put(acc, thermal_key(name), String.to_integer(value))

      _other ->
        acc
    end
  end

  defp thermal_key("CPU_Speed_Limit"), do: :cpu_speed_limit
  defp thermal_key("GPU_Speed_Limit"), do: :gpu_speed_limit
  defp thermal_key("Thermal_Level"), do: :thermal_level
  defp thermal_key("Performance_Level"), do: :performance_level

  defp command_capability(executable) do
    if System.find_executable(executable),
      do: %{status: :available, source: String.to_atom(executable)},
      else: %{status: :unavailable, reason: :command_not_found}
  end

  defp superuser? do
    case command("id", ["-u"]) do
      {:ok, "0"} -> true
      _other -> false
    end
  end

  defp parse_number(value) do
    case Float.parse(String.trim(value)) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp command(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {_output, _status} -> {:error, :command_failed}
    end
  rescue
    _error -> {:error, :command_unavailable}
  end
end
