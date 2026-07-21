defmodule Obscura.Recognizer.NER.Policy do
  @moduledoc false

  @ontonotes_context_words_by_label %{
    "ORG" => ["company", "employer", "organization", "works at", "work at", "affiliated with"],
    "LOC" => ["address", "city", "country", "geography", "located", "location", "region", "state"],
    "GPE" => ["address", "city", "country", "headquartered", "located", "office", "state"],
    "FAC" => ["airport", "building", "campus", "facility", "headquarters", "hospital", "office"]
  }

  @bigmed_conservative_thresholds %{
    person: 0.9,
    organization: 0.98,
    location: 0.95,
    email: 0.9,
    phone: 0.9,
    credit_card: 0.95,
    us_ssn: 0.95,
    ip_address: 0.95,
    url: 0.95,
    date_time: 0.98,
    patient_id: 0.98
  }

  @spec ontonotes_context_words_by_label() :: %{String.t() => [String.t()]}
  def ontonotes_context_words_by_label, do: @ontonotes_context_words_by_label

  @spec bigmed_conservative_thresholds() :: %{atom() => float()}
  def bigmed_conservative_thresholds, do: @bigmed_conservative_thresholds
end
