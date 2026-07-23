defmodule Obscura.Profile.PreparationTest do
  use ExUnit.Case, async: false

  alias Obscura.Diagnostic
  alias Obscura.Profile
  alias Obscura.Profile.Cache
  alias Obscura.Recognizer.NER.FakeServing

  @missing_cache %{status: :missing, bytes: 0, repositories: []}
  @present_cache %{status: :present, bytes: 1_024, repositories: []}

  test "model downloads require explicit permission" do
    parent = self()

    assert {:error, %Diagnostic{code: :model_download_not_allowed}} =
             Profile.prepare(:balanced,
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: fn _opts ->
                 send(parent, :unexpected_build)
                 {:ok, FakeServing.new([])}
               end
             )

    refute_received :unexpected_build
  end

  test "offline preparation never accepts a cache miss" do
    assert {:error, %Diagnostic{code: :missing_model_asset}} =
             Profile.prepare(:balanced,
               offline: true,
               allow_download: true,
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end
             )
  end

  test "cache hits force Bumblebee offline and can be prepared repeatedly" do
    parent = self()

    builder = fn opts ->
      send(parent, {:offline, opts[:offline]})
      {:ok, FakeServing.new([])}
    end

    opts = [
      cache_probe: probe(@present_cache),
      dependency_checker: fn _dependency -> true end,
      ner_serving_builder: builder
    ]

    assert {:ok, _runtime} = Profile.prepare(:balanced, opts)
    assert {:ok, _runtime} = Profile.prepare(:balanced, opts)
    assert_receive {:offline, true}
    assert_receive {:offline, true}
  end

  test "progress events are ordered, safe, and identify both accurate models" do
    parent = self()

    builder = fn opts ->
      observer = Keyword.fetch!(opts, :stage_observer)
      observer.(%{component: :ner_serving, stage: :model_load, status: :started})
      observer.(%{component: :ner_serving, stage: :model_load, status: :ok, duration_ms: 1.0})
      {:ok, FakeServing.new([])}
    end

    assert {:ok, _runtime} =
             Profile.prepare(:accurate,
               allow_download: true,
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: builder,
               progress: fn event -> send(parent, {:progress, event}) end
             )

    events = collect_progress([])
    assert hd(events).event == :asset_license_notice
    assert hd(events).asset == "tner_roberta_large_ontonotes5"
    assert hd(events).commercial_use == "requires_ldc_for_profit_membership"
    assert Enum.at(events, 1).event == :preparation_started
    assert List.last(events).event == :preparation_completed

    started_models =
      for %{event: :stage_started, stage: :model_load, model: model} <- events, do: model

    assert started_models == [
             :tner_roberta_large_ontonotes5,
             :jean_baptiste_roberta_large_ner_english
           ]

    assert Enum.any?(events, &(&1[:model_index] == 1 and &1[:model_count] == 2))
    assert Enum.any?(events, &(&1[:model_index] == 2 and &1[:model_count] == 2))

    encoded = Jason.encode!(events)
    refute encoded =~ "auth_token"
    refute encoded =~ "raw_text"
    refute encoded =~ System.user_home!()
  end

  test "progress callback failures do not abort preparation" do
    assert {:ok, _runtime} =
             Profile.prepare(:fast, progress: fn _event -> raise "callback failed" end)
  end

  test "fast preparation emits no model asset license notice" do
    parent = self()

    assert {:ok, _runtime} =
             Profile.prepare(:fast,
               progress: fn event -> send(parent, {:progress, event}) end
             )

    refute Enum.any?(collect_progress([]), &(&1.event == :asset_license_notice))
  end

  test "overall timeout terminates controlled preparation" do
    assert {:error, %Diagnostic{code: :preparation_timeout}} =
             Profile.prepare(:balanced,
               allow_download: true,
               timeout: 25,
               inactivity_timeout: 500,
               progress_interval: 5,
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: fn _opts ->
                 Process.sleep(200)
                 {:ok, FakeServing.new([])}
               end
             )
  end

  test "inactivity timeout terminates a silent preparation stage" do
    assert {:error, %Diagnostic{code: :preparation_inactivity_timeout}} =
             Profile.prepare(:balanced,
               allow_download: true,
               timeout: 500,
               inactivity_timeout: 25,
               progress_interval: 5,
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: fn _opts ->
                 Process.sleep(200)
                 {:ok, FakeServing.new([])}
               end
             )
  end

  test "cache growth emits byte progress and resets inactivity" do
    {:ok, bytes} = Agent.start_link(fn -> 0 end)
    parent = self()

    probe = fn _descriptor, _opts ->
      %{status: :missing, bytes: Agent.get(bytes, & &1), repositories: []}
    end

    builder = fn _opts ->
      Agent.update(bytes, &(&1 + 128))
      Process.sleep(30)
      Agent.update(bytes, &(&1 + 128))
      Process.sleep(30)
      {:ok, FakeServing.new([])}
    end

    assert {:ok, _runtime} =
             Profile.prepare(:balanced,
               allow_download: true,
               progress_interval: 5,
               inactivity_timeout: 40,
               cache_probe: probe,
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: builder,
               progress: fn event -> send(parent, {:progress, event}) end
             )

    events = collect_progress([])

    assert Enum.any?(events, fn event ->
             event.event == :stage_progress and event.stage == :download and
               event.bytes_received >= 128
           end)
  end

  test "concurrent preparation is serialized per profile" do
    {:ok, active} = Agent.start_link(fn -> %{current: 0, maximum: 0} end)

    builder = fn _opts ->
      Agent.update(active, fn state ->
        current = state.current + 1
        %{current: current, maximum: max(current, state.maximum)}
      end)

      Process.sleep(40)
      Agent.update(active, &%{&1 | current: &1.current - 1})
      {:ok, FakeServing.new([])}
    end

    opts = [
      allow_download: true,
      cache_probe: probe(@missing_cache),
      dependency_checker: fn _dependency -> true end,
      ner_serving_builder: builder
    ]

    results =
      1..2
      |> Task.async_stream(fn _index -> Profile.prepare(:balanced, opts) end,
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _runtime}}, &1))
    assert Agent.get(active, & &1.maximum) == 1
  end

  test "orphaned cache entries are quarantined before an online retry" do
    cache_dir =
      Path.join(System.tmp_dir!(), "obscura-cache-#{System.unique_integer([:positive])}")

    scope = Path.join([cache_dir, "huggingface", "tner--roberta-large-ontonotes5"])
    File.mkdir_p!(scope)
    partial = Path.join(scope, "urlhash.etag")
    File.write!(partial, "partial")
    parent = self()

    on_exit(fn -> File.rm_rf!(cache_dir) end)

    assert {:ok, descriptor} = Profile.fetch(:balanced)
    assert {:ok, %{status: :partial}} = Cache.inspect(descriptor, cache_opts(cache_dir))

    assert {:ok, _runtime} =
             Profile.prepare(
               :balanced,
               [
                 allow_download: true,
                 progress_interval: 5,
                 dependency_checker: fn _dependency -> true end,
                 ner_serving_builder: fn _opts ->
                   File.write!(Path.join(scope, "retry.etag"), :binary.copy(<<0>>, 128))
                   Process.sleep(25)
                   {:ok, FakeServing.new([])}
                 end,
                 progress: fn event -> send(parent, {:progress, event}) end
               ] ++ cache_opts(cache_dir)
             )

    refute File.exists?(partial)

    assert Path.wildcard(Path.join([cache_dir, ".obscura-quarantine", "**", "*"])) != []

    assert Enum.any?(collect_progress([]), fn event ->
             event.event == :stage_progress and event.bytes_received == 128
           end)
  end

  test "cache inspection keeps separate model and tokenizer roots" do
    root =
      Path.join(System.tmp_dir!(), "obscura-split-cache-#{System.unique_integer([:positive])}")

    model_cache = Path.join(root, "model")
    tokenizer_cache = Path.join(root, "tokenizer")
    scope = Path.join([model_cache, "huggingface", "tner--roberta-large-ontonotes5"])
    File.mkdir_p!(scope)
    File.write!(Path.join(scope, "resolved.json"), "{}")

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, descriptor} = Profile.fetch(:balanced)

    assert {:ok, snapshot} =
             Cache.inspect(descriptor,
               model_repository_opts: [cache_dir: model_cache],
               tokenizer_repository_opts: [cache_dir: tokenizer_cache]
             )

    assert snapshot.status == :missing

    assert Enum.map(snapshot.repositories, &{&1.kind, &1.status}) == [
             model: :present,
             tokenizer: :missing
           ]
  end

  test "specific model and tokenizer load failures remain distinguishable" do
    common = [
      allow_download: true,
      cache_probe: probe(@missing_cache),
      dependency_checker: fn _dependency -> true end
    ]

    assert {:error, %Diagnostic{code: :model_load_failed}} =
             Profile.prepare(
               :balanced,
               Keyword.put(common, :ner_serving_builder, fn _opts ->
                 {:error, {:model_load_failed, :invalid_checkpoint}}
               end)
             )

    assert {:error, %Diagnostic{code: :tokenizer_load_failed}} =
             Profile.prepare(
               :balanced,
               Keyword.put(common, :ner_serving_builder, fn _opts ->
                 {:error, {:tokenizer_load_failed, :invalid_tokenizer}}
               end)
             )
  end

  test "a present but unusable offline cache is reported as incomplete" do
    assert {:error, %Diagnostic{code: :model_asset_incomplete}} =
             Profile.prepare(:balanced,
               cache_probe: probe(@present_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: fn _opts ->
                 {:error, {:model_load_failed, :invalid_checkpoint}}
               end
             )
  end

  test "cache and backend failures return specific safe diagnostics" do
    assert {:error, %Diagnostic{code: :model_cache_failure}} =
             Profile.prepare(:balanced,
               cache_probe: fn _descriptor, _opts -> {:error, {:cache_failure, :eacces}} end,
               dependency_checker: fn _dependency -> true end
             )

    assert {:error, %Diagnostic{code: :backend_unavailable}} =
             Profile.prepare(:balanced,
               allow_download: true,
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: fn _opts ->
                 {:error, {:backend_configuration_failed, :emily, :device_unavailable}}
               end
             )
  end

  test "abnormal preparation worker exits are controlled" do
    assert {:error, %Diagnostic{code: :model_download_interrupted}} =
             Profile.prepare(:balanced,
               allow_download: true,
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: fn _opts -> exit(:download_process_failed) end
             )
  end

  test "malformed preparation options fail before asset work" do
    assert {:error, %Diagnostic{code: :profile_requirements_unsatisfied}} =
             Profile.prepare(:balanced, allow_download: :yes)

    assert {:error, %Diagnostic{code: :profile_requirements_unsatisfied}} =
             Profile.prepare(:balanced, timeout: 0)

    assert {:error, %Diagnostic{code: :profile_requirements_unsatisfied}} =
             Profile.prepare(:balanced, progress: :logger)
  end

  test "credentials and private values never enter diagnostics or progress" do
    parent = self()

    assert {:error, diagnostic} =
             Profile.prepare(:balanced,
               allow_download: true,
               model_repository_opts: [auth_token: "hf_private_value"],
               cache_probe: probe(@missing_cache),
               dependency_checker: fn _dependency -> true end,
               ner_serving_builder: fn _opts -> {:error, {:model_load_failed, "raw private"}} end,
               progress: fn event -> send(parent, {:progress, event}) end
             )

    rendered = diagnostic |> Diagnostic.to_map() |> Jason.encode!()
    events = collect_progress([]) |> Jason.encode!()

    refute rendered =~ "hf_private_value"
    refute rendered =~ "raw private"
    refute events =~ "hf_private_value"
    refute events =~ "raw private"
  end

  test "preparation telemetry uses the safe allowlist" do
    handler = "preparation-telemetry-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach_many(
      handler,
      [
        [:obscura, :profile, :preparation, :preparation_started],
        [:obscura, :profile, :preparation, :preparation_completed]
      ],
      fn event, measurements, metadata, _config ->
        send(parent, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:ok, _runtime} = Profile.prepare(:fast)

    assert_receive {:telemetry, _event, %{elapsed_ms: _elapsed}, metadata}
    assert metadata.profile == :fast
    refute Map.has_key?(metadata, :cache_directory)
    refute Map.has_key?(metadata, :auth_token)
  end

  defp probe(snapshot), do: fn _descriptor, _opts -> snapshot end

  defp cache_opts(cache_dir) do
    [
      model_repository_opts: [cache_dir: cache_dir],
      tokenizer_repository_opts: [cache_dir: cache_dir]
    ]
  end

  defp collect_progress(events) do
    receive do
      {:progress, event} -> collect_progress([event | events])
    after
      20 -> Enum.reverse(events)
    end
  end
end
