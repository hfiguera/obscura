defmodule Obscura.Fixtures.AnalyzerFixtureSchemaTest do
  use ExUnit.Case, async: true

  alias Obscura.Fixtures.Loader
  alias Obscura.Fixtures.Schema

  test "all analyzer fixtures satisfy the schema and have unique IDs" do
    assert {:ok, fixtures} = Loader.load_all(suite: :analyzer)
    assert fixtures != []

    ids = Enum.map(fixtures, & &1.id)
    assert ids == Enum.uniq(ids)

    assert Enum.all?(fixtures, fn schema_fixture_item ->
             assert {:ok, validated_fixture} = Schema.validate_analyzer(schema_fixture_item)
             validated_fixture == schema_fixture_item
           end)
  end

  test "presidio analyzer fixtures cover the required entity minimums" do
    assert {:ok, fixtures} = Loader.load_all(suite: :analyzer)

    counts =
      fixtures
      |> Enum.filter(&(:presidio in &1.tags))
      |> Enum.group_by(fn fixture -> fixture.entities |> List.first() end)
      |> Map.new(fn {entity, entity_fixtures} ->
        positives = Enum.count(entity_fixtures, & &1.should_match)
        negatives = Enum.count(entity_fixtures, &(not &1.should_match))
        {entity, {positives, negatives}}
      end)

    assert counts.email == {5, 3}
    assert counts.credit_card == {8, 5}
    assert counts.us_ssn == {6, 6}
    assert counts.phone == {6, 4}
    assert counts.ip_address == {6, 4}
    assert counts.iban == {5, 4}

    url_domain =
      fixtures
      |> Enum.filter(&(:presidio in &1.tags and :url_domain in &1.tags))
      |> then(fn url_fixtures ->
        {Enum.count(url_fixtures, & &1.should_match),
         Enum.count(url_fixtures, &(not &1.should_match))}
      end)

    assert url_domain == {6, 4}
  end

  test "obscura analyzer fixtures cover unicode, edge, and overlap cases" do
    assert {:ok, fixtures} = Loader.load_all(suite: :analyzer)
    obscura = Enum.filter(fixtures, &(:obscura in &1.tags))

    assert Enum.any?(obscura, &(:emoji in &1.tags))
    assert Enum.any?(obscura, &(:combining_mark in &1.tags))
    assert Enum.any?(obscura, &(:accented in &1.tags))
    assert Enum.any?(obscura, &(:byte_zero in &1.tags))
    assert Enum.any?(obscura, &(:end_of_text in &1.tags))
    assert Enum.any?(obscura, &(:overlap in &1.tags))
  end
end
