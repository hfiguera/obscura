defmodule Obscura.Profile.PreparerTest do
  use ExUnit.Case, async: false

  alias Obscura.Diagnostic
  alias Obscura.Profile.Preparer
  alias Obscura.Recognizer.NER.FakeServing

  test "supervised preparer exposes readiness and retains the runtime" do
    start_supervised!({Preparer, profile: :fast, name: Preparer})
    assert {:ok, runtime} = Preparer.await(Preparer)
    assert runtime.profile == :fast
    assert %{status: :ready, diagnostic: nil} = Preparer.status(Preparer)
    assert {:ok, ^runtime} = Preparer.runtime(Preparer)
  end

  test "subscribers receive progress and ready notification" do
    builder = fn _opts ->
      Process.sleep(100)
      {:ok, FakeServing.new([])}
    end

    pid =
      start_supervised!(
        {Preparer,
         id: :progress_preparer,
         profile: :balanced,
         prepare_options: [
           allow_download: true,
           cache_probe: fn _descriptor, _opts ->
             %{status: :missing, bytes: 0, repositories: []}
           end,
           dependency_checker: fn _dependency -> true end,
           ner_serving_builder: builder
         ]}
      )

    assert :ok = Preparer.subscribe(pid)
    assert {:ok, _runtime} = Preparer.await(pid)
    assert_receive {:obscura_profile_preparation, ^pid, %{event: _event}}
    assert_receive {:obscura_profile_ready, ^pid}
  end

  test "failure remains queryable without crashing the supervised process" do
    pid =
      start_supervised!(
        {Preparer,
         id: :failed_preparer,
         profile: :balanced,
         prepare_options: [
           cache_probe: fn _descriptor, _opts ->
             %{status: :missing, bytes: 0, repositories: []}
           end,
           dependency_checker: fn _dependency -> true end
         ]}
      )

    assert {:error, %Diagnostic{code: :model_download_not_allowed}} = Preparer.await(pid)

    assert %{status: :failed, diagnostic: %{code: :model_download_not_allowed}} =
             Preparer.status(pid)

    assert Process.alive?(pid)
  end

  test "await timeout does not stop preparation" do
    pid =
      start_supervised!(
        {Preparer,
         id: :slow_preparer,
         profile: :balanced,
         prepare_options: [
           allow_download: true,
           cache_probe: fn _descriptor, _opts ->
             %{status: :missing, bytes: 0, repositories: []}
           end,
           dependency_checker: fn _dependency -> true end,
           ner_serving_builder: fn _opts ->
             Process.sleep(80)
             {:ok, FakeServing.new([])}
           end
         ]}
      )

    assert {:error, %Diagnostic{code: :preparation_timeout}} = Preparer.await(pid, 5)
    assert {:ok, _runtime} = Preparer.await(pid, 500)
  end
end
