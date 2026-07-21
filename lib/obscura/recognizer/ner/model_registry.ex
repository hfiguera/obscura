defmodule Obscura.Recognizer.NER.ModelRegistry do
  @moduledoc """
  Registry for optional local token-classification models.
  """

  alias Obscura.Recognizer.NER.ModelSpec
  alias Obscura.Recognizer.NER.Policy

  @bilou_prefixes ["", "B-", "I-", "L-", "U-"]
  @obi_ignored_labels for label <- ["AGE", "DATE", "EMAIL", "ID", "OTHERPHI", "PHONE"],
                          prefix <- @bilou_prefixes,
                          do: "#{prefix}#{label}"
  @isotonic_ignored_labels for label <- [
                                 "ACCOUNTNAME",
                                 "ACCOUNTNUMBER",
                                 "AGE",
                                 "AMOUNT",
                                 "BIC",
                                 "BITCOINADDRESS",
                                 "CREDITCARDCVV",
                                 "CREDITCARDISSUER",
                                 "CREDITCARDNUMBER",
                                 "CURRENCY",
                                 "CURRENCYCODE",
                                 "CURRENCYNAME",
                                 "CURRENCYSYMBOL",
                                 "DATE",
                                 "DOB",
                                 "EMAIL",
                                 "ETHEREUMADDRESS",
                                 "EYECOLOR",
                                 "GENDER",
                                 "HEIGHT",
                                 "JOBAREA",
                                 "JOBTITLE",
                                 "JOBTYPE",
                                 "LITECOINADDRESS",
                                 "MAC",
                                 "MASKEDNUMBER",
                                 "NEARBYGPSCOORDINATE",
                                 "ORDINALDIRECTION",
                                 "PASSWORD",
                                 "PHONEIMEI",
                                 "PHONENUMBER",
                                 "PIN",
                                 "PREFIX",
                                 "SEX",
                                 "TIME",
                                 "USERAGENT",
                                 "USERNAME",
                                 "VEHICLEVIN",
                                 "VEHICLEVRM",
                                 "URL",
                                 "SSN",
                                 "IBAN",
                                 "IP",
                                 "IPV4",
                                 "IPV6"
                               ],
                               prefix <- ["", "B-", "I-"],
                               do: "#{prefix}#{label}"
  @ontonotes_ignored_labels [
    "B-CARDINAL",
    "I-CARDINAL",
    "B-DATE",
    "I-DATE",
    "B-EVENT",
    "I-EVENT",
    "B-LANGUAGE",
    "I-LANGUAGE",
    "B-LAW",
    "I-LAW",
    "B-MONEY",
    "I-MONEY",
    "B-NORP",
    "I-NORP",
    "B-ORDINAL",
    "I-ORDINAL",
    "B-PERCENT",
    "I-PERCENT",
    "B-PRODUCT",
    "I-PRODUCT",
    "B-QUANTITY",
    "I-QUANTITY",
    "B-TIME",
    "I-TIME",
    "B-WORK_OF_ART",
    "I-WORK_OF_ART"
  ]
  @ontonotes_conservative_policy [
    labels_to_ignore: @ontonotes_ignored_labels,
    per_entity_thresholds: %{organization: 0.95, location: 0.8},
    per_label_thresholds: %{
      "PERSON" => 0.72,
      "ORG" => 0.98,
      "GPE" => 0.9,
      "LOC" => 0.92,
      "FAC" => 0.97
    },
    context_required_labels: ["FAC"],
    context_required_below_thresholds: %{organization: 0.98},
    context_required_below_labels: %{
      "ORG" => 0.99,
      "LOC" => 0.96,
      "FAC" => 0.99
    },
    context_words_by_entity: %{
      organization: [
        "company",
        "employer",
        "organization",
        "works at",
        "work at",
        "affiliated with"
      ],
      location: [
        "address",
        "city",
        "country",
        "facility",
        "headquartered",
        "hospital",
        "in",
        "located",
        "location",
        "office",
        "state"
      ]
    },
    context_words_by_label: Policy.ontonotes_context_words_by_label(),
    weak_context_words_by_label: %{"FAC" => ["in"]},
    negative_context_words_by_label: %{
      "GPE" => [
        "account",
        "case",
        "code",
        "invoice",
        "order",
        "payment",
        "product",
        "reference",
        "ticket"
      ]
    },
    negative_context_reject_labels: ["GPE"],
    aggregation_strategy: :same,
    alignment_mode: :expand
  ]
  @conll_conservative_policy [
    labels_to_ignore: ["MISC", "B-MISC", "I-MISC"],
    per_entity_thresholds: %{organization: 0.95, location: 0.8},
    per_label_thresholds: %{
      "PER" => 0.72,
      "ORG" => 0.98,
      "LOC" => 0.92
    },
    context_required_below_thresholds: %{organization: 0.98},
    context_required_below_labels: %{
      "ORG" => 0.99,
      "LOC" => 0.96
    },
    context_words_by_entity: %{
      organization: [
        "company",
        "employer",
        "organization",
        "works at",
        "work at",
        "affiliated with"
      ],
      location: ["address", "city", "country", "located", "location", "office", "state"]
    },
    context_words_by_label: %{
      "ORG" => [
        "company",
        "employer",
        "organization",
        "works at",
        "work at",
        "affiliated with"
      ],
      "LOC" => ["address", "city", "country", "located", "location", "office", "state"]
    },
    aggregation_strategy: :same,
    alignment_mode: :expand
  ]
  @wikiann_conservative_policy [
    labels_to_ignore: ["DATE", "B-DATE", "I-DATE"],
    per_entity_thresholds: %{organization: 0.95, location: 0.8},
    per_label_thresholds: %{
      "PER" => 0.72,
      "ORG" => 0.98,
      "LOC" => 0.92
    },
    context_required_below_thresholds: %{organization: 0.98},
    context_required_below_labels: %{
      "ORG" => 0.99,
      "LOC" => 0.96
    },
    context_words_by_entity: %{
      organization: [
        "company",
        "employer",
        "organization",
        "works at",
        "work at",
        "affiliated with"
      ],
      location: ["address", "city", "country", "located", "location", "office", "state"]
    },
    context_words_by_label: %{
      "ORG" => [
        "company",
        "employer",
        "organization",
        "works at",
        "work at",
        "affiliated with"
      ],
      "LOC" => ["address", "city", "country", "located", "location", "office", "state"]
    },
    aggregation_strategy: :same,
    alignment_mode: :expand
  ]
  @isotonic_ai4privacy_policy [
    labels_to_ignore: @isotonic_ignored_labels,
    per_label_thresholds: %{
      "FIRSTNAME" => 0.82,
      "MIDDLENAME" => 0.9,
      "LASTNAME" => 0.82,
      "COMPANYNAME" => 0.98,
      "CITY" => 0.9,
      "STATE" => 0.94,
      "COUNTY" => 0.96,
      "STREET" => 0.96,
      "SECONDARYADDRESS" => 0.98,
      "BUILDINGNUMBER" => 0.98,
      "ZIPCODE" => 0.98
    },
    context_required_below_labels: %{
      "COMPANYNAME" => 0.99,
      "STREET" => 0.98,
      "SECONDARYADDRESS" => 0.98,
      "BUILDINGNUMBER" => 0.98,
      "ZIPCODE" => 0.99
    },
    context_words_by_label: %{
      "COMPANYNAME" => [
        "affiliated with",
        "business",
        "company",
        "employer",
        "organization",
        "works at",
        "work at"
      ],
      "CITY" => ["address", "city", "country", "located", "location", "office", "state"],
      "STATE" => ["address", "city", "located", "location", "state"],
      "COUNTY" => ["address", "county", "located", "location"],
      "STREET" => ["address", "building", "located", "location", "office", "street"],
      "SECONDARYADDRESS" => ["address", "apartment", "building", "office", "suite"],
      "BUILDINGNUMBER" => ["address", "building", "office", "street"],
      "ZIPCODE" => ["address", "city", "postal", "state", "zip"]
    },
    validate_structured_model_entities: true,
    aggregation_strategy: :same,
    alignment_mode: :expand
  ]
  @stanford_deidentifier_policy [
    labels_to_ignore: ["O", "ID"],
    low_score_entity_names: ["ID"],
    low_confidence_score_multiplier: 0.4,
    per_label_thresholds: %{
      "PATIENT" => 0.72,
      "HCW" => 0.82,
      "VENDOR" => 0.96,
      "HOSPITAL" => 0.9,
      "DATE" => 0.8,
      "PHONE" => 0.8
    },
    context_required_below_labels: %{
      "VENDOR" => 0.98,
      "HOSPITAL" => 0.94
    },
    context_words_by_label: %{
      "VENDOR" => [
        "affiliate",
        "company",
        "contractor",
        "employer",
        "organization",
        "vendor",
        "works at"
      ],
      "HOSPITAL" => [
        "clinic",
        "department",
        "facility",
        "hospital",
        "medical center",
        "radiology"
      ]
    },
    aggregation_strategy: :max,
    alignment_mode: :expand,
    stride: 16
  ]

  @models %{
    dslim_bert_base_ner: %{
      id: :dslim_bert_base_ner,
      model: {:hf, "dslim/bert-base-NER"},
      tokenizer: {:hf, "google-bert/bert-base-cased"},
      task: :token_classification,
      aggregation: :same,
      label_map: :dslim_bert_base_ner,
      entities: [:person, :organization, :location],
      license: "MIT",
      required?: true,
      status: :supported,
      policy: [
        aggregation_strategy: :same,
        alignment_mode: :expand
      ],
      notes: "First Phase 4.5 validation model."
    },
    dslim_bert_large_ner: %{
      id: :dslim_bert_large_ner,
      model: {:hf, "dslim/bert-large-NER"},
      tokenizer: {:hf, "google-bert/bert-large-cased"},
      task: :token_classification,
      aggregation: :same,
      label_map: :dslim_bert_large_ner,
      entities: [:person, :organization, :location],
      license: "MIT",
      required?: false,
      status: :experimental,
      policy: @conll_conservative_policy,
      notes:
        "Experimental BERT-large CoNLL-2003 NER candidate from dslim. Uses the canonical bert-large-cased tokenizer because the fine-tuned repo exposes vocab.txt and an ONNX tokenizer.json but not a root Rust-compatible tokenizer.json."
    },
    stanford_deidentifier_base: %{
      id: :stanford_deidentifier_base,
      model: {:hf, "StanfordAIMI/stanford-deidentifier-base"},
      tokenizer: {:hf, "StanfordAIMI/stanford-deidentifier-base"},
      task: :token_classification,
      aggregation: :max,
      label_map: :stanford_deidentifier_base,
      entities: [:person, :organization, :location, :phone, :date_time],
      license: "MIT",
      required?: false,
      status: :experimental,
      policy: @stanford_deidentifier_policy,
      notes:
        "Presidio transformers.yaml model candidate; MIT licensed, but native Bumblebee support must be proven before default recommendation."
    },
    obi_deid_roberta_i2b2: %{
      id: :obi_deid_roberta_i2b2,
      model: {:hf, "obi/deid_roberta_i2b2"},
      tokenizer: {:hf, "obi/deid_roberta_i2b2"},
      task: :token_classification,
      aggregation: :same,
      label_map: :obi_deid_roberta_i2b2,
      entities: [:person, :organization, :location, :email, :phone, :date_time, :nationality],
      license: "MIT",
      required?: false,
      status: :experimental,
      policy: [
        labels_to_ignore: @obi_ignored_labels,
        per_label_thresholds: %{
          "PATIENT" => 0.72,
          "STAFF" => 0.72,
          "HCW" => 0.82,
          "PATORG" => 0.94,
          "VENDOR" => 0.96,
          "LOC" => 0.88,
          "HOSP" => 0.9
        },
        context_required_below_labels: %{
          "PATORG" => 0.98,
          "VENDOR" => 0.98,
          "HOSP" => 0.94
        },
        context_words_by_label: %{
          "PATORG" => [
            "affiliated with",
            "company",
            "department",
            "employer",
            "organization",
            "works at",
            "work at"
          ],
          "VENDOR" => [
            "company",
            "employer",
            "organization",
            "vendor",
            "works at",
            "work at"
          ],
          "HOSP" => [
            "clinic",
            "facility",
            "hospital",
            "medical center",
            "office"
          ],
          "LOC" => [
            "address",
            "city",
            "country",
            "located",
            "location",
            "state"
          ]
        },
        aggregation_strategy: :same,
        alignment_mode: :expand
      ],
      notes:
        "Presidio TransformersNlpEngine default/example PHI candidate; evaluated before any default recommendation."
    },
    ab_ai_pii_model: %{
      id: :ab_ai_pii_model,
      model: {:hf, "ab-ai/pii_model"},
      tokenizer: {:hf, "ab-ai/pii_model"},
      task: :token_classification,
      aggregation: :same,
      label_map: :ab_ai_pii_model,
      entities: [
        :person,
        :organization,
        :location,
        :email,
        :phone,
        :credit_card,
        :us_ssn,
        :iban,
        :url,
        :date_time
      ],
      license: "apache-2.0",
      required?: false,
      status: :experimental,
      notes:
        "BERT-based PII candidate from V10; gated Hugging Face access must be accepted before runtime validation."
    },
    ar86bat_multilang_pii_ner: %{
      id: :ar86bat_multilang_pii_ner,
      model: {:hf, "Ar86Bat/multilang-pii-ner"},
      tokenizer: {:hf, "Ar86Bat/multilang-pii-ner"},
      task: :token_classification,
      aggregation: :same,
      label_map: :ar86bat_multilang_pii_ner,
      entities: [
        :person,
        :location,
        :email,
        :phone,
        :credit_card,
        :us_ssn,
        :date_time
      ],
      license: "MIT",
      required?: false,
      status: :experimental,
      notes:
        "XLM-RoBERTa multilingual PII candidate from V10; not default until heldout metrics prove value."
    },
    isotonic_distilbert_ai4privacy_v2: %{
      id: :isotonic_distilbert_ai4privacy_v2,
      model: {:hf, "Isotonic/distilbert_finetuned_ai4privacy_v2"},
      tokenizer: {:hf, "Isotonic/distilbert_finetuned_ai4privacy_v2"},
      task: :token_classification,
      aggregation: :same,
      label_map: :isotonic_distilbert_ai4privacy_v2,
      entities: [
        :person,
        :organization,
        :location
      ],
      license: "cc-by-nc-4.0",
      required?: false,
      status: :experimental,
      policy: @isotonic_ai4privacy_policy,
      notes:
        "Experimental DistilBERT AI4Privacy PII candidate with FIRSTNAME/LASTNAME, COMPANYNAME, city/state/county, and address-like labels. Structured labels stay ignored because deterministic recognizers cover them more reliably. The license is non-commercial, so it is benchmark-only and never a default production recommendation."
    },
    dbmdz_bert_large_conll03: %{
      id: :dbmdz_bert_large_conll03,
      model: {:hf, "dbmdz/bert-large-cased-finetuned-conll03-english"},
      tokenizer: {:hf, "google-bert/bert-large-cased"},
      task: :token_classification,
      aggregation: :same,
      label_map: :dbmdz_bert_large_conll03,
      entities: [:person, :organization, :location],
      license: "unknown",
      required?: false,
      status: :experimental,
      policy: [
        per_entity_thresholds: %{organization: 0.9},
        context_required_below_thresholds: %{organization: 0.95},
        context_words_by_entity: %{
          organization: [
            "company",
            "employer",
            "organization",
            "works at",
            "work at",
            "affiliated with"
          ]
        },
        aggregation_strategy: :same,
        alignment_mode: :expand
      ],
      notes:
        "BERT-large CoNLL-2003 NER control from V10; uses the canonical bert-large-cased tokenizer because the fine-tuned repo lacks tokenizer.json."
    },
    davlan_xlm_roberta_large_ner_hrl: %{
      id: :davlan_xlm_roberta_large_ner_hrl,
      model: {:hf, "Davlan/xlm-roberta-large-ner-hrl"},
      tokenizer: {:hf, "FacebookAI/xlm-roberta-large"},
      task: :token_classification,
      aggregation: :same,
      label_map: :davlan_xlm_roberta_large_ner_hrl,
      entities: [:person, :organization, :location],
      license: "unknown",
      required?: false,
      status: :experimental,
      policy: @conll_conservative_policy,
      notes:
        "Experimental XLM-R large high-resource NER candidate with PER/ORG/LOC labels; uses the base XLM-R large tokenizer because the fine-tuned repo lacks tokenizer.json. Evaluated as a V24 location/organization candidate before any recommendation."
    },
    davlan_xlm_roberta_base_wikiann_ner: %{
      id: :davlan_xlm_roberta_base_wikiann_ner,
      model: {:hf, "Davlan/xlm-roberta-base-wikiann-ner"},
      tokenizer: {:hf, "Davlan/xlm-roberta-base-wikiann-ner"},
      task: :token_classification,
      aggregation: :same,
      label_map: :davlan_xlm_roberta_base_wikiann_ner,
      entities: [:person, :organization, :location],
      license: "unknown",
      required?: false,
      status: :experimental,
      policy: @wikiann_conservative_policy,
      notes:
        "Experimental XLM-R base WikiANN token-classification candidate with PER/ORG/LOC/DATE labels and a repository-provided tokenizer.json. DATE is ignored for the location/organization validation phase."
    },
    facebook_xlm_roberta_large_conll03_english: %{
      id: :facebook_xlm_roberta_large_conll03_english,
      model: {:hf, "FacebookAI/xlm-roberta-large-finetuned-conll03-english"},
      tokenizer: {:hf, "FacebookAI/xlm-roberta-large-finetuned-conll03-english"},
      task: :token_classification,
      aggregation: :same,
      label_map: :facebook_xlm_roberta_large_conll03_english,
      entities: [:person, :organization, :location],
      license: "unknown",
      required?: false,
      status: :experimental,
      policy: @conll_conservative_policy,
      notes:
        "Experimental official XLM-R large CoNLL-2003 token-classification candidate with PER/ORG/LOC labels and a repository-provided tokenizer.json. Evaluated as a V26 location/organization candidate before any recommendation."
    },
    tner_roberta_large_ontonotes5: %{
      id: :tner_roberta_large_ontonotes5,
      model:
        {:hf, "tner/roberta-large-ontonotes5",
         revision: "0bce50f7884d5bb040469c907c897d4b061ccbb4"},
      tokenizer:
        {:hf, "tner/roberta-large-ontonotes5",
         revision: "0bce50f7884d5bb040469c907c897d4b061ccbb4"},
      task: :token_classification,
      aggregation: :same,
      label_map: :tner_roberta_large_ontonotes5,
      entities: [:person, :organization, :location],
      license: "unknown",
      required?: false,
      status: :experimental,
      policy: @ontonotes_conservative_policy,
      notes:
        "Experimental RoBERTa-large OntoNotes5 candidate. The Hugging Face model card reports strong OntoNotes metrics but warns that plain Transformers usage is not recommended because the training CRF layer is unsupported; Obscura must validate Bumblebee output before recommending it."
    },
    learnrr_roberta_large_ontonotes5_ner: %{
      id: :learnrr_roberta_large_ontonotes5_ner,
      model: {:hf, "learnrr/roberta-large-ontonotes5-ner"},
      tokenizer: {:hf, "learnrr/roberta-large-ontonotes5-ner"},
      task: :token_classification,
      aggregation: :same,
      label_map: :learnrr_roberta_large_ontonotes5_ner,
      entities: [:person, :organization, :location],
      license: "MIT",
      required?: false,
      status: :experimental,
      policy: @ontonotes_conservative_policy,
      notes:
        "MIT-licensed RoBERTa-large OntoNotes5 candidate without the TNER model card CRF warning; evaluated as a V19 location/organization candidate before any recommendation."
    },
    learnrr_bert_base_ontonotes5_ner: %{
      id: :learnrr_bert_base_ontonotes5_ner,
      model: {:hf, "learnrr/bert-base-ontonotes5-ner"},
      tokenizer: {:hf, "learnrr/bert-base-ontonotes5-ner"},
      task: :token_classification,
      aggregation: :same,
      label_map: :learnrr_bert_base_ontonotes5_ner,
      entities: [:person, :organization, :location],
      license: "MIT",
      required?: false,
      status: :experimental,
      policy: @ontonotes_conservative_policy,
      notes:
        "V20 MIT-licensed BERT-base OntoNotes5 candidate with PERSON/ORG/GPE/LOC/FAC labels; evaluated before any recommendation."
    },
    learnrr_bert_large_ontonotes5_ner: %{
      id: :learnrr_bert_large_ontonotes5_ner,
      model: {:hf, "learnrr/bert-large-ontonotes5-ner"},
      tokenizer: {:hf, "learnrr/bert-large-ontonotes5-ner"},
      task: :token_classification,
      aggregation: :same,
      label_map: :learnrr_bert_large_ontonotes5_ner,
      entities: [:person, :organization, :location],
      license: "MIT",
      required?: false,
      status: :experimental,
      policy: @ontonotes_conservative_policy,
      notes:
        "V20 MIT-licensed BERT-large OntoNotes5 candidate with PERSON/ORG/GPE/LOC/FAC labels; evaluated before any recommendation."
    },
    nickprock_bert_finetuned_ner_ontonotes: %{
      id: :nickprock_bert_finetuned_ner_ontonotes,
      model: {:hf, "nickprock/bert-finetuned-ner-ontonotes"},
      tokenizer: {:hf, "nickprock/bert-finetuned-ner-ontonotes"},
      task: :token_classification,
      aggregation: :same,
      label_map: :nickprock_bert_finetuned_ner_ontonotes,
      entities: [:person, :organization, :location],
      license: "apache-2.0",
      required?: false,
      status: :experimental,
      policy: @ontonotes_conservative_policy,
      notes:
        "Experimental Apache-2.0 BERT-base OntoNotes candidate with PERSON/ORG/GPE/LOC/FAC labels and a repository-provided tokenizer.json. Evaluated as a V26 fallback native location/organization candidate before any recommendation."
    },
    jean_baptiste_roberta_large_ner_english: %{
      id: :jean_baptiste_roberta_large_ner_english,
      model:
        {:hf, "Jean-Baptiste/roberta-large-ner-english",
         revision: "8f3abc1ef81ffbbb0e80568d4fed1dd10d459548"},
      tokenizer:
        {:hf, "FacebookAI/roberta-large", revision: "722cf37b1afa9454edce342e7895e588b6ff1d59"},
      task: :token_classification,
      aggregation: :same,
      label_map: :jean_baptiste_roberta_large_ner_english,
      entities: [:person, :organization, :location],
      license: "MIT",
      required?: false,
      status: :experimental,
      policy: @conll_conservative_policy,
      notes:
        "V20 MIT-licensed RoBERTa-large CoNLL/email-chat candidate with PER/ORG/LOC labels; uses the base RoBERTa-large tokenizer because the fine-tuned repo lacks tokenizer.json. Evaluated before any recommendation."
    },
    openai_privacy_filter: %{
      id: :openai_privacy_filter,
      model: {:hf, "openai/privacy-filter"},
      tokenizer: {:hf, "openai/privacy-filter"},
      task: :token_classification,
      aggregation: :same,
      label_map: :openai_privacy_filter,
      entities: [:person, :location, :email, :phone, :url, :date_time],
      license: "apache-2.0",
      required?: false,
      status: :experimental,
      notes:
        "PII Masking leaderboard token-classification model; custom openai_privacy_filter architecture must be proven before native Bumblebee use."
    },
    openmed_privacy_filter_nemotron: %{
      id: :openmed_privacy_filter_nemotron,
      model: {:hf, "OpenMed/privacy-filter-nemotron"},
      tokenizer: {:hf, "OpenMed/privacy-filter-nemotron"},
      task: :token_classification,
      aggregation: :same,
      label_map: :openmed_privacy_filter_nemotron,
      entities: [
        :person,
        :organization,
        :location,
        :email,
        :phone,
        :credit_card,
        :us_ssn,
        :ip_address,
        :url,
        :date_time,
        :patient_id
      ],
      license: "apache-2.0",
      required?: false,
      status: :experimental,
      notes:
        "PII Masking leaderboard Nemotron fine-tune; custom openai_privacy_filter architecture must be proven before native Bumblebee use."
    },
    openmed_pii_superclinical_small: %{
      id: :openmed_pii_superclinical_small,
      model: {:hf, "OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1"},
      tokenizer: {:hf, "OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1"},
      task: :token_classification,
      aggregation: :same,
      label_map: :openmed_pii_superclinical_small,
      entities: [
        :person,
        :organization,
        :location,
        :email,
        :phone,
        :credit_card,
        :us_ssn,
        :ip_address,
        :url,
        :date_time,
        :patient_id
      ],
      license: "apache-2.0",
      required?: false,
      status: :experimental,
      notes:
        "PII Masking leaderboard clinical DeBERTa-v3-small model; native Bumblebee support must be proven before default use."
    },
    openmed_pii_superclinical_large: %{
      id: :openmed_pii_superclinical_large,
      model: {:hf, "OpenMed/OpenMed-PII-SuperClinical-Large-434M-v1"},
      tokenizer: {:hf, "OpenMed/OpenMed-PII-SuperClinical-Large-434M-v1"},
      task: :token_classification,
      aggregation: :same,
      label_map: :openmed_pii_superclinical_large,
      entities: [
        :person,
        :organization,
        :location,
        :email,
        :phone,
        :credit_card,
        :us_ssn,
        :ip_address,
        :url,
        :date_time,
        :patient_id
      ],
      license: "apache-2.0",
      required?: false,
      status: :experimental,
      policy: [
        labels_to_ignore: [
          "age",
          "coordinate",
          "date",
          "date_of_birth",
          "date_time",
          "fax_number",
          "gender",
          "health_plan_beneficiary_number",
          "medical_record_number",
          "time"
        ],
        per_label_thresholds: %{
          "first_name" => 0.9,
          "last_name" => 0.9,
          "company_name" => 0.98,
          "city" => 0.94,
          "country" => 0.94,
          "county" => 0.96,
          "postcode" => 0.98,
          "state" => 0.96,
          "street_address" => 0.96
        },
        context_required_below_labels: %{
          "company_name" => 0.99,
          "street_address" => 0.98
        },
        context_words_by_label: %{
          "company_name" => [
            "affiliated with",
            "company",
            "department",
            "employer",
            "organization",
            "works at",
            "work at"
          ],
          "street_address" => [
            "address",
            "building",
            "located",
            "location",
            "office",
            "street"
          ],
          "city" => ["address", "city", "country", "located", "location", "state"],
          "country" => ["address", "country", "located", "location"],
          "state" => ["address", "city", "located", "location", "state"]
        },
        low_score_entity_names: [:organization, :location],
        low_confidence_score_multiplier: 0.4,
        validate_structured_model_entities: true,
        aggregation_strategy: :same,
        alignment_mode: :expand
      ],
      notes:
        "PII Masking leaderboard clinical DeBERTa-v3-large model; native Bumblebee support must be proven before default use."
    },
    openmed_pii_bigmed_large: %{
      id: :openmed_pii_bigmed_large,
      model: {:hf, "OpenMed/OpenMed-PII-BigMed-Large-560M-v1"},
      tokenizer: {:hf, "OpenMed/OpenMed-PII-BigMed-Large-560M-v1"},
      task: :token_classification,
      aggregation: :same,
      label_map: :openmed_pii_bigmed_large,
      entities: [
        :person,
        :organization,
        :location,
        :email,
        :phone,
        :credit_card,
        :us_ssn,
        :ip_address,
        :url,
        :date_time,
        :patient_id
      ],
      license: "apache-2.0",
      required?: false,
      status: :experimental,
      policy: [
        labels_to_ignore: [
          "age",
          "coordinate",
          "county",
          "date",
          "date_of_birth",
          "date_time",
          "fax_number",
          "gender",
          "health_plan_beneficiary_number",
          "medical_record_number",
          "postcode",
          "private_address",
          "private_date",
          "state",
          "street_address",
          "time"
        ],
        per_entity_thresholds: Policy.bigmed_conservative_thresholds(),
        low_score_entity_names: [:organization, :location, :date_time, :patient_id],
        low_confidence_score_multiplier: 0.4,
        validate_structured_model_entities: true,
        aggregation_strategy: :same,
        alignment_mode: :expand
      ],
      notes:
        "PII Masking leaderboard XLM-RoBERTa-large model; promising but heavy, so it remains benchmark-only until metrics justify it."
    },
    shield_82m: %{
      id: :shield_82m,
      model: {:hf, "LH-Tech-AI/Shield-82M"},
      tokenizer: {:hf, "LH-Tech-AI/Shield-82M"},
      task: :token_classification,
      aggregation: :same,
      label_map: :shield_82m,
      entities: [
        :person,
        :organization,
        :location,
        :email,
        :phone,
        :us_ssn,
        :iban,
        :ip_address,
        :url,
        :credit_card
      ],
      license: "unknown",
      required?: false,
      status: :experimental,
      notes:
        "PII-oriented candidate; compatibility and license must be verified before default use."
    },
    piiranha_v1: %{
      id: :piiranha_v1,
      model: {:hf, "iiiorg/piiranha-v1-detect-personal-information"},
      tokenizer: {:hf, "iiiorg/piiranha-v1-detect-personal-information"},
      task: :token_classification,
      aggregation: :same,
      label_map: :piiranha_v1,
      entities: [
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
      ],
      license: "cc-by-nc-nd-4.0",
      required?: false,
      status: :experimental,
      notes:
        "Purpose-built multilingual PII candidate. Bumblebee cannot load its DeBERTaV2 architecture; use the experimental ONNX/Ortex evaluation path."
    },
    eu_pii_safeguard: %{
      id: :eu_pii_safeguard,
      model: {:hf, "tabularisai/eu-pii-safeguard"},
      tokenizer: {:hf, "tabularisai/eu-pii-safeguard"},
      task: :token_classification,
      aggregation: :same,
      label_map: :eu_pii_safeguard,
      entities: [:person, :organization, :location, :email, :phone],
      license: "commercial-evaluation",
      required?: false,
      status: :evaluation,
      notes: "European PII evaluation candidate, not a default model."
    }
  }

  @doc """
  Lists known model aliases.
  """
  @spec aliases() :: [atom()]
  def aliases, do: @models |> Enum.map(fn {alias, _attrs} -> alias end) |> Enum.sort()

  @doc """
  Fetches a normalized model spec for an alias or explicit Hugging Face model.
  """
  @spec fetch(atom() | {:hf, String.t()}, keyword()) :: {:ok, ModelSpec.t()} | {:error, term()}
  def fetch(model, opts \\ [])

  def fetch(model, opts) when is_atom(model) do
    case Map.fetch(@models, model) do
      {:ok, attrs} -> attrs |> merge_overrides(opts) |> ModelSpec.new()
      :error -> {:error, {:unsupported_model, model}}
    end
  end

  def fetch({:hf, model_id}, opts) when is_binary(model_id) do
    label_map = Keyword.get(opts, :label_map)

    with true <- is_atom(label_map) || {:error, :missing_explicit_label_map},
         {:ok, base} <- fetch(label_map, []) do
      overrides =
        opts
        |> Keyword.put(:model, {:hf, model_id})
        |> Keyword.put_new(:tokenizer, Keyword.get(opts, :tokenizer, base.tokenizer))
        |> Keyword.put(:id, label_map)
        |> Keyword.put(:required?, false)

      base
      |> Map.from_struct()
      |> merge_overrides(overrides)
      |> ModelSpec.new()
    end
  end

  def fetch(model, _opts), do: {:error, {:unsupported_model, model}}

  @doc """
  Fetches registry metadata without loading optional dependencies.
  """
  @spec metadata(atom()) :: {:ok, map()} | {:error, term()}
  def metadata(alias) when is_atom(alias) do
    with {:ok, spec} <- fetch(alias) do
      {:ok, ModelSpec.metadata(spec)}
    end
  end

  defp merge_overrides(attrs, opts) do
    Enum.reduce(opts, attrs, fn
      {:model_id, id}, acc when is_binary(id) ->
        Map.put(acc, :model, {:hf, id})

      {:tokenizer_id, id}, acc when is_binary(id) ->
        Map.put(acc, :tokenizer, {:hf, id})

      {:model, {:hf, _id} = model}, acc ->
        Map.put(acc, :model, model)

      {:tokenizer, {:hf, _id} = tokenizer}, acc ->
        Map.put(acc, :tokenizer, tokenizer)

      {:aggregation, aggregation}, acc when is_atom(aggregation) ->
        Map.put(acc, :aggregation, aggregation)

      {:label_map, label_map}, acc when is_atom(label_map) ->
        Map.put(acc, :label_map, label_map)

      {:offset_unit, unit}, acc when unit in [:byte, :character] ->
        Map.put(acc, :offset_unit, unit)

      {:policy, policy}, acc when is_list(policy) or is_map(policy) ->
        Map.put(acc, :policy, policy)

      {:id, id}, acc when is_atom(id) ->
        Map.put(acc, :id, id)

      {:required?, required?}, acc when is_boolean(required?) ->
        Map.put(acc, :required?, required?)

      _other, acc ->
        acc
    end)
  end
end
