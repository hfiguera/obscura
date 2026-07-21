defmodule Obscura.Fixtures.Phase1AdapterTest do
  use ExUnit.Case, async: true

  alias Obscura.Fixtures.Loader
  alias Obscura.Fixtures.ObscuraAnalyzerAdapter
  alias Obscura.Fixtures.ObscuraOperatorAdapter

  test "real analyzer adapter exactly matches Phase 1 analyzer fixtures" do
    assert {:ok, fixtures} = Loader.load_all(suite: :analyzer)

    for fixture <- fixtures do
      assert {:ok, predicted} =
               ObscuraAnalyzerAdapter.analyze(fixture.text,
                 entities: fixture.entities,
                 profile: fixture.profile
               )

      assert normalize_spans(predicted) == normalize_spans(fixture.expected), fixture.id
    end
  end

  test "real operator adapter exactly matches Phase 1 operator fixtures" do
    assert {:ok, fixtures} = Loader.load_all(suite: :operator)

    for fixture <- fixtures do
      assert {:ok, result} =
               ObscuraOperatorAdapter.anonymize(
                 fixture.text,
                 fixture.spans,
                 fixture.operators,
                 []
               )

      assert result.text == fixture.expected_text, fixture.id
      assert normalize_items(result.items) == normalize_items(fixture.expected_items), fixture.id
    end
  end

  defp normalize_spans(spans) do
    Enum.map(spans, fn span ->
      Map.take(span, [:entity, :byte_start, :byte_end, :char_start, :char_end, :value])
    end)
  end

  defp normalize_items(items) do
    Enum.map(items, fn item ->
      Map.take(item, [
        :entity,
        :operator,
        :source_byte_start,
        :source_byte_end,
        :replacement_byte_start,
        :replacement_byte_end,
        :replacement,
        :metadata
      ])
    end)
  end
end
