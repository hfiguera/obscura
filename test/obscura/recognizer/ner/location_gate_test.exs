defmodule Obscura.Recognizer.NER.LocationGateTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.LocationGate

  test "runs for direct location context" do
    assert LocationGate.decide("Alice lives in Denver.").run?
    assert LocationGate.decide("Send it to 123 Main Street.").run?
    assert LocationGate.decide("The office is located near Paris.").run?
  end

  test "runs for comma-separated capitalized place-like phrases" do
    assert LocationGate.decide("The package moved through Boulder, Colorado yesterday.").run?
  end

  test "skips text without location signals" do
    refute LocationGate.decide("Alice emailed Bob about invoice INV-123.").run?
  end

  test "summarizes run and skip counts" do
    assert %{
             strategy: :location_context,
             total_samples: 3,
             run_count: 2,
             skip_count: 1,
             run_rate: run_rate,
             skip_rate: skip_rate
           } =
             LocationGate.summary([
               "Alice lives in Denver.",
               "Invoice only.",
               "The office is located near Paris."
             ])

    assert_in_delta run_rate, 2 / 3, 0.0001
    assert_in_delta skip_rate, 1 / 3, 0.0001
  end
end
