defmodule Obscura.Eval.Profile do
  @moduledoc """
  Profile support and unsupported-entity reporting for evaluation runs.
  """

  alias Obscura.Eval.EntityMapping
  alias Obscura.Profile, as: ProductProfile
  alias Obscura.Recognizer.PrivacyFilter.Native, as: PrivacyFilterNative

  @doc """
  Returns the supported entities for an evaluation profile.
  """
  @spec supported_entities(atom()) :: [atom()]
  def supported_entities(profile) when profile in [:fast, :balanced, :accurate, :openmed_pii] do
    {:ok, descriptor} = ProductProfile.fetch(profile)
    descriptor.supported_entities
  end

  def supported_entities(:regex_only), do: EntityMapping.phase_0_supported_entities()
  def supported_entities(:context), do: EntityMapping.phase_0_supported_entities()
  def supported_entities(:llm_safe), do: EntityMapping.phase_0_supported_entities()

  def supported_entities(:deterministic_plus),
    do: EntityMapping.deterministic_plus_supported_entities()

  def supported_entities(:nlp), do: EntityMapping.nlp_supported_entities()
  def supported_entities(:hybrid_ner), do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_balanced), do: EntityMapping.hybrid_ner_supported_entities()
  def supported_entities(:hybrid_ner_org), do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_org_high_recall),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_dbmdz_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_tner_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_tner_high_recall),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_tner_facebookai_org),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_tner_jean_location),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_tner_jean_location_gated),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_tner_jean_location_cascade),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_ner_bigmed_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:ner_ortex_openmed_superclinical_small),
    do: [
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

  def supported_entities(:hybrid_ner_ortex_openmed_superclinical_small),
    do: EntityMapping.hybrid_ner_ortex_openmed_superclinical_supported_entities()

  def supported_entities(:ner_ortex_piiranha_v1),
    do: EntityMapping.ner_ortex_piiranha_supported_entities()

  def supported_entities(:hybrid_ner_ortex_piiranha_v1),
    do: EntityMapping.hybrid_ner_ortex_piiranha_supported_entities()

  def supported_entities(:gliner_ortex), do: EntityMapping.hybrid_ner_supported_entities()

  def supported_entities(:hybrid_gliner_ortex),
    do: EntityMapping.hybrid_gliner_supported_entities()

  def supported_entities(:hybrid_gliner_urchade),
    do: EntityMapping.hybrid_gliner_supported_entities()

  def supported_entities(:hybrid_gliner_urchade_native),
    do: EntityMapping.hybrid_gliner_supported_entities()

  def supported_entities(:privacy_filter_native), do: PrivacyFilterNative.supported_entities()

  def supported_entities(:hybrid_privacy_filter_native),
    do:
      EntityMapping.deterministic_plus_supported_entities()
      |> Kernel.++(PrivacyFilterNative.supported_entities())
      |> Enum.uniq()
      |> Enum.sort()

  def supported_entities(:phi), do: EntityMapping.phi_supported_entities()
  def supported_entities(:real_ner), do: [:person, :organization, :location]
  def supported_entities(:real_pii), do: EntityMapping.phase_0_supported_entities()
  def supported_entities(_profile), do: []

  @doc """
  Parses an evaluation profile from a CLI string.
  """
  @spec from_string(String.t()) :: {:ok, atom()} | {:error, term()}
  def from_string("fast"), do: {:ok, :fast}
  def from_string("balanced"), do: {:ok, :balanced}
  def from_string("accurate"), do: {:ok, :accurate}
  def from_string("openmed_pii"), do: {:ok, :openmed_pii}
  def from_string("regex_only"), do: {:ok, :regex_only}
  def from_string("context"), do: {:ok, :context}
  def from_string("llm_safe"), do: {:ok, :llm_safe}
  def from_string("deterministic_plus"), do: {:ok, :deterministic_plus}
  def from_string("nlp"), do: {:ok, :nlp}
  def from_string("hybrid_ner"), do: {:ok, :hybrid_ner}
  def from_string("hybrid_ner_conservative"), do: {:ok, :hybrid_ner_conservative}
  def from_string("hybrid_ner_balanced"), do: {:ok, :hybrid_ner_balanced}
  def from_string("hybrid_ner_org"), do: {:ok, :hybrid_ner_org}
  def from_string("hybrid_ner_org_high_recall"), do: {:ok, :hybrid_ner_org_high_recall}
  def from_string("hybrid_ner_dbmdz_conservative"), do: {:ok, :hybrid_ner_dbmdz_conservative}
  def from_string("hybrid_ner_tner_conservative"), do: {:ok, :hybrid_ner_tner_conservative}
  def from_string("hybrid_ner_tner_high_recall"), do: {:ok, :hybrid_ner_tner_high_recall}

  def from_string("hybrid_ner_tner_facebookai_org"),
    do: {:ok, :hybrid_ner_tner_facebookai_org}

  def from_string("hybrid_ner_tner_jean_location"),
    do: {:ok, :hybrid_ner_tner_jean_location}

  def from_string("hybrid_ner_tner_jean_location_gated"),
    do: {:ok, :hybrid_ner_tner_jean_location_gated}

  def from_string("hybrid_ner_tner_jean_location_cascade"),
    do: {:ok, :hybrid_ner_tner_jean_location_cascade}

  def from_string("hybrid_ner_bigmed_conservative"), do: {:ok, :hybrid_ner_bigmed_conservative}

  def from_string("ner_ortex_openmed_superclinical_small"),
    do: {:ok, :ner_ortex_openmed_superclinical_small}

  def from_string("hybrid_ner_ortex_openmed_superclinical_small"),
    do: {:ok, :hybrid_ner_ortex_openmed_superclinical_small}

  def from_string("ner_ortex_piiranha_v1"), do: {:ok, :ner_ortex_piiranha_v1}

  def from_string("hybrid_ner_ortex_piiranha_v1"),
    do: {:ok, :hybrid_ner_ortex_piiranha_v1}

  def from_string("gliner_ortex"), do: {:ok, :gliner_ortex}
  def from_string("hybrid_gliner_ortex"), do: {:ok, :hybrid_gliner_ortex}
  def from_string("hybrid_gliner_urchade"), do: {:ok, :hybrid_gliner_urchade}
  def from_string("hybrid_gliner_urchade_native"), do: {:ok, :hybrid_gliner_urchade_native}
  def from_string("privacy_filter_native"), do: {:ok, :privacy_filter_native}
  def from_string("hybrid_privacy_filter_native"), do: {:ok, :hybrid_privacy_filter_native}
  def from_string("phi"), do: {:ok, :phi}
  def from_string("real_ner"), do: {:ok, :real_ner}
  def from_string("real_pii"), do: {:ok, :real_pii}
  def from_string(profile), do: {:error, {:unknown_profile, profile}}

  @doc """
  Splits spans into supported and unsupported groups for a profile.
  """
  @spec split_spans([map()], atom()) :: %{supported: [map()], unsupported: [map()]}
  def split_spans(spans, profile) when is_list(spans) do
    supported = supported_entities(profile)

    Enum.reduce(spans, %{supported: [], unsupported: []}, fn span, acc ->
      entity = Map.fetch!(span, :entity)

      if entity in supported do
        %{acc | supported: [span | acc.supported]}
      else
        %{acc | unsupported: [span | acc.unsupported]}
      end
    end)
    |> then(fn acc ->
      %{supported: Enum.reverse(acc.supported), unsupported: Enum.reverse(acc.unsupported)}
    end)
  end
end
