defmodule Obscura.Spacy.RealModelTest do
  use ExUnit.Case, async: false
  alias Obscura.Profile
  alias Obscura.Spacy.{Assets, Serving}

  @model_dir System.get_env("OBSCURA_SPACY_MODEL_DIR")
  @moduletag skip: is_nil(@model_dir) or not Assets.supported_platform?()

  defp prepare(opts \\ []) do
    {:ok, runtime} = Profile.prepare(:spacy_cpu, Keyword.merge([model_dir: @model_dir], opts))

    on_exit(fn ->
      if Process.alive?(runtime.resources.spacy), do: Serving.stop(runtime.resources.spacy)
    end)

    runtime
  end

  test "profile analyzes UTF-8, redacts, and preserves structured precedence" do
    runtime = prepare()
    assert Serving.status(runtime.resources.spacy).backend == Assets.backend()
    text = "José García lives in São Paulo. Email alice@example.com."
    assert {:ok, results} = Obscura.analyze(text, profile: runtime, include_text: false)

    assert Enum.any?(
             results,
             &(&1.entity == :person and &1.byte_start == 0 and &1.byte_end == 13)
           )

    assert Enum.any?(
             results,
             &(&1.entity == :location and &1.byte_start == 23 and &1.byte_end == 33)
           )

    assert Enum.any?(results, &(&1.entity == :email))
    # A KiB value mislabeled as bytes would fall below this lower bound.
    assert Serving.status(runtime.resources.spacy).sum_peak_worker_rss_bytes > 1_048_576
    assert {:ok, _} = Obscura.redact(text, profile: runtime)

    assert {:ok, [^results, []]} =
             Obscura.analyze_many([text, ""], profile: runtime, include_text: false)

    assert {:ok, [%{entity: :email}]} =
             Obscura.analyze(text, profile: runtime, entities: [:email])
  end

  test "efficient is a stable reusable public runtime with controlled failures" do
    assert {:ok, :stable} = Profile.classification(:efficient)

    for workers <- 1..4 do
      assert {:ok, runtime} =
               Profile.prepare("efficient", model_dir: @model_dir, workers: workers)

      try do
        assert runtime.profile == :efficient

        assert {:ok, results} =
                 Obscura.analyze("José García lives in São Paulo. Email alice@example.com.",
                   profile: runtime
                 )

        assert Enum.any?(results, &(&1.entity == :person))
        assert Enum.any?(results, &(&1.entity == :location))
        assert Enum.any?(results, &(&1.entity == :email))
        assert {:ok, _} = Obscura.redact("Alice Smith lives in London.", profile: runtime)
        assert {:ok, [_, []]} = Obscura.analyze_many(["Alice Smith", ""], profile: runtime)
      after
        Serving.stop(runtime.resources.spacy)
      end

      assert {:error, _} = Obscura.analyze("Alice Smith", profile: runtime)
    end
  end

  test "supervised preparer owns the native pool for its lifetime" do
    {:ok, preparer} =
      Profile.Preparer.start_link(profile: :spacy_cpu, prepare_options: [model_dir: @model_dir])

    assert {:ok, runtime} = Profile.Preparer.await(preparer)
    assert Profile.available?(:spacy_cpu, serving: runtime.resources.spacy)
    monitor = Process.monitor(runtime.resources.spacy)
    GenServer.stop(preparer)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
  end

  test "bounded concurrent native calls return the same results" do
    runtime = prepare(workers: 2)
    text = "Alice Smith lives in London."
    assert {:ok, expected} = Obscura.analyze(text, profile: runtime, include_text: false)

    rows =
      1..20
      |> Task.async_stream(
        fn _ -> Obscura.analyze(text, profile: runtime, include_text: false) end,
        max_concurrency: 2
      )
      |> Enum.to_list()

    assert Enum.all?(rows, &(&1 == {:ok, {:ok, expected}}))
  end

  test "native process loss recovers and stale runtime fails closed after shutdown" do
    runtime = prepare()
    pool = runtime.resources.spacy
    state = :sys.get_state(pool)
    [{_, slot}] = Map.to_list(state.slots)

    :ok =
      :sys.replace_state(pool, fn state ->
        Port.close(slot.port)
        state
      end)
      |> then(fn _ -> :ok end)

    eventually(fn ->
      status = Serving.status(pool)
      status.workers == 1 and status.failures > 0
    end)

    assert {:ok, [_ | _]} = Obscura.analyze("Alice Smith lives in London.", profile: runtime)
    Serving.stop(pool)
    assert {:error, _} = Obscura.analyze("Alice", profile: runtime)
    refute Profile.available?(:spacy_cpu, serving: pool)
  end

  test "corrupt assets fail before native process startup" do
    dir =
      Path.join(System.tmp_dir!(), "obscura-spacy-corrupt-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    for name <- Map.keys(Assets.hashes()) do
      if name == "model.json",
        do: File.write!(Path.join(dir, name), "{}"),
        else: File.ln_s!(Path.join(@model_dir, name) |> Path.expand(), Path.join(dir, name))
    end

    assert {:error, %{code: :checkpoint_hash_mismatch}} =
             Profile.prepare(:spacy_cpu, model_dir: dir)
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(25)
          eventually(fun, attempts - 1)
        )
  end
end
