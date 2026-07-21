defmodule Obscura.CLITest do
  use ExUnit.Case, async: true

  alias Obscura.CLI

  test "detect output is value-safe by default" do
    assert {:ok, output} =
             CLI.detect("Email ana@example.com", profile: :regex_only, telemetry: false)

    assert [%{entity: "email"} = result] = output.results
    refute Map.has_key?(result, :text)
    assert output.status == "ok"
  end

  test "detect output can include text only when explicit" do
    assert {:ok, output} =
             CLI.detect("Email ana@example.com",
               profile: :regex_only,
               include_text: true,
               telemetry: false
             )

    assert [%{text: "ana@example.com"}] = output.results
  end

  test "redact returns redacted text without exposing source values in item metadata" do
    assert {:ok, output} =
             CLI.redact("Email ana@example.com", profile: :regex_only, telemetry: false)

    assert output.text == "Email [EMAIL]"
    assert [%{entity: "email", replacement: "[EMAIL]"}] = output.items
  end

  test "generated config recommends stable local profiles" do
    config = CLI.config_example()

    assert config =~ "default_profile: :fast"
    assert config =~ "balanced:"
    refute config =~ "Remote"
  end
end
