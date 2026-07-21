defmodule Mix.Tasks.ObscuraDetectTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
    end)

    :ok
  end

  test "detect task emits value-safe JSON" do
    path = tmp_file!("detect", "Email ana@example.com")

    Mix.Task.rerun("obscura.detect", [path, "--format", "json"])

    assert_receive {:mix_shell, :info, [json]}
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["status"] == "ok"
    assert [%{"entity" => "email"} = result] = decoded["results"]
    refute Map.has_key?(result, "text")
  end

  test "detect task rejects removed remote flags" do
    path = tmp_file!("detect-remote", "Email ana@example.com")

    assert_raise Mix.Error, ~r/Invalid options/, fn ->
      Mix.Task.rerun("obscura.detect", [path, "--remote", "ollama"])
    end
  end

  defp tmp_file!(name, contents) do
    dir = Path.join(System.tmp_dir!(), "obscura_phase5_cli_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name <> ".txt")
    File.write!(path, contents)
    path
  end
end
