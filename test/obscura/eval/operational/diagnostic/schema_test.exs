defmodule Obscura.Eval.Operational.Diagnostic.SchemaTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Diagnostic.Schema
  alias Obscura.Test.DiagnosticReportFixture

  test "accepts complete canonical diagnostics and rejects controls or sensitive values" do
    report = DiagnosticReportFixture.valid_report()
    assert :ok = Schema.validate(report)

    assert {:error, :invalid_diagnostic_report_schema} =
             report
             |> put_in(["experiment", "kind"], "control")
             |> Schema.validate()

    assert {:error, {:sensitive_diagnostic_report_key, "text"}} =
             report
             |> Map.put("debug", %{"text" => "private"})
             |> Schema.validate()
  end

  test "requires clean GPU evidence and complete stage distributions" do
    report = DiagnosticReportFixture.valid_report()

    assert {:error, :diagnostic_gpu_backend_not_proven} =
             report
             |> put_in(["environment", "fallback_occurred"], true)
             |> Schema.validate()

    assert {:error, :incomplete_stage_diagnostics} =
             report
             |> update_in(["stage_diagnostics", "stages"], &Map.delete(&1, "model_serving"))
             |> Schema.validate()
  end
end
