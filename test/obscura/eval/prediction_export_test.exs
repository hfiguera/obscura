defmodule Obscura.Eval.PredictionExportTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.PredictionExport

  test "exports Presidio-compatible JSONL without raw text or detected values" do
    assert {:ok, export} = PredictionExport.run(profile: :regex_only, limit: 1, telemetry: false)

    assert export.sample_count == 1
    assert [line] = export.lines
    assert {:ok, decoded} = Jason.decode(line)

    refute Map.has_key?(decoded, "text")
    assert is_list(decoded["predictions"])

    for prediction <- decoded["predictions"] do
      assert Map.has_key?(prediction, "entity_type")
      assert Map.has_key?(prediction, "start_position")
      assert Map.has_key?(prediction, "end_position")
      refute Map.has_key?(prediction, "text")
      refute Map.has_key?(prediction, "value")
    end
  end
end
