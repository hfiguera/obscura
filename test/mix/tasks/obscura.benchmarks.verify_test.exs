defmodule Mix.Tasks.Obscura.Benchmarks.VerifyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Obscura.Benchmarks.Verify

  setup do
    Mix.Task.reenable("obscura.benchmarks.verify")
    :ok
  end

  test "verifies the committed authoritative manifest" do
    output = capture_io(fn -> Verify.run([]) end)

    assert output =~ "Authoritative benchmark manifest verified."
  end

  test "fails non-zero semantics for an invalid manifest" do
    path =
      Path.join(System.tmp_dir!(), "obscura-invalid-manifest-#{System.unique_integer()}.json")

    File.write!(path, Jason.encode!(%{"schema_version" => 1, "reports" => [%{}]}))
    on_exit(fn -> File.rm(path) end)

    assert_raise Mix.Error, ~r/Authoritative benchmark verification failed/, fn ->
      Verify.run(["--manifest", path])
    end
  end
end
