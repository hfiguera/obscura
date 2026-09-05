defmodule Obscura.SpacyNative.Worker do
  @moduledoc "A serial, Python-free native Port worker for the evaluation prototype."
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)
  def predict(worker, text), do: GenServer.call(worker, {:predict, text}, 35_000)
  def ready(worker), do: GenServer.call(worker, :ready)

  @impl true
  def init(opts) do
    root = Path.expand(__DIR__)

    binary =
      Keyword.get(
        opts,
        :binary,
        Path.expand(
          "../../native/spacy_cpu/target/aarch64-apple-darwin/release/obscura-spacy-native-prototype",
          root
        )
      )

    args = Keyword.get(opts, :args, [Path.join(root, "assets")])
    started = System.monotonic_time()

    port =
      Port.open({:spawn_executable, binary}, [
        :binary,
        :exit_status,
        {:line, 8_388_608},
        {:args, args},
        {:env, [{~c"VECLIB_MAXIMUM_THREADS", ~c"1"}]}
      ])

    case response(port) do
      {:ok, %{"ready" => true} = ready} ->
        ready = Map.put(ready, "startup_ms", elapsed(started))
        {:ok, %{port: port, ready: ready}}

      _ ->
        close(port)
        {:stop, :native_startup_failed}
    end
  end

  @impl true
  def handle_call(:ready, _from, state), do: {:reply, state.ready, state}

  def handle_call({:predict, text}, _from, state) when byte_size(text) <= 1_048_576 do
    true = Port.command(state.port, [Jason.encode!(%{text: text}), "\n"])

    case response(state.port) do
      {:ok, %{"error" => _}} -> {:reply, {:error, :native_inference_failed}, state}
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:stop, reason, {:error, reason}, state}
    end
  end

  def handle_call({:predict, _text}, _from, state),
    do: {:reply, {:error, :native_input_limit}, state}

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:stop, {:native_exit, status}, state}

  @impl true
  def terminate(_reason, state), do: close(state.port)

  defp response(port) do
    receive do
      {^port, {:data, {:eol, line}}} -> Jason.decode(line)
      {^port, {:data, {:noeol, _}}} -> {:error, :native_response_limit}
      {^port, {:exit_status, status}} -> {:error, {:native_exit, status}}
    after
      30_000 -> {:error, :native_timeout}
    end
  end

  defp close(port), do: if(Port.info(port), do: Port.close(port))

  defp elapsed(started),
    do: System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond) / 1000
end

defmodule Obscura.SpacyNative.Recognizer do
  @moduledoc "Experimental spaCy NER recognizer; use with :deterministic_plus."
  @behaviour Obscura.Recognizer
  @labels ["PERSON", "GPE", "LOC", "FAC"]

  @impl true
  def name, do: :spacy_native_prototype
  @impl true
  def supported_entities, do: [:person, :location]

  @impl true
  def analyze(text, opts) do
    with {:ok, result} <- Obscura.SpacyNative.Worker.predict(Keyword.fetch!(opts, :worker), text) do
      if recipient = Keyword.get(opts, :stats_recipient),
        do: send(recipient, {:spacy_native_stats, result})

      outputs =
        result["predictions"]
        |> Enum.filter(&(&1["label"] in @labels))
        |> Enum.map(fn p ->
          %{
            label: p["label"],
            start: p["byte_start"],
            end: p["byte_end"],
            score: p["score"],
            offset_unit: :byte
          }
        end)

      Obscura.Analyzer.ModelOutput.normalize(text, outputs,
        include_text: false,
        label_map: %{person: ["PERSON"], location: ["GPE", "LOC", "FAC"]},
        unknown_labels: :error
      )
    end
  end
end
