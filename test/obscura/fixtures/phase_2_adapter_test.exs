defmodule Obscura.Fixtures.Phase2AdapterTest do
  use ExUnit.Case, async: true

  alias Obscura.Fixtures.ContextAdapter
  alias Obscura.Fixtures.Loader
  alias Obscura.Fixtures.StructuredAdapter

  test "structured fixtures match expected data and items" do
    assert {:ok, fixtures} = Loader.load_all(suite: :structured)

    for fixture <- fixtures do
      assert {:ok, result} = StructuredAdapter.redact(fixture.input, fixture.opts)

      assert result.data == fixture.expected_data, fixture.id
      assert normalize_items(result.items) == normalize_items(fixture.expected_items), fixture.id
    end
  end

  test "context fixtures improve score and record context words" do
    assert {:ok, fixtures} = Loader.load_all(suite: :context)

    for fixture <- fixtures do
      assert {:ok, result} = ContextAdapter.run(fixture)

      assert result.with_context.score > result.without_context.score, fixture.id
      assert result.with_context.score <= 1.0

      recorded =
        result.with_context.explanation.context_words
        |> Enum.map(&String.downcase/1)

      assert Enum.all?(fixture.expected_context_words, &(String.downcase(&1) in recorded)),
             fixture.id
    end
  end

  defp normalize_items(items) do
    items
    |> Enum.map(fn item ->
      Map.take(item, [
        :path,
        :entity,
        :operator,
        :source_byte_start,
        :source_byte_end,
        :replacement,
        :metadata
      ])
    end)
    |> Enum.sort_by(&{&1.path, &1.entity, &1.source_byte_start, &1.source_byte_end})
  end
end
