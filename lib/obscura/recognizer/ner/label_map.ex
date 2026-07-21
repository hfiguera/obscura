defmodule Obscura.Recognizer.NER.LabelMap do
  @moduledoc """
  Safe mapping from model labels to Obscura entity atoms.
  """

  @default %{
    person: ["PER", "PERSON", "B-PER", "I-PER"],
    organization: ["ORG", "ORGANIZATION", "B-ORG", "I-ORG"],
    location: ["LOC", "LOCATION", "GPE", "B-LOC", "I-LOC"],
    date_time: ["DATE", "TIME", "DATE_TIME"],
    nationality: ["NORP", "NRP", "NATIONALITY"]
  }

  @phi %{
    medical_condition: ["CONDITION", "MEDICAL_CONDITION", "DIAGNOSIS"],
    medication: ["MEDICATION", "DRUG"],
    patient_id: ["PATIENT_ID"],
    provider: ["PROVIDER", "DOCTOR", "CLINICIAN"]
  }

  @ab_ai_person_labels for label <- ["FIRSTNAME", "MIDDLENAME", "LASTNAME", "PREFIX"],
                           prefix <- ["", "B-", "I-"],
                           do: "#{prefix}#{label}"
  @ab_ai_organization_labels for label <- ["COMPANYNAME"],
                                 prefix <- ["", "B-", "I-"],
                                 do: "#{prefix}#{label}"
  @ab_ai_location_labels for label <- [
                               "BUILDINGNUMBER",
                               "STREET",
                               "SECONDARYADDRESS",
                               "STATE",
                               "CITY",
                               "COUNTY",
                               "ZIPCODE"
                             ],
                             prefix <- ["", "B-", "I-"],
                             do: "#{prefix}#{label}"
  @ab_ai_email_labels for label <- ["EMAIL"], prefix <- ["", "B-", "I-"], do: "#{prefix}#{label}"
  @ab_ai_phone_labels for label <- ["PHONENUMBER"],
                          prefix <- ["", "B-", "I-"],
                          do: "#{prefix}#{label}"
  @ab_ai_credit_card_labels for label <- [
                                  "CREDITCARDNUMBER",
                                  "CREDITCARDCVV",
                                  "CREDITCARDISSUER"
                                ],
                                prefix <- ["", "B-", "I-"],
                                do: "#{prefix}#{label}"
  @ab_ai_us_ssn_labels for label <- ["SSN"], prefix <- ["", "B-", "I-"], do: "#{prefix}#{label}"
  @ab_ai_iban_labels for label <- ["IBAN"], prefix <- ["", "B-", "I-"], do: "#{prefix}#{label}"
  @ab_ai_url_labels for label <- ["URL"], prefix <- ["", "B-", "I-"], do: "#{prefix}#{label}"
  @ab_ai_date_time_labels for label <- ["DATE", "DOB"],
                              prefix <- ["", "B-", "I-"],
                              do: "#{prefix}#{label}"
  @isotonic_person_labels for label <- ["FIRSTNAME", "MIDDLENAME", "LASTNAME"],
                              prefix <- ["", "B-", "I-"],
                              do: "#{prefix}#{label}"
  @isotonic_organization_labels for label <- ["COMPANYNAME"],
                                    prefix <- ["", "B-", "I-"],
                                    do: "#{prefix}#{label}"
  @isotonic_location_labels for label <- [
                                  "BUILDINGNUMBER",
                                  "STREET",
                                  "SECONDARYADDRESS",
                                  "STATE",
                                  "CITY",
                                  "COUNTY",
                                  "ZIPCODE"
                                ],
                                prefix <- ["", "B-", "I-"],
                                do: "#{prefix}#{label}"
  @ar86bat_person_labels for label <- ["GIVENNAME", "SURNAME"],
                             prefix <- ["", "B-", "I-"],
                             do: "#{prefix}#{label}"
  @ar86bat_location_labels for label <- ["BUILDINGNUM", "CITY", "STREET", "ZIPCODE"],
                               prefix <- ["", "B-", "I-"],
                               do: "#{prefix}#{label}"
  @ar86bat_email_labels for label <- ["EMAIL"],
                            prefix <- ["", "B-", "I-"],
                            do: "#{prefix}#{label}"
  @ar86bat_phone_labels for label <- ["TELEPHONENUM"],
                            prefix <- ["", "B-", "I-"],
                            do: "#{prefix}#{label}"
  @ar86bat_credit_card_labels for label <- ["CREDITCARDNUMBER"],
                                  prefix <- ["", "B-", "I-"],
                                  do: "#{prefix}#{label}"
  @ar86bat_us_ssn_labels for label <- ["SOCIALNUM"],
                             prefix <- ["", "B-", "I-"],
                             do: "#{prefix}#{label}"
  @ar86bat_date_time_labels for label <- ["DATE", "TIME"],
                                prefix <- ["", "B-", "I-"],
                                do: "#{prefix}#{label}"
  @piiranha_prefixes ["", "B-", "I-"]
  @piiranha_labels for label <- [
                         "ACCOUNTNUM",
                         "BUILDINGNUM",
                         "CITY",
                         "CREDITCARDNUMBER",
                         "DATEOFBIRTH",
                         "DRIVERLICENSENUM",
                         "EMAIL",
                         "GIVENNAME",
                         "IDCARDNUM",
                         "PASSWORD",
                         "SOCIALNUM",
                         "STREET",
                         "SURNAME",
                         "TAXNUM",
                         "TELEPHONENUM",
                         "USERNAME",
                         "ZIPCODE"
                       ],
                       prefix <- @piiranha_prefixes,
                       do: "#{prefix}#{label}"
  @bilou_prefixes ["", "B-", "I-", "L-", "U-"]
  @obi_person_labels for label <- ["PATIENT", "STAFF", "HCW"],
                         prefix <- @bilou_prefixes,
                         do: "#{prefix}#{label}"
  @obi_organization_labels for label <- ["PATORG", "VENDOR"],
                               prefix <- @bilou_prefixes,
                               do: "#{prefix}#{label}"
  @obi_location_labels for label <- ["LOC", "HOSP", "HOSPITAL", "FACILITY"],
                           prefix <- @bilou_prefixes,
                           do: "#{prefix}#{label}"
  @obi_email_labels for label <- ["EMAIL"], prefix <- @bilou_prefixes, do: "#{prefix}#{label}"
  @obi_phone_labels for label <- ["PHONE"], prefix <- @bilou_prefixes, do: "#{prefix}#{label}"
  @obi_date_time_labels for label <- ["DATE", "TIME"],
                            prefix <- @bilou_prefixes,
                            do: "#{prefix}#{label}"
  @bioes_prefixes ["", "B-", "I-", "E-", "S-"]
  @privacy_filter_person_labels for label <- ["private_person"],
                                    prefix <- @bioes_prefixes,
                                    do: "#{prefix}#{label}"
  @privacy_filter_location_labels for label <- ["private_address"],
                                      prefix <- @bioes_prefixes,
                                      do: "#{prefix}#{label}"
  @privacy_filter_email_labels for label <- ["private_email"],
                                   prefix <- @bioes_prefixes,
                                   do: "#{prefix}#{label}"
  @privacy_filter_phone_labels for label <- ["private_phone"],
                                   prefix <- @bioes_prefixes,
                                   do: "#{prefix}#{label}"
  @privacy_filter_url_labels for label <- ["private_url"],
                                 prefix <- @bioes_prefixes,
                                 do: "#{prefix}#{label}"
  @privacy_filter_date_time_labels for label <- ["private_date"],
                                       prefix <- @bioes_prefixes,
                                       do: "#{prefix}#{label}"
  @openmed_person_labels for label <- ["first_name", "last_name"],
                             prefix <- @bioes_prefixes,
                             do: "#{prefix}#{label}"
  @openmed_organization_labels for label <- ["company_name"],
                                   prefix <- @bioes_prefixes,
                                   do: "#{prefix}#{label}"
  @openmed_location_labels for label <- [
                                 "city",
                                 "coordinate",
                                 "country",
                                 "county",
                                 "postcode",
                                 "state",
                                 "street_address",
                                 "private_address"
                               ],
                               prefix <- @bioes_prefixes,
                               do: "#{prefix}#{label}"
  @openmed_email_labels for label <- ["email", "private_email"],
                            prefix <- @bioes_prefixes,
                            do: "#{prefix}#{label}"
  @openmed_phone_labels for label <- ["phone_number", "fax_number", "private_phone"],
                            prefix <- @bioes_prefixes,
                            do: "#{prefix}#{label}"
  @openmed_credit_card_labels for label <- ["credit_debit_card", "cvv"],
                                  prefix <- @bioes_prefixes,
                                  do: "#{prefix}#{label}"
  @openmed_us_ssn_labels for label <- ["ssn"], prefix <- @bioes_prefixes, do: "#{prefix}#{label}"
  @openmed_ip_address_labels for label <- ["ipv4", "ipv6"],
                                 prefix <- @bioes_prefixes,
                                 do: "#{prefix}#{label}"
  @openmed_url_labels for label <- ["url", "private_url"],
                          prefix <- @bioes_prefixes,
                          do: "#{prefix}#{label}"
  @openmed_date_time_labels for label <- [
                                  "date",
                                  "date_of_birth",
                                  "date_time",
                                  "time",
                                  "private_date"
                                ],
                                prefix <- @bioes_prefixes,
                                do: "#{prefix}#{label}"
  @openmed_patient_id_labels for label <- [
                                   "medical_record_number",
                                   "health_plan_beneficiary_number"
                                 ],
                                 prefix <- @bioes_prefixes,
                                 do: "#{prefix}#{label}"
  @openmed_label_map %{
    person: @openmed_person_labels,
    organization: @openmed_organization_labels,
    location: @openmed_location_labels,
    email: @openmed_email_labels,
    phone: @openmed_phone_labels,
    credit_card: @openmed_credit_card_labels,
    us_ssn: @openmed_us_ssn_labels,
    ip_address: @openmed_ip_address_labels,
    url: @openmed_url_labels,
    date_time: @openmed_date_time_labels,
    patient_id: @openmed_patient_id_labels
  }

  @model_maps %{
    dslim_bert_base_ner: %{
      person: ["PER", "B-PER", "I-PER"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["LOC", "B-LOC", "I-LOC"]
    },
    dslim_bert_large_ner: %{
      person: ["PER", "B-PER", "I-PER"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["LOC", "B-LOC", "I-LOC"]
    },
    stanford_deidentifier_base: %{
      person: ["PER", "PERSON", "B-PER", "I-PER", "PATIENT", "STAFF", "HCW"],
      organization: ["ORG", "ORGANIZATION", "B-ORG", "I-ORG", "HOSP", "PATORG", "VENDOR"],
      location: ["LOC", "LOCATION", "B-LOC", "I-LOC", "GPE", "FACILITY", "HOSPITAL"],
      email: ["EMAIL", "B-EMAIL", "I-EMAIL"],
      phone: ["PHONE", "PHONE_NUMBER", "B-PHONE", "I-PHONE"],
      date_time: ["DATE", "TIME", "DATE_TIME", "B-DATE", "I-DATE", "B-TIME", "I-TIME"],
      nationality: ["NORP", "NRP"]
    },
    ab_ai_pii_model: %{
      person: @ab_ai_person_labels,
      organization: @ab_ai_organization_labels,
      location: @ab_ai_location_labels,
      email: @ab_ai_email_labels,
      phone: @ab_ai_phone_labels,
      credit_card: @ab_ai_credit_card_labels,
      us_ssn: @ab_ai_us_ssn_labels,
      iban: @ab_ai_iban_labels,
      url: @ab_ai_url_labels,
      date_time: @ab_ai_date_time_labels
    },
    ar86bat_multilang_pii_ner: %{
      person: @ar86bat_person_labels,
      location: @ar86bat_location_labels,
      email: @ar86bat_email_labels,
      phone: @ar86bat_phone_labels,
      credit_card: @ar86bat_credit_card_labels,
      us_ssn: @ar86bat_us_ssn_labels,
      date_time: @ar86bat_date_time_labels
    },
    isotonic_distilbert_ai4privacy_v2: %{
      person: @isotonic_person_labels,
      organization: @isotonic_organization_labels,
      location: @isotonic_location_labels
    },
    dbmdz_bert_large_conll03: %{
      person: ["PER", "B-PER", "I-PER"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["LOC", "B-LOC", "I-LOC"]
    },
    davlan_xlm_roberta_large_ner_hrl: %{
      person: ["PER", "B-PER", "I-PER"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["LOC", "B-LOC", "I-LOC"]
    },
    davlan_xlm_roberta_base_wikiann_ner: %{
      person: ["PER", "B-PER", "I-PER"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["LOC", "B-LOC", "I-LOC"]
    },
    facebook_xlm_roberta_large_conll03_english: %{
      person: ["PER", "B-PER", "I-PER"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["LOC", "B-LOC", "I-LOC"]
    },
    tner_roberta_large_ontonotes5: %{
      person: ["PERSON", "B-PERSON", "I-PERSON"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["GPE", "B-GPE", "I-GPE", "LOC", "B-LOC", "I-LOC", "FAC", "B-FAC", "I-FAC"]
    },
    learnrr_roberta_large_ontonotes5_ner: %{
      person: ["PERSON", "B-PERSON", "I-PERSON"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["GPE", "B-GPE", "I-GPE", "LOC", "B-LOC", "I-LOC", "FAC", "B-FAC", "I-FAC"]
    },
    learnrr_bert_base_ontonotes5_ner: %{
      person: ["PERSON", "B-PERSON", "I-PERSON"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["GPE", "B-GPE", "I-GPE", "LOC", "B-LOC", "I-LOC", "FAC", "B-FAC", "I-FAC"]
    },
    learnrr_bert_large_ontonotes5_ner: %{
      person: ["PERSON", "B-PERSON", "I-PERSON"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["GPE", "B-GPE", "I-GPE", "LOC", "B-LOC", "I-LOC", "FAC", "B-FAC", "I-FAC"]
    },
    nickprock_bert_finetuned_ner_ontonotes: %{
      person: ["PERSON", "B-PERSON", "I-PERSON"],
      organization: ["ORG", "B-ORG", "I-ORG"],
      location: ["GPE", "B-GPE", "I-GPE", "LOC", "B-LOC", "I-LOC", "FAC", "B-FAC", "I-FAC"]
    },
    jean_baptiste_roberta_large_ner_english: %{
      person: ["PER"],
      organization: ["ORG"],
      location: ["LOC"]
    },
    openai_privacy_filter: %{
      person: @privacy_filter_person_labels,
      location: @privacy_filter_location_labels,
      email: @privacy_filter_email_labels,
      phone: @privacy_filter_phone_labels,
      url: @privacy_filter_url_labels,
      date_time: @privacy_filter_date_time_labels
    },
    openmed_privacy_filter_nemotron: @openmed_label_map,
    openmed_pii_superclinical_small: @openmed_label_map,
    openmed_pii_superclinical_large: @openmed_label_map,
    openmed_pii_bigmed_large: @openmed_label_map,
    shield_82m: %{
      person: ["FIRSTNAME", "MIDDLENAME", "LASTNAME", "PREFIX"],
      organization: ["COMPANYNAME"],
      location: ["CITY", "COUNTY", "STATE", "STREET", "SECONDARYADDRESS", "ZIPCODE"],
      email: ["EMAIL"],
      phone: ["PHONENUMBER", "PHONEIMEI"],
      us_ssn: ["SSN"],
      iban: ["IBAN"],
      ip_address: ["IP", "IPV4", "IPV6"],
      url: ["URL"],
      credit_card: ["CREDITCARDNUMBER", "CREDITCARDCVV", "CREDITCARDISSUER"]
    },
    obi_deid_roberta_i2b2: %{
      person: @obi_person_labels,
      organization: @obi_organization_labels,
      location: @obi_location_labels,
      email: @obi_email_labels,
      phone: @obi_phone_labels,
      date_time: @obi_date_time_labels
    },
    piiranha_v1: %{
      id:
        Enum.filter(@piiranha_labels, fn label ->
          String.replace(label, ~r/^(B|I)-/, "") in ["ACCOUNTNUM", "IDCARDNUM", "TAXNUM"]
        end),
      street_address:
        Enum.filter(@piiranha_labels, fn label ->
          String.replace(label, ~r/^(B|I)-/, "") in ["BUILDINGNUM", "STREET"]
        end),
      location:
        Enum.filter(@piiranha_labels, fn label ->
          String.replace(label, ~r/^(B|I)-/, "") == "CITY"
        end),
      credit_card: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "CREDITCARDNUMBER")),
      date_time: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "DATEOFBIRTH")),
      us_driver_license:
        Enum.filter(@piiranha_labels, &String.ends_with?(&1, "DRIVERLICENSENUM")),
      email: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "EMAIL")),
      person:
        Enum.filter(@piiranha_labels, fn label ->
          String.replace(label, ~r/^(B|I)-/, "") in ["GIVENNAME", "SURNAME"]
        end),
      password: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "PASSWORD")),
      us_ssn: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "SOCIALNUM")),
      phone: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "TELEPHONENUM")),
      username: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "USERNAME")),
      zip_code: Enum.filter(@piiranha_labels, &String.ends_with?(&1, "ZIPCODE"))
    },
    eu_pii_safeguard: %{
      person: ["PER", "PERSON", "B-PER", "I-PER", "NAME"],
      organization: ["ORG", "ORGANIZATION", "B-ORG", "I-ORG"],
      location: ["LOC", "LOCATION", "B-LOC", "I-LOC"],
      email: ["EMAIL"],
      phone: ["PHONE", "PHONE_NUMBER"]
    }
  }

  @deterministic_entities [
    :email,
    :phone,
    :credit_card,
    :date_time,
    :id,
    :us_ssn,
    :us_driver_license,
    :iban,
    :ip_address,
    :url,
    :domain,
    :location,
    :password,
    :person,
    :street_address,
    :username,
    :zip_code
  ]

  @known_entities @default
                  |> Map.keys()
                  |> Kernel.++(Map.keys(@phi))
                  |> Kernel.++(@deterministic_entities)
                  |> Enum.uniq()

  @doc """
  Returns default label mappings.
  """
  @spec default() :: %{atom() => [String.t()]}
  def default, do: @default

  @doc """
  Returns a model-specific label map.
  """
  @spec for_model(atom()) :: {:ok, %{atom() => [String.t()]}} | {:error, term()}
  def for_model(model) when is_atom(model) do
    case Map.fetch(@model_maps, model) do
      {:ok, label_map} -> {:ok, label_map}
      :error -> {:error, {:unknown_label_map, model}}
    end
  end

  @doc """
  Returns all known Phase 4 NER entity atoms.
  """
  @spec known_entities() :: [atom()]
  def known_entities, do: @known_entities

  @doc """
  Maps a model label to an Obscura entity atom.
  """
  @spec to_entity(String.t(), keyword()) :: {:ok, atom()} | {:error, term()}
  def to_entity(label, opts \\ [])

  def to_entity(label, opts) when is_binary(label) do
    opts
    |> Keyword.get(:label_map, @default)
    |> normalize_label_map()
    |> case do
      {:ok, label_map} -> find_entity(label_map, label)
      {:error, reason} -> {:error, reason}
    end
  end

  def to_entity(label, _opts), do: {:error, {:unknown_model_label, label}}

  @doc """
  Validates and normalizes caller-provided label maps.
  """
  @spec normalize_label_map(map()) :: {:ok, %{atom() => [String.t()]}} | {:error, term()}
  def normalize_label_map(label_map) when is_atom(label_map) do
    with {:ok, label_map} <- for_model(label_map) do
      normalize_label_map(label_map)
    end
  end

  def normalize_label_map(label_map) when is_map(label_map) do
    Enum.reduce_while(label_map, {:ok, %{}}, fn {entity, labels}, {:ok, acc} ->
      cond do
        entity not in @known_entities ->
          {:halt, {:error, {:unsupported_ner_entity, entity}}}

        not is_list(labels) or not Enum.all?(labels, &is_binary/1) ->
          {:halt, {:error, {:invalid_labels, entity}}}

        true ->
          {:cont, {:ok, Map.put(acc, entity, labels)}}
      end
    end)
  end

  def normalize_label_map(_label_map), do: {:error, :invalid_label_map}

  defp find_entity(label_map, label) do
    label_map
    |> Enum.find(fn {_entity, labels} -> label in labels end)
    |> case do
      {entity, _labels} -> {:ok, entity}
      nil -> {:error, {:unknown_model_label, label}}
    end
  end
end
