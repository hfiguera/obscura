defmodule Mix.Tasks.Obscura.Profile.CheckTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Obscura.Profile.Check

  test "renders successful human preflight" do
    Mix.Task.reenable("obscura.profile.check")

    output = capture_io(fn -> Check.run(["--profile", "fast"]) end)

    assert output =~ "profile=fast stability=stable status=ready"
    assert output =~ "implementation=deterministic_plus"
  end

  test "accepts preparation safety options only when preparation is explicit" do
    Mix.Task.reenable("obscura.profile.check")

    output =
      capture_io(fn ->
        Check.run([
          "--profile",
          "fast",
          "--prepare",
          "--allow-download",
          "--offline",
          "--timeout",
          "1000",
          "--inactivity-timeout",
          "500"
        ])
      end)

    assert output =~ "profile=fast stability=stable status=ready"
  end

  test "renders JSON and exits non-zero for an unavailable profile" do
    Mix.Task.reenable("obscura.profile.check")

    assert_raise Mix.Error, ~r/unknown_profile/, fn ->
      capture_io(fn ->
        Check.run(["--profile", "missing", "--json"])
      end)
    end
  end

  test "human output discloses the TNER commercial-use restriction" do
    Mix.Task.reenable("obscura.profile.check")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, fn ->
          Check.run(["--profile", "balanced"])
        end
      end)

    assert output =~ "Commercial use of tner/roberta-large-ontonotes5"
    assert output =~ "requires an LDC for-profit membership"
  end

  test "JSON output includes machine-readable TNER commercial-use metadata" do
    Mix.Task.reenable("obscura.profile.check")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, fn ->
          Check.run(["--profile", "accurate", "--json"])
        end
      end)

    report = Jason.decode!(output)

    assert Enum.any?(report["requirements"]["asset_licensing"], fn asset ->
             asset["id"] == "tner_roberta_large_ontonotes5" and
               asset["commercial_use"] == "requires_ldc_for_profit_membership"
           end)

    assert Enum.any?(report["warnings"], &String.contains?(&1, "LDC for-profit membership"))
  end
end
