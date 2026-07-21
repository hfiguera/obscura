defmodule Obscura.Eval.Operational.Soak.SchemaTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.ReportPrivacy
  alias Obscura.Eval.Operational.Soak.Schema
  alias Obscura.Test.SoakReportFixture

  test "accepts a complete canonical fast soak and rejects sensitive report fields" do
    report = SoakReportFixture.valid_report()

    assert :ok = Schema.validate(report)

    assert {:error, {:sensitive_soak_report_key, "text"}} =
             report
             |> Map.put("debug", %{"text" => "private"})
             |> Schema.validate()
  end

  test "requires model allocator series and canonical durations" do
    openmed =
      SoakReportFixture.valid_report()
      |> Map.put("profile", "openmed_pii")
      |> put_in(["workload", "requested_duration_ms"], 1_800_000)
      |> put_in(["workload", "elapsed_ms"], 1_800_001)
      |> Map.put("environment", %{
        "requested_backend" => "emily",
        "requested_device" => "gpu",
        "emily_fallback" => "raise",
        "backend_proven" => true,
        "fallback_occurred" => false,
        "platform" => "apple_emily"
      })

    assert :ok = Schema.validate(openmed)

    assert {:error, :incomplete_soak_memory_analysis} =
             openmed
             |> put_in(
               ["memory_analysis", "metrics", "emily_active"],
               %{"status" => "unavailable"}
             )
             |> Schema.validate()

    assert {:error, :noncanonical_soak_run} =
             openmed
             |> put_in(["workload", "requested_duration_ms"], 1_799_999)
             |> Schema.validate()
  end

  test "asset metadata scrubbing removes checkpoint paths before validation" do
    evidence = %{
      models: %{
        report: %{
          checkpoint: ".cache/private-checkpoint",
          nested: [%{"path" => "/Users/developer/model", "revision" => "abc"}]
        }
      }
    }

    scrubbed = ReportPrivacy.drop_keys(evidence, ["checkpoint", "path"])

    refute inspect(scrubbed) =~ "private-checkpoint"
    refute inspect(scrubbed) =~ "/Users/"
    assert get_in(scrubbed, [:models, :report, :nested]) == [%{"revision" => "abc"}]
  end
end
