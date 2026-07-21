defmodule Obscura.Eval.ProfileTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Profile

  test "stable product aliases expose their resolved entity surfaces" do
    assert Profile.supported_entities(:fast) == Profile.supported_entities(:deterministic_plus)

    assert Profile.supported_entities(:balanced) ==
             Profile.supported_entities(:hybrid_ner_tner_conservative)

    assert Profile.supported_entities(:accurate) ==
             Profile.supported_entities(:hybrid_ner_tner_jean_location)

    assert Profile.supported_entities(:openmed_pii) ==
             Profile.supported_entities(:privacy_filter_native)
  end

  test "regex_only profile includes Phase 0 supported entities" do
    assert Profile.supported_entities(:regex_only) == [
             :email,
             :phone,
             :credit_card,
             :iban,
             :us_ssn,
             :ip_address,
             :domain,
             :url
           ]
  end

  test "splits supported and unsupported spans" do
    spans = [
      %{entity: :email},
      %{entity: :person},
      %{entity: :credit_card},
      %{entity: :organization}
    ]

    assert %{supported: supported, unsupported: unsupported} =
             Profile.split_spans(spans, :regex_only)

    assert Enum.map(supported, & &1.entity) == [:email, :credit_card]
    assert Enum.map(unsupported, & &1.entity) == [:person, :organization]
  end

  test "deterministic_plus profile includes local person location and address recognizers" do
    assert :person in Profile.supported_entities(:deterministic_plus)
    assert :location in Profile.supported_entities(:deterministic_plus)
    assert :street_address in Profile.supported_entities(:deterministic_plus)
    refute :organization in Profile.supported_entities(:deterministic_plus)
  end

  test "hybrid org profile is an explicit real-model benchmark variant" do
    assert Profile.from_string("hybrid_ner_org") == {:ok, :hybrid_ner_org}
    assert Profile.supported_entities(:hybrid_ner_org) == Profile.supported_entities(:hybrid_ner)
    assert :organization in Profile.supported_entities(:hybrid_ner_org)
  end

  test "hybrid NER preset aliases use the same entity surface" do
    assert Profile.from_string("hybrid_ner_conservative") == {:ok, :hybrid_ner_conservative}
    assert Profile.from_string("hybrid_ner_balanced") == {:ok, :hybrid_ner_balanced}

    assert Profile.from_string("hybrid_ner_org_high_recall") ==
             {:ok, :hybrid_ner_org_high_recall}

    assert Profile.from_string("hybrid_ner_dbmdz_conservative") ==
             {:ok, :hybrid_ner_dbmdz_conservative}

    assert Profile.from_string("hybrid_ner_tner_conservative") ==
             {:ok, :hybrid_ner_tner_conservative}

    assert Profile.from_string("hybrid_ner_tner_high_recall") ==
             {:ok, :hybrid_ner_tner_high_recall}

    assert Profile.from_string("hybrid_ner_tner_facebookai_org") ==
             {:ok, :hybrid_ner_tner_facebookai_org}

    assert Profile.from_string("hybrid_ner_tner_jean_location") ==
             {:ok, :hybrid_ner_tner_jean_location}

    assert Profile.from_string("hybrid_ner_tner_jean_location_gated") ==
             {:ok, :hybrid_ner_tner_jean_location_gated}

    assert Profile.from_string("hybrid_ner_tner_jean_location_cascade") ==
             {:ok, :hybrid_ner_tner_jean_location_cascade}

    assert Profile.from_string("hybrid_ner_bigmed_conservative") ==
             {:ok, :hybrid_ner_bigmed_conservative}

    for profile <- [
          :hybrid_ner_conservative,
          :hybrid_ner_balanced,
          :hybrid_ner_org_high_recall,
          :hybrid_ner_dbmdz_conservative,
          :hybrid_ner_tner_conservative,
          :hybrid_ner_tner_high_recall,
          :hybrid_ner_tner_facebookai_org,
          :hybrid_ner_tner_jean_location,
          :hybrid_ner_tner_jean_location_gated,
          :hybrid_ner_bigmed_conservative
        ] do
      assert Profile.supported_entities(profile) == Profile.supported_entities(:hybrid_ner)
    end
  end

  test "hybrid GLiNER profile combines deterministic structured entities with open-class model entities" do
    assert Profile.from_string("hybrid_gliner_ortex") == {:ok, :hybrid_gliner_ortex}
    assert Profile.from_string("hybrid_gliner_urchade") == {:ok, :hybrid_gliner_urchade}

    assert Profile.from_string("hybrid_gliner_urchade_native") ==
             {:ok, :hybrid_gliner_urchade_native}

    assert Profile.supported_entities(:hybrid_gliner_ortex) == [
             :credit_card,
             :date_time,
             :domain,
             :email,
             :iban,
             :ip_address,
             :location,
             :organization,
             :person,
             :phone,
             :street_address,
             :url,
             :us_ssn
           ]

    assert Profile.supported_entities(:hybrid_gliner_urchade) ==
             Profile.supported_entities(:hybrid_gliner_ortex)

    assert Profile.supported_entities(:hybrid_gliner_urchade_native) ==
             Profile.supported_entities(:hybrid_gliner_ortex)
  end

  test "OpenMed SuperClinical Ortex profile is explicit and scoped to mapped PII labels" do
    assert Profile.from_string("ner_ortex_openmed_superclinical_small") ==
             {:ok, :ner_ortex_openmed_superclinical_small}

    assert Profile.supported_entities(:ner_ortex_openmed_superclinical_small) == [
             :credit_card,
             :date_time,
             :email,
             :ip_address,
             :location,
             :organization,
             :patient_id,
             :person,
             :phone,
             :url,
             :us_ssn
           ]
  end

  test "hybrid OpenMed SuperClinical Ortex profile combines structured deterministic and model entities" do
    assert Profile.from_string("hybrid_ner_ortex_openmed_superclinical_small") ==
             {:ok, :hybrid_ner_ortex_openmed_superclinical_small}

    assert Profile.supported_entities(:hybrid_ner_ortex_openmed_superclinical_small) == [
             :credit_card,
             :date_time,
             :domain,
             :email,
             :iban,
             :ip_address,
             :location,
             :organization,
             :patient_id,
             :person,
             :phone,
             :street_address,
             :url,
             :us_ssn
           ]
  end

  test "Piiranha Ortex profiles expose the checkpoint's actual PII taxonomy" do
    assert Profile.from_string("ner_ortex_piiranha_v1") == {:ok, :ner_ortex_piiranha_v1}

    assert Profile.from_string("hybrid_ner_ortex_piiranha_v1") ==
             {:ok, :hybrid_ner_ortex_piiranha_v1}

    model_entities = Profile.supported_entities(:ner_ortex_piiranha_v1)
    hybrid_entities = Profile.supported_entities(:hybrid_ner_ortex_piiranha_v1)

    assert :person in model_entities
    assert :location in model_entities
    assert :password in model_entities
    assert :username in model_entities
    refute :organization in model_entities

    assert :domain in hybrid_entities
    assert :iban in hybrid_entities
    refute :password in hybrid_entities
    refute :username in hybrid_entities
    refute :organization in hybrid_entities
  end

  test "privacy-filter profiles are explicit opt-in benchmark variants" do
    assert Profile.from_string("privacy_filter_native") == {:ok, :privacy_filter_native}

    assert Profile.from_string("hybrid_privacy_filter_native") ==
             {:ok, :hybrid_privacy_filter_native}

    assert :person in Profile.supported_entities(:privacy_filter_native)
    assert :email in Profile.supported_entities(:privacy_filter_native)
    assert :phone in Profile.supported_entities(:privacy_filter_native)

    assert :credit_card in Profile.supported_entities(:hybrid_privacy_filter_native)
    assert :person in Profile.supported_entities(:hybrid_privacy_filter_native)
  end

  test "removed remote profiles cannot be selected for evaluation" do
    for profile <- [
          "remote_google_dlp",
          "remote_azure_pii",
          "remote_azure_phi",
          "remote_ollama",
          "hybrid_remote"
        ] do
      assert Profile.from_string(profile) == {:error, {:unknown_profile, profile}}
    end
  end
end
