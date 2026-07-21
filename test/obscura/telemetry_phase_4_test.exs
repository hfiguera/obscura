defmodule Obscura.TelemetryPhase4Test do
  use ExUnit.Case, async: false

  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.FakeServing

  test "NER telemetry omits raw text and model outputs" do
    test_pid = self()
    handler_id = "obscura-phase-4-test-#{System.unique_integer([:positive])}"
    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok =
      :telemetry.attach(
        handler_id,
        [:obscura, :recognizer, :ner, :analyze, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    serving = FakeServing.new(%{"Alice" => [%{label: "PER", start: 0, end: 5, score: 0.9}]})

    assert {:ok, [_result]} =
             Obscura.analyze("Alice",
               entities: [:person],
               recognizers: [{NER, serving: serving}]
             )

    assert_receive {:telemetry, [:obscura, :recognizer, :ner, :analyze, :stop], _measurements,
                    metadata}

    refute Map.has_key?(metadata, :text)
    refute Map.has_key?(metadata, :value)
    refute Map.has_key?(metadata, :model_outputs)
    assert metadata.status == :ok
    assert metadata.backend == :fake
  end
end
