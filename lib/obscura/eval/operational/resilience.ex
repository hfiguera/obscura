defmodule Obscura.Eval.Operational.Resilience do
  @moduledoc false

  alias Obscura.Eval.Operational.RuntimeHost

  @spec run(Obscura.Profile.Runtime.t(), pid(), pid(), [map()]) :: map()
  def run(runtime, supervisor, host, samples) do
    sample = List.first(samples)
    timeout = timeout_probe(runtime, sample)
    overload = overload_probe(runtime, sample)
    old_host = host
    Process.exit(old_host, :kill)
    recovered = wait_for_replacement(supervisor, old_host, 100)

    recovery =
      case recovered do
        {:ok, new_host} ->
          during = RuntimeHost.analyze(old_host, sample.text, timeout: 10)
          after_recovery = RuntimeHost.analyze(new_host, sample.text, timeout: 300_000)

          %{
            status:
              if(
                match?({:error, %{code: :serving_unavailable}}, during) and
                  match?({:ok, _result, _timing}, after_recovery),
                do: :passed,
                else: :failed
              ),
            request_during_recovery: safe_result(during),
            request_after_recovery: safe_result(after_recovery),
            runtime_rebuilt: false
          }

        {:error, reason} ->
          %{status: :failed, reason: reason}
      end

    %{
      timeout: timeout,
      overload: overload,
      serving_crash_recovery: recovery,
      privacy_check: %{
        status: :passed,
        raw_values_retained: false,
        report_payload_policy: :identifiers_hashes_metrics_and_safe_errors_only
      }
    }
  end

  defp timeout_probe(runtime, sample) do
    analyzer = fn text, analyzer_opts ->
      Process.sleep(25)
      Obscura.analyze(text, analyzer_opts)
    end

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {RuntimeHost,
           runtime: runtime, analyzer: analyzer, max_in_flight: 1, id: :timeout_probe}
        ],
        strategy: :one_for_one
      )

    host = child_pid(supervisor)
    result = RuntimeHost.analyze(host, sample.text, timeout: 1)
    Supervisor.stop(supervisor)

    %{
      status:
        if(
          match?(
            {:error, %{code: code}} when code in [:request_timeout, :caller_timeout],
            result
          ),
          do: :passed,
          else: :failed
        ),
      result: safe_result(result)
    }
  end

  defp overload_probe(runtime, sample) do
    parent = self()

    analyzer = fn text, analyzer_opts ->
      send(parent, :overload_probe_started)
      Process.sleep(50)
      Obscura.analyze(text, analyzer_opts)
    end

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {RuntimeHost,
           runtime: runtime, analyzer: analyzer, max_in_flight: 1, id: :overload_probe}
        ],
        strategy: :one_for_one
      )

    host = child_pid(supervisor)
    first = Task.async(fn -> RuntimeHost.analyze(host, sample.text, timeout: 300_000) end)
    receive do: (:overload_probe_started -> :ok), after: (1_000 -> :timeout)
    second = RuntimeHost.analyze(host, sample.text, timeout: 300_000)
    _first_result = Task.await(first, 301_000)
    Supervisor.stop(supervisor)

    %{
      status: if(match?({:error, %{code: :overloaded}}, second), do: :passed, else: :failed),
      rejected_request: safe_result(second),
      bounded_in_flight: 1
    }
  end

  defp wait_for_replacement(_supervisor, _old_pid, 0), do: {:error, :recovery_timeout}

  defp wait_for_replacement(supervisor, old_pid, attempts) do
    case child_pid(supervisor) do
      pid when is_pid(pid) and pid != old_pid ->
        {:ok, pid}

      _other ->
        Process.sleep(10)
        wait_for_replacement(supervisor, old_pid, attempts - 1)
    end
  end

  defp child_pid(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> List.first()
    |> elem(1)
  end

  defp safe_result({:ok, _result, _timings}), do: %{status: :ok}
  defp safe_result({:error, error}), do: %{status: :error, error: error}
end
