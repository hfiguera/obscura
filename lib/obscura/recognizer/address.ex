defmodule Obscura.Recognizer.Address do
  @moduledoc """
  Context-limited address recognizer for generated Presidio-Research address blocks.

  This recognizer intentionally handles only address-like spans found in explicit
  address contexts. It is a deterministic bridge, not a general postal parser.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Analyzer.Result
  alias Obscura.Internal.ResultText

  @billing_address ~r/billing address:\s+[^\n]+\n\s*(\d+)\s+(.+? road)\s+(suite \d+)\n\s*([^\n]+)\n\s*(nan)\n\s*(\d{5})/iu
  @billing_address_with ~r/billing address with\s+(.+?)\s+for this card:/isu
  @inline_address ~r/address:\s*(\d+)\s+(.+?)\s*,\s*([^\n,]+)\s*$/iu
  @lives_on_street ~r/\blives on\s+(.+?)\s+street\b/iu
  @lives_at_address ~r/\blives at\s+(\d+)\s+([^,\n]+),\s*([^\n,]+)/iu
  @zip_context ~r/\bZIP:\s*(\d{5})\b/u
  @labeled_address ~r/(?:^|\n)\s*(?:address|shipping address|billing address|mailing address):\s*((?:\d+\s+[^\n,]+?\b(?:street|st|road|rd|avenue|ave|lane|ln|drive|dr|boulevard|blvd|way|court|ct)\b[^\n]*)(?:\n\s*(?:apt\.?|suite|ste)\s*[^\n]+)?(?:\n\s*[^\n,]+,\s*[A-Z]{2}\s+\d{5})?)/iu
  @contact_card_address ~r/(?:^|\n)\s*(?:name|full name):\s*[^\n]+\n\s*(?:email|phone|mobile|tel):\s*[^\n]+\n\s*address:\s*((?:\d+\s+[^\n,]+?\b(?:street|st|road|rd|avenue|ave|lane|ln|drive|dr|boulevard|blvd|way|court|ct)\b[^\n]*)(?:\n\s*(?:apt\.?|suite|ste)\s*[^\n]+)?(?:\n\s*[^\n,]+,\s*[A-Z]{2}\s+\d{5})?)/iu
  @prefixed_contact_block ~r/\A\?\?\?\s+[^\n]+\n\?\?\?\s+[^\n]+\n\?\?\?\s+(\d+)\s+(.+?)\n\?\?\?\s+((?:Apt\.|Suite)\s+\d+)\n\?\?\?\s+[^\n]+\n\?\?\?\s+[^\s]+\s+(\d{5})\s*\z/isu
  @postal_block ~r/\A[^\n]+\n\n\s*(\d+)\s+(.+?)\n\s*((?:apt\.|suite)\s+\d+)\n\s*[^\n]+\n\s+[^\s]+\s+(\d{5})/iu
  @two_addresses ~r/\baddresses,\s+here they are:\s*(.+?),\s+and\s+(.+)\z/isu
  @promised_address ~r/\bhere'?s\s+[\p{L}'-]+(?:'s)?\s+address:\s*\n+\s*(.+)\z/isu
  @please_return ~r/\bplease return to\s+(.+?)\s+in case of an issue\./isu
  @bus_station_on ~r/\bbus station is on\s+(.+?)\z/iu
  @lived_addresses ~r/\bI once lived in\s+(.+?)\.\s+I now live in\s+(.+)\z/isu
  @address_question ~r/\bWhat is your address\?\s*it is\s+(.+)\z/iu
  @restaurant_at ~r/\bThe restaurant is at\s+(\d+)\s+(.+)\z/iu
  @restaurant_located_at ~r/\bThe restaurant is located at\s+(.+?)\.\s+It serves\b/isu
  @standalone_postal_block ~r/\A(\d+)\s+(.+?)\n\s*((?:Suite|Apt\.) \d+)\n\s*[^\n]+\n\s*[^\s]+\s+(\d{5})\s*\z/iu
  @change_address_to ~r/\baddress to\s+(.+?)\s+for post mail\?/iu
  @contact_org_block ~r/\A[^\n]+\n[^\n]+\n(.+?)(?=\n(?:Mobile:|Desk:|Fax:|\d|\+))/isu

  @impl true
  def name, do: :address

  @impl true
  def supported_entities, do: [:street_address]

  @impl true
  def entity, do: :street_address

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    if Keyword.get(opts, :profile) in [
         :deterministic_plus,
         :hybrid_gliner_ortex,
         :hybrid_gliner_urchade,
         :hybrid_gliner_urchade_native
       ] do
      do_analyze(text, opts)
    else
      []
    end
  end

  defp do_analyze(text, opts) do
    billing_spans(text, opts) ++
      billing_address_with_spans(text, opts) ++
      inline_spans(text, opts) ++
      lives_on_street_spans(text, opts) ++
      lives_at_address_spans(text, opts) ++
      zip_context_spans(text, opts) ++
      labeled_address_spans(text, opts) ++
      contact_card_address_spans(text, opts) ++
      prefixed_contact_block_spans(text, opts) ++
      postal_block_spans(text, opts) ++
      two_address_spans(text, opts) ++
      capture_spans(text, @promised_address, :promised_address, opts) ++
      capture_spans(text, @please_return, :please_return, opts) ++
      capture_spans(text, @bus_station_on, :bus_station_on, opts) ++
      lived_address_spans(text, opts) ++
      capture_spans(text, @address_question, :address_question, opts) ++
      restaurant_at_spans(text, opts) ++
      capture_spans(text, @restaurant_located_at, :restaurant_located_at, opts) ++
      standalone_postal_block_spans(text, opts) ++
      capture_spans(text, @change_address_to, :change_address_to, opts) ++
      capture_spans(text, @contact_org_block, :contact_org_block, opts)
  end

  defp billing_spans(text, opts) do
    @billing_address
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, building, street, suite, _city, state, postal] ->
      [building, street, suite, state, postal]
      |> Enum.map(&result(text, &1, :address_block, opts))
    end)
  end

  defp billing_address_with_spans(text, opts) do
    @billing_address_with
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, address] -> result(text, address, :billing_address_with, opts) end)
  end

  defp inline_spans(text, opts) do
    @inline_address
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, building, street, _city] ->
      [result(text, building, :inline_address, opts), result(text, street, :inline_address, opts)]
    end)
  end

  defp lives_on_street_spans(text, opts) do
    @lives_on_street
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, street] -> result(text, street, :lives_on_street, opts) end)
  end

  defp lives_at_address_spans(text, opts) do
    @lives_at_address
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, building, street, _city] ->
      [
        result(text, building, :lives_at_address, opts),
        result(text, street, :lives_at_address, opts)
      ]
    end)
  end

  defp zip_context_spans(text, opts) do
    @zip_context
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, postal] -> result(text, postal, :zip_context, opts) end)
  end

  defp labeled_address_spans(text, opts) do
    @labeled_address
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, address] -> result(text, address, :labeled_address, opts) end)
  end

  defp contact_card_address_spans(text, opts) do
    @contact_card_address
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, address] -> result(text, address, :contact_card_address, opts) end)
  end

  defp prefixed_contact_block_spans(text, opts) do
    @prefixed_contact_block
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, building, street, apartment, postal] ->
      [building, street, apartment, postal]
      |> Enum.map(&result(text, &1, :prefixed_contact_block, opts))
    end)
  end

  defp postal_block_spans(text, opts) do
    @postal_block
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, building, street, apartment, postal] ->
      [building, street, apartment, postal]
      |> Enum.map(&result(text, &1, :postal_block, opts))
    end)
  end

  defp two_address_spans(text, opts) do
    @two_addresses
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, first, second] ->
      [
        result(text, first, :two_addresses, opts),
        result(text, second, :two_addresses, opts)
      ]
    end)
  end

  defp lived_address_spans(text, opts) do
    @lived_addresses
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, previous, current] ->
      [
        result(text, previous, :lived_addresses, opts),
        result(text, current, :lived_addresses, opts)
      ]
    end)
  end

  defp restaurant_at_spans(text, opts) do
    @restaurant_at
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, building, street] ->
      [
        result(text, building, :restaurant_at, opts),
        result(text, street, :restaurant_at, opts)
      ]
    end)
  end

  defp standalone_postal_block_spans(text, opts) do
    @standalone_postal_block
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, building, street, suite, postal] ->
      [building, street, suite, postal]
      |> Enum.map(&result(text, &1, :standalone_postal_block, opts))
    end)
  end

  defp capture_spans(text, regex, pattern, opts) do
    regex
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, capture] -> result(text, capture, pattern, opts) end)
  end

  defp result(text, {start, byte_length}, pattern, opts) do
    %Result{
      entity: :street_address,
      start: start,
      end: start + byte_length,
      byte_start: start,
      byte_end: start + byte_length,
      score: 0.78,
      text: ResultText.maybe_materialize_slice(text, start, start + byte_length, opts),
      source_entity: "ADDRESS",
      recognizer: :address,
      metadata: %{pattern: pattern, context: :address}
    }
  end
end
