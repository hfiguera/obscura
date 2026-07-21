defmodule Obscura.Recognizer.USSSN do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern

  @regex ~r/(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)/

  @impl true
  def name, do: :us_ssn

  @impl true
  def supported_entities, do: [:us_ssn]

  @impl true
  def entity, do: :us_ssn

  @impl true
  def analyze(text, opts) do
    Pattern.scan(text, @regex,
      entity: :us_ssn,
      source_entity: "US_SSN",
      recognizer: :us_ssn,
      pattern: :us_ssn,
      score: 0.85,
      explain: Keyword.get(opts, :explain, false),
      validate: &validate/1
    )
  end

  defp validate(<<area::binary-size(3), "-", group::binary-size(2), "-", serial::binary-size(4)>>) do
    area_number = String.to_integer(area)

    cond do
      area in ["000", "666"] or area_number >= 900 ->
        {:error, :invalid_area}

      group == "00" ->
        {:error, :invalid_group}

      serial == "0000" ->
        {:error, :invalid_serial}

      true ->
        {:ok, %{country: :us, context_words: ["ssn", "social security", "tax id"]}}
    end
  end
end
