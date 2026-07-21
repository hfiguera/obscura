defmodule Obscura.Recognizer.NER.Routing do
  @moduledoc """
  Entity-aware routing helpers for multi-model NER profiles.

  These helpers keep full-profile behavior unchanged while allowing scoped
  entity requests to avoid model recognizers that cannot contribute useful
  results.
  """

  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.OutputAwareCascade
  alias Obscura.Recognizer.NER.Secondary, as: SecondaryNER

  @primary_entities [:person, :organization]
  @location_entities [:location]

  @doc """
  Returns true when the primary TNER person/organization model is needed.
  """
  @spec primary_needed?([atom()]) :: boolean()
  def primary_needed?(entities) when is_list(entities) do
    Enum.any?(entities, &(&1 in @primary_entities))
  end

  @doc """
  Returns true when the location-specialist model is needed.
  """
  @spec location_needed?([atom()]) :: boolean()
  def location_needed?(entities) when is_list(entities) do
    Enum.any?(entities, &(&1 in @location_entities))
  end

  @doc """
  Builds recognizers for the TNER plus Jean-Baptiste location hybrid profile.
  """
  @spec tner_jean_recognizers([atom()], keyword() | nil, keyword() | nil) :: [
          atom() | {module(), keyword()}
        ]
  def tner_jean_recognizers(entities, primary_opts, location_opts) when is_list(entities) do
    [:default]
    |> maybe_add_primary(entities, primary_opts)
    |> maybe_add_location(entities, location_opts)
  end

  @doc """
  Returns serving needs for the TNER plus Jean-Baptiste profile.
  """
  @spec tner_jean_serving_needs([atom()]) :: %{primary: boolean(), location: boolean()}
  def tner_jean_serving_needs(entities) when is_list(entities) do
    %{
      primary: primary_needed?(entities),
      location: location_needed?(entities)
    }
  end

  @doc """
  Builds recognizers for the output-aware TNER and Jean-Baptiste cascade.

  Location requests require both models because TNER remains the primary
  location recognizer and Jean-Baptiste is only a conditional recovery path.
  """
  @spec tner_jean_cascade_recognizers([atom()], keyword() | nil, keyword() | nil, keyword()) ::
          [atom() | {module(), keyword()}]
  def tner_jean_cascade_recognizers(entities, primary_opts, secondary_opts, cascade_opts)
      when is_list(entities) and is_list(cascade_opts) do
    model_entities = Enum.filter(entities, &(&1 in (@primary_entities ++ @location_entities)))

    cond do
      model_entities == [] ->
        [:default]

      :location in model_entities and is_list(primary_opts) and is_list(secondary_opts) ->
        [
          :default,
          {OutputAwareCascade,
           cascade_opts
           |> Keyword.put(:primary_opts, Keyword.put(primary_opts, :entities, model_entities))
           |> Keyword.put(:secondary_opts, Keyword.put(secondary_opts, :entities, [:location]))}
        ]

      is_list(primary_opts) ->
        [:default, {NER, Keyword.put(primary_opts, :entities, model_entities)}]

      true ->
        [:default]
    end
  end

  @doc """
  Returns serving needs for the output-aware cascade.
  """
  @spec tner_jean_cascade_serving_needs([atom()]) :: %{primary: boolean(), location: boolean()}
  def tner_jean_cascade_serving_needs(entities) when is_list(entities) do
    location? = location_needed?(entities)

    %{
      primary: primary_needed?(entities) or location?,
      location: location?
    }
  end

  defp maybe_add_primary(recognizers, entities, primary_opts) do
    if primary_needed?(entities) and is_list(primary_opts) do
      recognizers ++ [{NER, primary_opts}]
    else
      recognizers
    end
  end

  defp maybe_add_location(recognizers, entities, location_opts) do
    if location_needed?(entities) and is_list(location_opts) do
      recognizers ++ [{SecondaryNER, location_opts}]
    else
      recognizers
    end
  end
end
