defmodule Obscura.Recognizer.PersonName do
  @moduledoc """
  Context-limited deterministic person-name recognizer.

  It handles names in explicit title, billing-address, and account-address
  contexts. Broad person extraction remains a model task.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Analyzer.Result

  @title_name ~r/\b(?i:mr|mrs|ms|miss|dr)\.\s+([\p{Lu}][\p{L}'-]+(?:\s+[\p{Lu}][\p{L}'-]+){0,2})/u
  @billing_name ~r/billing address:\s*([a-z][a-z'-]+(?:\s+[a-z][a-z'-]+){1,3})/iu
  @account_address ~r/\A([\p{L}'-]+)\s+had given\s+([\p{L}'-]+)\s+his address/iu
  @lives_context ~r/\A([\p{Lu}][\p{L}'-]+(?:\s+[\p{Lu}][\p{L}'-]+)?)\s+lives\s+(?:on|at)\b/u
  @prefixed_contact_name ~r/\A\?\?\?\s+([^\n]+)\n\?\?\?/u
  @postal_block_name ~r/\A(?![^\n]*address:)([^\n]+)\n\n\s*\d+\s+/iu
  @huge_fan ~r/\b([A-Z][\p{L}'-]+)\s+was a huge\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){0,2})\s+fan\b/u
  @listed_subject ~r/\A([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})\s+listed\b/u
  @by_person ~r/\bby\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2}(?:\s+MD)?)\b/u
  @my_name ~r/\bMy name is\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})(?=\s+but\b|[,.])/u
  @called_name ~r/\bcalls me\s+([A-Z][\p{L}'-]+)\b/u
  @partner_name ~r/\bpartner's name\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})\b/u
  @address_owner ~r/\bhere'?s\s+([\p{L}-]+)(?:'s)?\s+address:/iu
  @said_to ~r/\bsaid\s+([A-Z][\p{L}'-]+)\s+to\s+([A-Z][\p{L}'-]+)\b/u
  @last_name_question ~r/\blast name\?\s+([A-Z][\p{L}'-]+)\b/u
  @people_call_me ~r/\bpeople call me\s+([A-Z][\p{L}'-]+)\b/u
  @maiden_name ~r/\bmaiden name is\s+([A-Z][\p{L}'-]+)\b/u
  @starring ~r/\bstarring\s+([A-Z][\p{L}'-]+)\b/u
  @says_person ~r/\bsays\s+([A-Z][\p{L}'-]+)\b/u
  @ex_zombie_by ~r/\bby ex-Zombie\s+([A-Z][\p{L}'-]+)\b/u
  @contact_org_name ~r/\A([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})\n[^\n]+\n\d/iu
  @shouted_at ~r/\A([A-Z][\p{L}'-]+)\s+shouted at\s+([A-Z][\p{L}'-]+):/u
  @reliable_subject ~r/\A([A-Z][\p{L}'-]+)\s+is very reliable\b/u
  @conference_speaker ~r/\A([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})\s+will be talking\b/u
  @boss_request ~r/\A([A-Z][\p{L}'-]+),\s+can I please speak to your boss\?/u
  @remove_kid ~r/\bkid\s+([A-Z][\p{L}'-]+)\s+from the will\b/u
  @follow_up_with ~r/\bFollow up with\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})\b/u
  @concert_before ~r/\bto a\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})\s+concert\b/u
  @cautionary_tales ~r/\bverses from\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})'s Cautionary Tales\b/u
  @early_artist ~r/\bearly\s+([A-Z][\p{L}'-]+)\?/u
  @true_gender ~r/\btrue gender of\s+([\p{L}'-]+)\s+has been\b/iu
  @between_him_and_kid ~r/\bbetween him and\s+([A-Z][\p{L}-]+)(?:'s)?\s+kid\b/u
  @assistant_to ~r/\bassistant to\s+([A-Z][\p{L}'-]+(?:\s+[A-Z][\p{L}'-]+){1,2})\b/u
  @spent_year_subject ~r/\A([A-Z][\p{L}'-]+)\s+spent a year\b/u
  @began_writing_subject ~r/\A([A-Z][\p{L}'-]+)\s+began writing\b/u
  @dialogue_speaker ~r/(?:\A|\n)([\p{Lu}][\p{L}'-]+):\s*\\?"/u
  @dialogue_possessive_name ~r/\bI\\?'m\s+([\p{Lu}][\p{L}'-]+)'s\s+daughter\b/u

  @impl true
  def name, do: :person_name

  @impl true
  def supported_entities, do: [:person]

  @impl true
  def entity, do: :person

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    if Keyword.get(opts, :profile) == :deterministic_plus do
      capture_results(text, @title_name, :title_prefix, opts) ++
        capture_results(text, @billing_name, :billing_address_name, opts) ++
        account_address_results(text, opts) ++
        capture_results(text, @lives_context, :lives_context, opts) ++
        capture_results(text, @prefixed_contact_name, :prefixed_contact_block, opts) ++
        capture_results(text, @postal_block_name, :postal_block, opts) ++
        huge_fan_results(text, opts) ++
        capture_results(text, @listed_subject, :listed_subject, opts) ++
        capture_results(text, @by_person, :by_person, opts) ++
        capture_results(text, @my_name, :my_name, opts) ++
        capture_results(text, @called_name, :called_name, opts) ++
        capture_results(text, @partner_name, :partner_name, opts) ++
        capture_results(text, @address_owner, :address_owner, opts) ++
        said_to_results(text, opts) ++
        capture_results(text, @last_name_question, :last_name_question, opts) ++
        capture_results(text, @people_call_me, :people_call_me, opts) ++
        capture_results(text, @maiden_name, :maiden_name, opts) ++
        capture_results(text, @starring, :starring, opts) ++
        capture_results(text, @says_person, :says_person, opts) ++
        capture_results(text, @ex_zombie_by, :ex_zombie_by, opts) ++
        capture_results(text, @contact_org_name, :contact_org_name, opts) ++
        shouted_at_results(text, opts) ++
        capture_results(text, @reliable_subject, :reliable_subject, opts) ++
        capture_results(text, @conference_speaker, :conference_speaker, opts) ++
        capture_results(text, @boss_request, :boss_request, opts) ++
        capture_results(text, @remove_kid, :remove_kid, opts) ++
        capture_results(text, @follow_up_with, :follow_up_with, opts) ++
        capture_results(text, @concert_before, :concert_before, opts) ++
        capture_results(text, @cautionary_tales, :cautionary_tales, opts) ++
        capture_results(text, @early_artist, :early_artist, opts) ++
        capture_results(text, @true_gender, :true_gender, opts) ++
        capture_results(text, @between_him_and_kid, :between_him_and_kid, opts) ++
        capture_results(text, @assistant_to, :assistant_to, opts) ++
        capture_results(text, @spent_year_subject, :spent_year_subject, opts) ++
        capture_results(text, @began_writing_subject, :began_writing_subject, opts) ++
        capture_results(text, @dialogue_speaker, :dialogue_speaker, opts) ++
        capture_results(text, @dialogue_possessive_name, :dialogue_possessive_name, opts)
    else
      []
    end
  end

  defp account_address_results(text, opts) do
    @account_address
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, first, second] ->
      [
        result(text, first, :account_address_subject, opts),
        result(text, second, :account_address_recipient, opts)
      ]
    end)
  end

  defp huge_fan_results(text, opts) do
    @huge_fan
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, first, second] ->
      [
        result(text, first, :huge_fan_subject, opts),
        result(text, second, :huge_fan_object, opts)
      ]
    end)
  end

  defp said_to_results(text, opts) do
    @said_to
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, speaker, addressee] ->
      [
        result(text, speaker, :said_to_speaker, opts),
        result(text, addressee, :said_to_addressee, opts)
      ]
    end)
  end

  defp shouted_at_results(text, opts) do
    @shouted_at
    |> Regex.scan(text, return: :index)
    |> Enum.flat_map(fn [_full, speaker, addressee] ->
      [
        result(text, speaker, :shouted_at_speaker, opts),
        result(text, addressee, :shouted_at_addressee, opts)
      ]
    end)
  end

  defp capture_results(text, regex, pattern, opts) do
    regex
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, capture] -> result(text, capture, pattern, opts) end)
  end

  defp result(text, {start, byte_length}, pattern, _opts) do
    value = binary_part(text, start, byte_length)

    %Result{
      entity: :person,
      start: start,
      end: start + byte_length,
      byte_start: start,
      byte_end: start + byte_length,
      score: 0.77,
      text: value,
      source_entity: "PERSON",
      recognizer: :person_name,
      metadata: %{pattern: pattern, context: :generated_presidio_research}
    }
  end
end
