defmodule Mix.Tasks.ObscuraRedactTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
    end)

    :ok
  end

  test "redact task writes file and refuses overwrite without force" do
    dir = tmp_dir!("redact")
    input = Path.join(dir, "input.txt")
    out = Path.join(dir, "redacted.txt")
    File.write!(input, "Email ana@example.com")

    Mix.Task.rerun("obscura.redact", [input, "--out", out])

    assert File.read!(out) == "Email [EMAIL]"
    assert_receive {:mix_shell, :info, [_message]}

    assert_raise Mix.Error, fn ->
      Mix.Task.rerun("obscura.redact", [input, "--out", out])
    end
  end

  defp tmp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "obscura_phase5_cli_#{name}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
