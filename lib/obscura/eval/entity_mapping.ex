defmodule Obscura.Eval.EntityMapping do
  @moduledoc """
  Maps entity names between Presidio, Presidio-Research, and Obscura.
  """

  @type source ::
          :presidio
          | :presidio_research
          | :obscura
          | :nemotron_pii
  @type status ::
          :phase_0_supported
          | :phase_4_supported
          | :phase_0_unsupported
          | :future
  @type row :: %{
          source: source(),
          source_entity: String.t() | atom(),
          obscura_entity: atom(),
          status: status(),
          profile: atom() | nil,
          notes: String.t() | nil
        }

  @phase_0_supported [
    {"EMAIL_ADDRESS", :email},
    {"PHONE_NUMBER", :phone},
    {"CREDIT_CARD", :credit_card},
    {"IBAN_CODE", :iban},
    {"US_SSN", :us_ssn},
    {"IP_ADDRESS", :ip_address},
    {"DOMAIN_NAME", :domain},
    {"URL", :url}
  ]

  @phase_0_unsupported [
    {"STREET_ADDRESS", :street_address, "Unsupported until the structured/context phase."},
    {"ADDRESS", :street_address, "Generated Presidio-Research address field."}
  ]

  @phase_4_supported [
    {"PERSON", :person},
    {"ORGANIZATION", :organization},
    {"GPE", :location},
    {"LOCATION", :location},
    {"DATE_TIME", :date_time},
    {"NRP", :nationality}
  ]

  @future [
    {"TITLE", :title},
    {"AGE", :age},
    {"ZIP_CODE", :zip_code},
    {"US_DRIVER_LICENSE", :us_driver_license}
  ]

  @nemotron_pii [
    {"account_number", :id, "Generic financial account identifier."},
    {"age", :age, "Future recognizer."},
    {"api_key", :api_key, "Future credential recognizer."},
    {"bank_routing_number", :id, "Generic banking identifier."},
    {"biometric_identifier", :biometric_identifier, "Future biometric recognizer."},
    {"blood_type", :blood_type, "Future clinical recognizer."},
    {"certificate_license_number", :id, "Generic license identifier."},
    {"city", :location, nil},
    {"company_name", :organization, nil},
    {"coordinate", :location, "Geographic coordinate."},
    {"country", :location, nil},
    {"county", :location, nil},
    {"credit_debit_card", :credit_card, nil},
    {"customer_id", :id, "Generic customer identifier."},
    {"cvv", :credit_card, "Credit-card verification value."},
    {"date", :date_time, nil},
    {"date_of_birth", :date_time, nil},
    {"date_time", :date_time, nil},
    {"device_identifier", :device_identifier, "Future device identifier recognizer."},
    {"education_level", :education_level, "Sensitive demographic attribute."},
    {"email", :email, nil},
    {"employee_id", :id, "Generic employee identifier."},
    {"employment_status", :employment_status, "Sensitive employment attribute."},
    {"fax_number", :phone, "Fax numbers are phone-like contact identifiers."},
    {"first_name", :person, nil},
    {"gender", :gender, "Sensitive demographic attribute."},
    {"health_plan_beneficiary_number", :patient_id, "PHI beneficiary identifier."},
    {"http_cookie", :secret, "Future credential/session recognizer."},
    {"ipv4", :ip_address, nil},
    {"ipv6", :ip_address, nil},
    {"language", :language, "Sensitive demographic attribute."},
    {"last_name", :person, nil},
    {"license_plate", :vehicle_identifier, "Future vehicle identifier recognizer."},
    {"mac_address", :mac_address, "Future network hardware identifier recognizer."},
    {"medical_record_number", :patient_id, "PHI medical record identifier."},
    {"national_id", :id, "Generic government identifier."},
    {"occupation", :occupation, "Sensitive demographic attribute."},
    {"password", :password, "Future credential recognizer."},
    {"phone_number", :phone, nil},
    {"pin", :password, "Future credential recognizer."},
    {"political_view", :political_view, "Sensitive demographic attribute."},
    {"postcode", :zip_code, nil},
    {"race_ethnicity", :race_ethnicity, "Sensitive demographic attribute."},
    {"religious_belief", :religious_belief, "Sensitive demographic attribute."},
    {"sexuality", :sexuality, "Sensitive demographic attribute."},
    {"ssn", :us_ssn, nil},
    {"state", :location, nil},
    {"street_address", :street_address, nil},
    {"swift_bic", :iban, "Banking code; mapped to the closest existing banking entity."},
    {"tax_id", :id, "Generic tax identifier."},
    {"time", :date_time, nil},
    {"unique_id", :id, "Generic unique identifier."},
    {"url", :url, nil},
    {"user_name", :username, "Future username recognizer."},
    {"vehicle_identifier", :vehicle_identifier, "Future vehicle identifier recognizer."}
  ]

  @doc """
  Returns the Phase 0 taxonomy mapping rows.
  """
  @spec rows() :: [row()]
  def rows do
    supported_rows() ++
      phase_4_rows() ++
      nemotron_rows() ++
      unsupported_rows() ++
      future_rows() ++
      obscura_rows()
  end

  @doc """
  Converts an external entity name into an Obscura entity atom.
  """
  @spec to_obscura(String.t() | atom()) ::
          {:ok, atom()} | {:error, {:unsupported_entity, String.t() | atom()}}
  def to_obscura(entity) when is_atom(entity), do: {:ok, entity}

  def to_obscura(entity) when is_binary(entity) do
    rows()
    |> Enum.find(&(&1.source_entity == entity))
    |> case do
      %{obscura_entity: obscura_entity} -> {:ok, obscura_entity}
      nil -> {:error, {:unsupported_entity, entity}}
    end
  end

  @doc """
  Returns all source entity names covered by the mapping.
  """
  @spec source_entities() :: [String.t() | atom()]
  def source_entities, do: Enum.map(rows(), & &1.source_entity)

  @doc """
  Returns the Phase 0 supported Obscura entities.
  """
  @spec phase_0_supported_entities() :: [atom()]
  def phase_0_supported_entities do
    Enum.map(@phase_0_supported, fn {_source, obscura} -> obscura end)
  end

  @doc """
  Returns Phase 4 NLP supported entities.
  """
  @spec nlp_supported_entities() :: [atom()]
  def nlp_supported_entities do
    (phase_0_supported_entities() ++
       Enum.map(@phase_4_supported, fn {_source, obscura} -> obscura end))
    |> Enum.uniq()
  end

  @doc """
  Returns hybrid deterministic plus real local NER entities.
  """
  @spec hybrid_ner_supported_entities() :: [atom()]
  def hybrid_ner_supported_entities do
    (phase_0_supported_entities() ++ [:person, :location, :organization])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns hybrid deterministic plus GLiNER Ortex entities.

  Structured PII remains deterministic/parser-backed. GLiNER contributes only
  open-class person, location, and organization spans.
  """
  @spec hybrid_gliner_supported_entities() :: [atom()]
  def hybrid_gliner_supported_entities do
    (phase_0_supported_entities() ++
       [:date_time, :street_address, :person, :location, :organization])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns hybrid deterministic plus OpenMed SuperClinical Ortex entities.

  Structured PII remains deterministic/parser-backed. The Ortex model
  contributes broader OpenMed-style PII/PHI labels such as person,
  organization, location, date/time, and patient identifiers.
  """
  @spec hybrid_ner_ortex_openmed_superclinical_supported_entities() :: [atom()]
  def hybrid_ner_ortex_openmed_superclinical_supported_entities do
    (phase_0_supported_entities() ++
       [:date_time, :location, :organization, :patient_id, :person, :street_address])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns entities emitted by the experimental Piiranha Ortex profile.
  """
  @spec ner_ortex_piiranha_supported_entities() :: [atom()]
  def ner_ortex_piiranha_supported_entities do
    [
      :credit_card,
      :date_time,
      :email,
      :id,
      :location,
      :password,
      :person,
      :phone,
      :street_address,
      :us_driver_license,
      :us_ssn,
      :username,
      :zip_code
    ]
  end

  @doc """
  Returns deterministic-plus entities combined with Piiranha model entities.
  """
  @spec hybrid_ner_ortex_piiranha_supported_entities() :: [atom()]
  def hybrid_ner_ortex_piiranha_supported_entities do
    deterministic_plus_supported_entities()
  end

  @doc """
  Returns deterministic-plus entities used for local accuracy improvement.
  """
  @spec deterministic_plus_supported_entities() :: [atom()]
  def deterministic_plus_supported_entities do
    (phase_0_supported_entities() ++ [:date_time, :location, :person, :street_address, :title])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns Phase 4 PHI profile entities.
  """
  @spec phi_supported_entities() :: [atom()]
  def phi_supported_entities do
    nlp_supported_entities() ++ [:medical_condition, :medication, :patient_id, :provider]
  end

  @doc """
  Returns true when the entity is supported by the given profile.
  """
  @spec supported?(atom(), atom()) :: boolean()
  def supported?(entity, :regex_only), do: entity in phase_0_supported_entities()
  def supported?(entity, :context), do: supported?(entity, :regex_only)
  def supported?(entity, :llm_safe), do: supported?(entity, :regex_only)

  def supported?(entity, :deterministic_plus),
    do: entity in deterministic_plus_supported_entities()

  def supported?(entity, :nlp), do: entity in nlp_supported_entities()
  def supported?(entity, :hybrid_ner), do: entity in hybrid_ner_supported_entities()
  def supported?(entity, :hybrid_ner_org), do: entity in hybrid_ner_supported_entities()

  def supported?(entity, :hybrid_ner_tner_facebookai_org),
    do: entity in hybrid_ner_supported_entities()

  def supported?(entity, :hybrid_ner_tner_jean_location),
    do: entity in hybrid_ner_supported_entities()

  def supported?(entity, :hybrid_ner_tner_jean_location_gated),
    do: entity in hybrid_ner_supported_entities()

  def supported?(entity, :hybrid_ner_tner_jean_location_cascade),
    do: entity in hybrid_ner_supported_entities()

  def supported?(entity, :hybrid_gliner_ortex), do: entity in hybrid_gliner_supported_entities()

  def supported?(entity, :hybrid_gliner_urchade),
    do: entity in hybrid_gliner_supported_entities()

  def supported?(entity, :hybrid_gliner_urchade_native),
    do: entity in hybrid_gliner_supported_entities()

  def supported?(entity, :ner_ortex_piiranha_v1),
    do: entity in ner_ortex_piiranha_supported_entities()

  def supported?(entity, :hybrid_ner_ortex_piiranha_v1),
    do: entity in hybrid_ner_ortex_piiranha_supported_entities()

  def supported?(entity, :phi), do: entity in phi_supported_entities()
  def supported?(_entity, _profile), do: false

  defp supported_rows do
    Enum.map(@phase_0_supported, fn {source_entity, obscura_entity} ->
      row(:presidio_research, source_entity, obscura_entity, :phase_0_supported, :regex_only, nil)
    end)
  end

  defp phase_4_rows do
    Enum.map(@phase_4_supported, fn {source_entity, obscura_entity} ->
      row(:presidio_research, source_entity, obscura_entity, :phase_4_supported, :nlp, nil)
    end)
  end

  defp unsupported_rows do
    Enum.map(@phase_0_unsupported, fn {source_entity, obscura_entity, notes} ->
      row(:presidio_research, source_entity, obscura_entity, :phase_0_unsupported, nil, notes)
    end)
  end

  defp future_rows do
    Enum.map(@future, fn {source_entity, obscura_entity} ->
      row(:presidio_research, source_entity, obscura_entity, :future, nil, "Future recognizer.")
    end)
  end

  defp nemotron_rows do
    Enum.map(@nemotron_pii, fn {source_entity, obscura_entity, notes} ->
      row(:nemotron_pii, source_entity, obscura_entity, :future, nil, notes)
    end)
  end

  defp obscura_rows do
    (phase_0_supported_entities() ++
       Enum.map(@phase_4_supported, fn {_source, obscura} -> obscura end))
    |> Enum.uniq()
    |> Enum.map(fn entity ->
      profile = if entity in phase_0_supported_entities(), do: :regex_only, else: :nlp

      status =
        if entity in phase_0_supported_entities(),
          do: :phase_0_supported,
          else: :phase_4_supported

      row(:obscura, entity, entity, status, profile, nil)
    end)
  end

  defp row(source, source_entity, obscura_entity, status, profile, notes) do
    %{
      source: source,
      source_entity: source_entity,
      obscura_entity: obscura_entity,
      status: status,
      profile: profile,
      notes: notes
    }
  end
end
