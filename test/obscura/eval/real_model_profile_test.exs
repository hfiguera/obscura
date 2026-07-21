defmodule Obscura.Eval.RealModelProfileTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Profile
  alias Obscura.Eval.RealModelSmoke

  test "real model profiles are explicit and do not change nlp defaults" do
    assert Profile.from_string("real_ner") == {:ok, :real_ner}
    assert Profile.supported_entities(:real_ner) == [:person, :organization, :location]
    assert :date_time in Profile.supported_entities(:nlp)
  end

  test "skipped smoke reports are value-free when real model cannot build" do
    assert :ok =
             RealModelSmoke.write_smoke_report(
               model: :dslim_bert_base_ner,
               dependency_checker: fn _module -> false end,
               telemetry: false
             )

    assert {:ok, report} =
             "eval/reports/phase_4_5_dslim_bert_base_ner_smoke.json"
             |> File.read!()
             |> Jason.decode()

    assert report["dataset"]["status"] == "skipped"
    assert report["model"]["model_alias"] == "dslim_bert_base_ner"
    refute inspect(report) =~ "Rachel Green"
    refute inspect(report) =~ "Ralph Lauren"
    refute inspect(report) =~ "New York City"
  end
end
