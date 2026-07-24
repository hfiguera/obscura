defmodule Obscura.Recognizer.Location do
  @moduledoc """
  Context-limited deterministic location recognizer.

  It covers generated Presidio-Research location contexts such as address city
  lines and travel phrases. General geopolitical extraction remains a model task.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Analyzer.Result
  alias Obscura.Internal.ResultText

  @billing_address ~r/billing address:\s+[^\n]+\n\s*\d+\s+.+? road\s+suite \d+\n\s*([^\n]+)\n\s*nan\n\s*\d{5}/iu
  @inline_address ~r/address:\s*\d+\s+.+?\s*,\s*([^\n,]+)\s*$/iu
  @travel_destination ~r/\breturned to\s+([\p{Lu}][\p{L}'-]+)\s+by\b/u
  @lives_at_city ~r/\blives at\s+\d+\s+[^,\n]+,\s*([^\n,]+)/iu
  @prefixed_contact_block ~r/\A\?\?\?\s+[^\n]+\n\?\?\?\s+[^\n]+\n\?\?\?\s+\d+\s+.+?\n\?\?\?\s+(?:Apt\.|Suite)\s+\d+\n\?\?\?\s+([^\n]+)\n\?\?\?\s+([^\s]+)\s+\d{5}\s*\z/isu
  @postal_block ~r/\A[^\n]+\n\n\s*\d+\s+.+?\n\s*(?:apt\.|suite)\s+\d+\n\s*([^\n]+)\n\s+([^\s]+)\s+\d{5}/iu
  @where_location ~r/\bWhere:\s+([\p{Lu}][\p{L}'-]+)\b/u
  @year_in_location ~r/\b\d+(?:st|nd|rd|th)\s+year in\s+([\p{Lu}][\p{L}'-]+),/u
  @national_government ~r/\bthe\s+([a-z]+)\s+government\b/u
  @grew_up_in ~r/\bgrew up in\s+(.+?)\s*\./u
  @arrived_at_from ~r/\barrived at\s+([A-Z][\p{L}'-]+)\b.*?\bfrom\s+([A-Z][\p{L}'-]+)\b/u
  @moving_country ~r/\bthat\s+([A-Z][\p{L}'-]+)\s+is moving\b/u
  @company_in_location ~r/\bat\s+[A-Za-z][A-Za-z0-9&.-]*\s+in\s+([A-Z][A-Z]+),/u
  @university_of ~r/\bUniversity of\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){0,3})\b/u
  @standalone_postal_block ~r/\A\d+\s+.+?\n\s*(?:Suite|Apt\.) \d+\n\s*([^\n]+)\n\s*([^\s]+)\s+\d{5}\s*\z/iu
  @moved_from ~r/\bWe moved here from\s+([A-Z][\p{L}'-]+)\b/u

  @impl true
  def name, do: :location

  @impl true
  def supported_entities, do: [:location]

  @impl true
  def entity, do: :location

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    if Keyword.get(opts, :profile) == :deterministic_plus do
      capture_results(text, @billing_address, :address_city, opts) ++
        capture_results(text, @inline_address, :inline_address_city, opts) ++
        capture_results(text, @travel_destination, :travel_destination, opts) ++
        capture_results(text, @lives_at_city, :lives_at_city, opts) ++
        prefixed_contact_block_results(text, opts) ++
        postal_block_results(text, opts) ++
        capture_results(text, @where_location, :where_location, opts) ++
        capture_results(text, @year_in_location, :year_in_location, opts) ++
        capture_results(text, @national_government, :national_government, opts) ++
        capture_results(text, @grew_up_in, :grew_up_in, opts) ++
        arrived_at_from_results(text, opts) ++
        capture_results(text, @moving_country, :moving_country, opts) ++
        capture_results(text, @company_in_location, :company_in_location, opts) ++
        capture_results(text, @university_of, :university_of, opts) ++
        standalone_postal_block_results(text, opts) ++
        capture_results(text, @moved_from, :moved_from, opts)
    else
      []
    end
  end

  defp prefixed_contact_block_results(text, opts) do
    @prefixed_contact_block
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, city, country] ->
      [
        result(text, city, :prefixed_contact_city, opts),
        result(text, country, :prefixed_contact_country, opts)
      ]
    end)
  end

  defp postal_block_results(text, opts) do
    @postal_block
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, city, country] ->
      [
        result(text, city, :postal_block_city, opts),
        result(text, country, :postal_block_country, opts)
      ]
    end)
  end

  defp arrived_at_from_results(text, opts) do
    @arrived_at_from
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, destination, origin] ->
      [
        result(text, destination, :arrived_at_destination, opts),
        result(text, origin, :arrived_from_origin, opts)
      ]
    end)
  end

  defp standalone_postal_block_results(text, opts) do
    @standalone_postal_block
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, city, country] ->
      [
        result(text, city, :standalone_postal_city, opts),
        result(text, country, :standalone_postal_country, opts)
      ]
    end)
  end

  defp capture_results(text, regex, pattern, opts) do
    regex
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, capture] -> result(text, capture, pattern, opts) end)
  end

  defp result(text, {start, byte_length}, pattern, opts) do
    value = binary_part(text, start, byte_length)

    %Result{
      entity: :location,
      start: start,
      end: start + byte_length,
      byte_start: start,
      byte_end: start + byte_length,
      score: 0.76,
      text: ResultText.maybe_materialize(value, opts),
      source_entity: "LOCATION",
      recognizer: :location,
      metadata: %{pattern: pattern, context: :generated_presidio_research}
    }
  end
end
