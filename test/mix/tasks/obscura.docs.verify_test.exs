defmodule Mix.Tasks.Obscura.Docs.VerifyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Obscura.Docs.Verify

  setup do
    root = Path.join(System.tmp_dir!(), "obscura-doc-links-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Mix.Task.reenable("obscura.docs.verify")
    {:ok, root: root}
  end

  test "accepts existing relative links and ignores fenced or external links", %{root: root} do
    target = Path.join(root, "target.md")
    source = Path.join(root, "source.md")
    File.write!(target, "# Target\n")

    File.write!(source, """
    [target](target.md#section)
    [external](https://example.com/missing)

    ```markdown
    [example](missing.md)
    ```
    """)

    output = capture_io(fn -> Verify.run([source]) end)
    assert output =~ "Verified local Markdown links in 1 files."
  end

  test "rejects missing and absolute local targets", %{root: root} do
    source = Path.join(root, "source.md")
    File.write!(source, "[missing](missing.md)\n[local](/Users/example/private.md)\n")

    assert_raise Mix.Error, ~r/Markdown link verification failed with 2 error/, fn ->
      capture_io(:stderr, fn -> Verify.run([source]) end)
    end
  end
end
