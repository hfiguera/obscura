defmodule Mix.Tasks.ObscuraGenConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
    end)

    :ok
  end

  test "gen config task writes local profile config without overwrite by default" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "obscura_phase5_config_#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    path = Path.join(dir, "runtime.exs")
    File.rm_rf!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
    end)

    Mix.Task.rerun("obscura.gen.config", ["--write", path])

    config = File.read!(path)
    assert config =~ "default_profile: :fast"
    assert config =~ "balanced:"
    refute config =~ "GOOGLE_ACCESS_TOKEN"
    refute config =~ "AZURE_AI_LANGUAGE_KEY"
    assert_receive {:mix_shell, :info, [_message]}

    assert_raise Mix.Error, fn ->
      Mix.Task.rerun("obscura.gen.config", ["--write", path])
    end
  end
end
