defmodule Obscura.Recognizer.GLiNER.NativeTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Native

  test "rejects models outside the pinned native contract before checking optional dependencies" do
    assert {:error, {:native_gliner_not_supported, :other}} = Native.build(model: :other)
  end

  test "rejects malformed shape buckets before checking optional dependencies" do
    assert {:error, {:invalid_gliner_native_shape_buckets, [{64, 32}, {48, 24}]}} =
             Native.build(shape_buckets: [{64, 32}, {48, 24}])
  end

  test "reports a missing optional dependency without loading assets" do
    assert {:error, {:missing_optional_dependency, :nx}} =
             Native.build(dependency_checker: fn _module -> false end)
  end
end
