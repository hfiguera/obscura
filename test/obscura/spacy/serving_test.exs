defmodule Obscura.Spacy.ServingTest do
  use ExUnit.Case, async: true
  alias Obscura.Spacy.Assets
  alias Obscura.Spacy.Serving

  # The process protocol is tested with a tiny executable; it is never used for
  # accuracy. This bypasses asset loading to keep lifecycle tests portable.
  defp pool(context, response \\ :ok, timeout \\ 500) do
    dir = Path.join(System.tmp_dir!(), "obscura-spacy-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    binary = Path.join(dir, "worker")

    ready =
      Jason.encode!(%{
        ready: true,
        protocol_version: 1,
        python_runtime: false,
        backend: Map.get(context, :backend, Assets.native_backend()),
        model: "en_core_web_lg",
        model_version: "3.8.0"
      })

    result =
      Jason.encode!(%{predictions: [%{label: "PERSON", byte_start: 0, byte_end: 5, score: 0.85}]})

    action =
      case response do
        :ok ->
          "printf '%s\\n' '#{result}'"

        :hang ->
          "sleep 2"

        :crash ->
          "exit 3"

        :malformed ->
          "printf '%s\\n' 'PRIVATE_RESPONSE_MUST_NOT_ESCAPE'"

        :threads ->
          "test \"$VECLIB_MAXIMUM_THREADS:$OPENBLAS_NUM_THREADS:$OPENBLAS_DEFAULT_NUM_THREADS:$OMP_NUM_THREADS\" = 1:1:1:1 && printf '%s\\n' '#{result}'"
      end

    File.write!(
      binary,
      "#!/bin/sh\nprintf '%s\\n' '#{ready}'\nwhile IFS= read -r line; do\n#{action}\ndone\n"
    )

    File.chmod!(binary, 0o755)

    args = %{
      paths: %{native_binary: binary, model_dir: dir},
      count: Map.get(context, :workers, 1),
      timeout: timeout,
      owner: self(),
      starter: self()
    }

    on_exit(fn -> File.rm_rf!(dir) end)

    case GenServer.start(Serving, args) do
      {:ok, server} ->
        on_exit(fn -> stop_if_alive(server) end)
        server

      error ->
        error
    end
  end

  defp stop_if_alive(server), do: if(Process.alive?(server), do: Serving.stop(server))

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, attempts - 1)
        )
  end

  test "bounded admission occurs before source text reaches the pool", context do
    server = pool(context)
    assert {:ok, _lease} = GenServer.call(server, :reserve)
    assert {:error, :spacy_busy} = Serving.predict(server, "PRIVATE_SOURCE_MUST_NOT_QUEUE")
    assert %{busy: 1, queued_inputs: 0, workers: 1} = Serving.status(server)
    refute inspect(:sys.get_state(server)) =~ "PRIVATE_SOURCE"
  end

  test "a native worker must identify the host CPU backend", context do
    assert {:error, :native_startup_failed} = pool(Map.put(context, :backend, "wrong_backend"))
  end

  test "child math libraries are limited to one thread", context do
    server = pool(context, :threads)
    assert {:ok, [_]} = Serving.predict(server, "Alice")
  end

  test "successful responses release the reservation", context do
    server = pool(context)
    assert {:ok, [%{"label" => "PERSON"}]} = Serving.predict(server, "Alice")
    assert %{busy: 0} = Serving.status(server)
    assert {:ok, [_]} = Serving.predict(server, "Alice")
  end

  test "timed out requests discard the worker and release capacity", context do
    server = pool(context, :hang, 50)
    assert {:error, :spacy_timeout} = Serving.predict(server, "PRIVATE_SOURCE")
    eventually(fn -> match?(%{workers: 1, busy: 0, failures: 1}, Serving.status(server)) end)
    refute inspect(:sys.get_state(server)) =~ "PRIVATE_SOURCE"
  end

  test "malformed output is sanitized and worker replaced", context do
    server = pool(context, :malformed)
    assert {:error, :spacy_invalid_response} = Serving.predict(server, "Alice")
    eventually(fn -> Serving.status(server).workers == 1 end)
    refute inspect(:sys.get_state(server)) =~ "PRIVATE_RESPONSE"
  end

  test "native exit fails the current request and recovers", context do
    server = pool(context, :crash)
    assert {:error, :spacy_worker_failed} = Serving.predict(server, "Alice")
    eventually(fn -> Serving.status(server).workers == 1 end)
  end

  test "caller death cancels an active request", context do
    server = pool(context, :hang)
    caller = spawn(fn -> Serving.predict(server, "PRIVATE_SOURCE") end)
    eventually(fn -> Serving.status(server).busy == 1 end)
    Process.exit(caller, :kill)
    eventually(fn -> match?(%{workers: 1, busy: 0, failures: 1}, Serving.status(server)) end)
  end

  test "abandoned reservations do not consume the worker restart budget", context do
    server = pool(context)
    original = :sys.get_state(server).slots[1].port
    parent = self()

    for _ <- 1..10 do
      caller =
        spawn(fn ->
          {:ok, _} = GenServer.call(server, :reserve)
          send(parent, :reserved)

          receive do
            :exit -> :ok
          end
        end)

      assert_receive :reserved
      send(caller, :exit)
      eventually(fn -> Serving.status(server).busy == 0 end)
    end

    assert :sys.get_state(server).slots[1].port == original
    assert %{workers: 1, failures: 0} = Serving.status(server)
    assert {:ok, [_]} = Serving.predict(server, "Alice")
  end

  test "reservation expiry cannot leave capacity occupied", context do
    server = pool(context, :ok, 40)
    assert {:ok, lease} = GenServer.call(server, :reserve)
    eventually(fn -> match?(%{workers: 1, busy: 0, failures: 1}, Serving.status(server)) end)
    assert {:error, :spacy_invalid_lease} = GenServer.call(server, {:predict, lease, "Alice"})
    assert {:ok, [_]} = Serving.predict(server, "Alice")
  end

  test "owner death closes the pool and its ports", context do
    server = pool(context)

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    :sys.replace_state(server, fn state -> %{state | owner_monitor: Process.monitor(owner)} end)
    monitor = Process.monitor(server)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^server, :normal}, 1_000
  end

  test "limits and invalid UTF-8 fail before reservation", context do
    server = pool(context)

    assert {:error, :spacy_input_limit} =
             Serving.predict(server, String.duplicate("x", 1_048_577))

    assert {:error, :spacy_invalid_input} = Serving.predict(server, <<255>>)
    assert %{busy: 0} = Serving.status(server)
  end

  test "two workers admit two reservations and reject a third", context do
    server = pool(Map.put(context, :workers, 2))
    assert {:ok, a} = GenServer.call(server, :reserve)
    assert {:ok, b} = GenServer.call(server, :reserve)
    assert {:error, :spacy_busy} = GenServer.call(server, :reserve)
    assert {:ok, [_]} = GenServer.call(server, {:predict, a, "Alice"})
    assert {:ok, [_]} = GenServer.call(server, {:predict, b, "Alice"})
    assert %{busy: 0, workers: 2} = Serving.status(server)
  end

  test "crash formatting redacts state and last message" do
    formatted =
      Serving.format_status(%{
        state: "PRIVATE",
        message: "PRIVATE",
        reason: "PRIVATE",
        log: ["PRIVATE"]
      })

    refute inspect(formatted) =~ "PRIVATE"
  end
end
