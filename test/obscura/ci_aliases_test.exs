defmodule Obscura.CIAliasesTest do
  use ExUnit.Case, async: true

  test "real-model smoke runs stable and experimental model aliases in isolated processes" do
    aliases = Obscura.MixProject.project() |> Keyword.fetch!(:aliases)
    commands = Keyword.fetch!(aliases, :"ci.real_model_smoke")

    assert [_, _, _] = commands
    assert Enum.all?(commands, &String.starts_with?(&1, "cmd mix obscura.eval "))

    for profile <- ~w(balanced accurate openmed_pii) do
      assert Enum.any?(commands, &String.contains?(&1, "--profile #{profile}"))
    end
  end

  test "unused dependency check fetches the conditional dependency union first" do
    aliases = Obscura.MixProject.project() |> Keyword.fetch!(:aliases)

    assert [fetch, check] = Keyword.fetch!(aliases, :"deps.check_unused")

    for command <- [fetch, check] do
      assert String.contains?(command, "MIX_ENV=test")
      assert String.contains?(command, "OBSCURA_REAL_MODEL=1")
      assert String.contains?(command, "OBSCURA_REAL_MODEL_BACKEND=emily")
      assert String.contains?(command, "OBSCURA_GLINER_ORTEX=1")
    end

    assert String.ends_with?(fetch, "mix deps.get --only test")
    assert String.ends_with?(check, "mix deps.unlock --check-unused")
  end
end
