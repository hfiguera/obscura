defmodule Obscura.Fixtures.OperatorFixtureSchemaTest do
  use ExUnit.Case, async: true

  alias Obscura.Fixtures.Loader
  alias Obscura.Fixtures.Schema

  test "all operator fixtures satisfy the schema and have unique IDs" do
    assert {:ok, fixtures} = Loader.load_all(suite: :operator)
    assert fixtures != []

    ids = Enum.map(fixtures, & &1.id)
    assert ids == Enum.uniq(ids)

    assert Enum.all?(fixtures, fn schema_fixture_item ->
             assert {:ok, validated_fixture} = Schema.validate_operator(schema_fixture_item)
             validated_fixture == schema_fixture_item
           end)
  end

  test "required operator behaviors are represented" do
    assert {:ok, fixtures} = Loader.load_all(suite: :operator)
    tags = fixtures |> Enum.flat_map(& &1.tags) |> MapSet.new()

    for tag <- [
          :replace,
          :redact,
          :mask,
          :hash,
          :custom,
          :invalid_span,
          :overlap,
          :whitespace_merging,
          :unicode,
          :right_to_left,
          :conflict_policy
        ] do
      assert MapSet.member?(tags, tag)
    end

    assert Enum.any?(fixtures, &(:default_fallback in &1.tags))
    assert Enum.any?(fixtures, &(:entity_override in &1.tags))
  end
end
