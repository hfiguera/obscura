defmodule Obscura.Eval.Operational.RuntimeHostTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.RuntimeHost
  alias Obscura.Internal.StageDiagnostics
  alias Obscura.Profile.Runtime

  setup do
    runtime = %Runtime{
      profile: :fast,
      implementation_profile: :deterministic_plus,
      resources: %{},
      analyzer_options: [profile: :fast, entities: [:email]],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{}
    }

    %{runtime: runtime}
  end

  test "enforces bounded overload with a structured value-safe error", %{runtime: runtime} do
    parent = self()

    analyzer = fn _input, _opts ->
      send(parent, :started)
      Process.sleep(30)
      {:ok, []}
    end

    {:ok, host} =
      RuntimeHost.start_link(runtime: runtime, analyzer: analyzer, max_in_flight: 1)

    first = Task.async(fn -> RuntimeHost.analyze(host, "private-one") end)
    assert_receive :started
    assert %{in_flight: 1, completed: 0, max_in_flight: 1} = RuntimeHost.stats(host)

    assert {:error, %{code: :overloaded, retryable: true} = error} =
             RuntimeHost.analyze(host, "private-two")

    refute inspect(error) =~ "private"
    assert {:ok, [], _timing} = Task.await(first)
    assert %{in_flight: 0, completed: 1, rejected: 1} = RuntimeHost.stats(host)
  end

  test "kills timed out work and returns no input value", %{runtime: runtime} do
    analyzer = fn _input, _opts ->
      Process.sleep(100)
      {:ok, []}
    end

    {:ok, host} = RuntimeHost.start_link(runtime: runtime, analyzer: analyzer)

    assert {:error, %{code: :request_timeout} = error} =
             RuntimeHost.analyze(host, "never-report-this", timeout: 1)

    refute inspect(error) =~ "never-report-this"
    assert %{timed_out: 1} = RuntimeHost.stats(host)
  end

  test "a supervisor replaces a killed gateway without rebuilding runtime", %{runtime: runtime} do
    {:ok, supervisor} =
      Supervisor.start_link(
        [{RuntimeHost, runtime: runtime, id: :runtime_host_test}],
        strategy: :one_for_one
      )

    [{_id, old_host, _type, _modules}] = Supervisor.which_children(supervisor)
    Process.exit(old_host, :kill)

    new_host =
      Enum.find_value(1..100, fn _attempt ->
        Process.sleep(2)
        [{_id, pid, _type, _modules}] = Supervisor.which_children(supervisor)
        if is_pid(pid) and pid != old_host, do: pid
      end)

    assert is_pid(new_host)
    assert {:ok, _results, _timing} = RuntimeHost.analyze(new_host, "jane@example.com")
  end

  test "returns privacy-safe queue and bounded stage diagnostics", %{runtime: runtime} do
    analyzer = fn _input, _opts ->
      StageDiagnostics.measure(:model_serving, fn -> Process.sleep(1) end)
      {:ok, []}
    end

    {:ok, host} =
      RuntimeHost.start_link(runtime: runtime, analyzer: analyzer, diagnostics: true)

    assert {:ok, [], service} = RuntimeHost.analyze(host, "private-source")
    assert service.queue_ms >= 0
    assert service.service_ms >= 0
    assert service.diagnostics.status == :measured
    assert service.diagnostics.metadata.input_bytes == byte_size("private-source")
    assert service.diagnostics.stages.model_serving.count == 1
    refute inspect(service) =~ "private-source"
  end
end
