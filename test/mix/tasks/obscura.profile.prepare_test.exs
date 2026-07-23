defmodule Mix.Tasks.Obscura.Profile.PrepareTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Obscura.Profile.Prepare

  setup_all do
    cache_dir =
      Path.join(
        System.tmp_dir!(),
        "obscura-profile-prepare-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(cache_dir)
    previous = System.get_env("BUMBLEBEE_CACHE_DIR")
    System.put_env("BUMBLEBEE_CACHE_DIR", cache_dir)

    on_exit(fn ->
      if previous do
        System.put_env("BUMBLEBEE_CACHE_DIR", previous)
      else
        System.delete_env("BUMBLEBEE_CACHE_DIR")
      end

      File.rm_rf!(cache_dir)
    end)

    :ok
  end

  test "renders human progress for dependency-light preparation" do
    Mix.Task.reenable("obscura.profile.prepare")

    output = capture_io(fn -> Prepare.run(["--profile", "fast"]) end)

    assert output =~ "profile=fast"
    assert output =~ "preparation_started"
    assert output =~ "status=ready runtime=reusable"
    assert output =~ "allow_download=false"
  end

  test "JSON mode emits machine-readable records without terminal bars" do
    Mix.Task.reenable("obscura.profile.prepare")

    output = capture_io(fn -> Prepare.run(["--profile", "fast", "--json"]) end)
    records = output |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert hd(records)["type"] == "setup"
    assert List.last(records)["type"] == "result"
    assert List.last(records)["status"] == "ok"
    assert Enum.any?(records, &(&1["event"] == "preparation_started"))
    refute output =~ "[="
  end

  test "human mode prints the TNER commercial restriction before preparation fails" do
    Mix.Task.reenable("obscura.profile.prepare")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, fn ->
          Prepare.run(["--profile", "balanced"])
        end
      end)

    assert output =~ "license_notice asset=tner_roberta_large_ontonotes5"
    assert output =~ "commercial_use=requires_ldc_for_profit_membership"
    assert output =~ "requires an LDC for-profit membership"
    assert position(output, "license_notice") < position(output, "preparation_started")
  end

  test "JSON mode exposes structured TNER licensing before preparation fails" do
    Mix.Task.reenable("obscura.profile.prepare")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, fn ->
          Prepare.run(["--profile", "accurate", "--json"])
        end
      end)

    records = output |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    notice = Enum.find(records, &(&1["event"] == "asset_license_notice"))

    assert notice["asset"] == "tner_roberta_large_ontonotes5"
    assert notice["commercial_use"] == "requires_ldc_for_profit_membership"
    assert notice["type"] == "progress"

    notice_index = Enum.find_index(records, &(&1["event"] == "asset_license_notice"))
    started_index = Enum.find_index(records, &(&1["event"] == "preparation_started"))
    assert notice_index < started_index
  end

  defp position(output, pattern), do: output |> :binary.match(pattern) |> elem(0)
end
