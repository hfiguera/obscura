defmodule Mix.Tasks.Obscura.Efficient.InstallTest do
  use ExUnit.Case, async: false
  alias Mix.Tasks.Obscura.Efficient.Install

  setup do
    dir = Path.join(System.tmp_dir!(), "efficient-install-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "requires explicit network authorization and removes failed staging", %{dir: dir} do
    assert_raise Mix.Error, ~r/allow-download/, fn -> Install.run(["--destination", dir]) end
    refute File.exists?(dir)
    assert Path.wildcard(dir <> ".staging-*") == []
  end

  test "does not overwrite an existing directory that fails verification", %{dir: dir} do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "keep"), "existing installation")
    assert_raise Mix.Error, ~r/verification failed/, fn -> Install.run(["--destination", dir]) end
    assert File.read!(Path.join(dir, "keep")) == "existing installation"
  end

  test "rejects a local executable before running it when its hash differs", %{dir: dir} do
    fake = dir <> "-fake"
    on_exit(fn -> File.rm(fake) end)
    File.write!(fake, "#!/bin/sh\ntouch #{dir}-executed\n")
    File.chmod!(fake, 0o755)

    assert_raise Mix.Error, ~r/Checksum verification failed/, fn ->
      Install.run(["--destination", dir, "--native-binary", fake])
    end

    refute File.exists?(dir <> "-executed")
    refute File.exists?(dir)
  end
end
