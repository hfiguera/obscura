defmodule Obscura.Recognizer.NER.RoutingTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.OutputAwareCascade
  alias Obscura.Recognizer.NER.Routing
  alias Obscura.Recognizer.NER.Secondary

  test "person and organization requests need only the primary model" do
    assert Routing.tner_jean_serving_needs([:person, :organization]) == %{
             primary: true,
             location: false
           }

    assert [:default, {NER, [serving: :primary]}] =
             Routing.tner_jean_recognizers(
               [:person, :organization],
               [serving: :primary],
               serving: :location
             )
  end

  test "location-only requests need only the location model" do
    assert Routing.tner_jean_serving_needs([:location]) == %{
             primary: false,
             location: true
           }

    assert [:default, {Secondary, [serving: :location]}] =
             Routing.tner_jean_recognizers(
               [:location],
               [serving: :primary],
               serving: :location
             )
  end

  test "structured-only requests do not need model recognizers" do
    assert Routing.tner_jean_serving_needs([:email, :phone, :credit_card]) == %{
             primary: false,
             location: false
           }

    assert [:default] =
             Routing.tner_jean_recognizers(
               [:email, :phone, :credit_card],
               [serving: :primary],
               serving: :location
             )
  end

  test "full open-class requests include both model recognizers" do
    assert Routing.tner_jean_serving_needs([:person, :organization, :location]) == %{
             primary: true,
             location: true
           }

    assert [:default, {NER, [serving: :primary]}, {Secondary, [serving: :location]}] =
             Routing.tner_jean_recognizers(
               [:person, :organization, :location],
               [serving: :primary],
               serving: :location
             )
  end

  test "output-aware location routing keeps TNER primary and Jean secondary" do
    assert Routing.tner_jean_cascade_serving_needs([:location]) == %{
             primary: true,
             location: true
           }

    assert [:default, {OutputAwareCascade, cascade_opts}] =
             Routing.tner_jean_cascade_recognizers(
               [:location],
               [serving: :primary],
               [serving: :location],
               cascade_trigger: :missing
             )

    assert cascade_opts[:cascade_trigger] == :missing
    assert cascade_opts[:primary_opts][:serving] == :primary
    assert cascade_opts[:primary_opts][:entities] == [:location]
    assert cascade_opts[:secondary_opts][:serving] == :location
    assert cascade_opts[:secondary_opts][:entities] == [:location]
  end
end
