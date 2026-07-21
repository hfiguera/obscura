defmodule Mix.Tasks.Obscura.Profile.PrepareTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Obscura.Profile.Prepare

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
end
