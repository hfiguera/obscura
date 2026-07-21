defmodule Obscura.Recognizer.GLiNER.OrtexTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Ortex

  test "returns clear missing Ortex dependency error" do
    assert {:error, {:missing_optional_dependency, :ortex}} =
             Ortex.build(dependency_checker: fn _module -> false end)
  end

  test "returns clear missing Tokenizers dependency error" do
    assert {:error, {:missing_optional_dependency, :tokenizers}} =
             Ortex.build(dependency_checker: fn module -> module == :"Elixir.Ortex" end)
  end
end
