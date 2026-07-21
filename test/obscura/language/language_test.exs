defmodule Obscura.LanguageTest do
  use ExUnit.Case, async: true

  test "normalizes supported language tags without dynamic atoms" do
    assert Obscura.Language.normalize(:en) == {:ok, :en}
    assert Obscura.Language.normalize("es") == {:ok, :es}
    assert {:error, :unsupported_language} = Obscura.Language.normalize("zz")
  end
end
