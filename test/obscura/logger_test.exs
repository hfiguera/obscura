defmodule Obscura.LoggerTest do
  use ExUnit.Case, async: true

  test "redacts metadata and safe inspect output" do
    metadata = [user: "jane@example.com", password: "secret"]

    assert {:ok, redacted} = Obscura.Logger.redact_metadata(metadata, entities: [:email])
    assert redacted[:user] == "[EMAIL]"
    assert redacted[:password] == "[REDACTED]"

    assert {:ok, inspected} = Obscura.Logger.safe_inspect(metadata, entities: [:email])
    refute inspected =~ "jane@example.com"
    refute inspected =~ "secret"
  end
end
