defmodule Obscura.Recognizer.NER.ModelRegistryTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.LabelMap
  alias Obscura.Recognizer.NER.ModelRegistry

  test "normalizes dslim bert base NER model spec" do
    assert {:ok, spec} = ModelRegistry.fetch(:dslim_bert_base_ner)

    assert spec.id == :dslim_bert_base_ner
    assert spec.model == {:hf, "dslim/bert-base-NER"}
    assert spec.tokenizer == {:hf, "google-bert/bert-base-cased"}
    assert spec.task == :token_classification
    assert spec.aggregation == :same
    assert spec.label_map == :dslim_bert_base_ner
    assert spec.entities == [:person, :organization, :location]
    assert spec.license == "MIT"
    assert spec.offset_unit == :byte
  end

  test "normalizes dslim bert large NER model spec without changing base default" do
    assert {:ok, base} = ModelRegistry.fetch(:dslim_bert_base_ner)
    assert base.required? == true
    assert base.status == :supported

    assert {:ok, spec} = ModelRegistry.fetch(:dslim_bert_large_ner)

    assert spec.id == :dslim_bert_large_ner
    assert spec.model == {:hf, "dslim/bert-large-NER"}
    assert spec.tokenizer == {:hf, "google-bert/bert-large-cased"}
    assert spec.task == :token_classification
    assert spec.aggregation == :same
    assert spec.label_map == :dslim_bert_large_ner
    assert spec.entities == [:person, :organization, :location]
    assert spec.license == "MIT"
    assert spec.required? == false
    assert spec.status == :experimental
    assert spec.policy[:per_label_thresholds] == %{"PER" => 0.72, "ORG" => 0.98, "LOC" => 0.92}
    assert spec.policy[:context_required_below_labels] == %{"ORG" => 0.99, "LOC" => 0.96}
    assert spec.policy[:aggregation_strategy] == :same
    assert spec.policy[:alignment_mode] == :expand
    assert "MISC" in spec.policy[:labels_to_ignore]
    assert "B-MISC" in spec.policy[:labels_to_ignore]
    assert "I-MISC" in spec.policy[:labels_to_ignore]
  end

  test "returns safe error for unknown aliases" do
    assert {:error, {:unsupported_model, :unknown_model}} = ModelRegistry.fetch(:unknown_model)
  end

  test "normalizes Presidio-inspired real model candidate specs" do
    assert {:ok, stanford} = ModelRegistry.fetch(:stanford_deidentifier_base)
    assert stanford.model == {:hf, "StanfordAIMI/stanford-deidentifier-base"}
    assert stanford.tokenizer == {:hf, "StanfordAIMI/stanford-deidentifier-base"}
    assert stanford.aggregation == :max
    assert stanford.label_map == :stanford_deidentifier_base
    assert stanford.entities == [:person, :organization, :location, :phone, :date_time]
    assert stanford.license == "MIT"
    assert stanford.required? == false
    assert stanford.status == :experimental
    assert stanford.policy[:labels_to_ignore] == ["O", "ID"]
    assert stanford.policy[:low_score_entity_names] == ["ID"]
    assert stanford.policy[:low_confidence_score_multiplier] == 0.4
    assert stanford.policy[:per_label_thresholds]["PATIENT"] == 0.72
    assert stanford.policy[:per_label_thresholds]["HOSPITAL"] == 0.9
    assert stanford.policy[:context_required_below_labels]["VENDOR"] == 0.98
    assert "hospital" in stanford.policy[:context_words_by_label]["HOSPITAL"]
    assert stanford.policy[:aggregation_strategy] == :max
    assert stanford.policy[:alignment_mode] == :expand
    assert stanford.policy[:stride] == 16

    assert {:ok, obi} = ModelRegistry.fetch(:obi_deid_roberta_i2b2)
    assert obi.model == {:hf, "obi/deid_roberta_i2b2"}
    assert obi.tokenizer == {:hf, "obi/deid_roberta_i2b2"}
    assert obi.aggregation == :same
    assert obi.label_map == :obi_deid_roberta_i2b2
    assert obi.license == "MIT"
    assert obi.required? == false
    assert "U-ID" in obi.policy[:labels_to_ignore]
    assert obi.policy[:per_label_thresholds]["PATORG"] == 0.94
    assert "works at" in obi.policy[:context_words_by_label]["PATORG"]

    assert {:ok, piiranha} = ModelRegistry.fetch(:piiranha_v1)
    assert piiranha.model == {:hf, "iiiorg/piiranha-v1-detect-personal-information"}
    assert piiranha.label_map == :piiranha_v1
    assert piiranha.license == "cc-by-nc-nd-4.0"
    assert piiranha.status == :experimental
    assert :person in piiranha.entities
    assert :street_address in piiranha.entities
    assert :password in piiranha.entities
    refute :organization in piiranha.entities
  end

  test "normalizes V10 real model candidate specs" do
    assert {:ok, ab_ai} = ModelRegistry.fetch(:ab_ai_pii_model)
    assert ab_ai.model == {:hf, "ab-ai/pii_model"}
    assert ab_ai.tokenizer == {:hf, "ab-ai/pii_model"}
    assert ab_ai.label_map == :ab_ai_pii_model
    assert ab_ai.license == "apache-2.0"
    assert :credit_card in ab_ai.entities

    assert {:ok, ar86bat} = ModelRegistry.fetch(:ar86bat_multilang_pii_ner)
    assert ar86bat.model == {:hf, "Ar86Bat/multilang-pii-ner"}
    assert ar86bat.tokenizer == {:hf, "Ar86Bat/multilang-pii-ner"}
    assert ar86bat.label_map == :ar86bat_multilang_pii_ner
    assert ar86bat.license == "MIT"

    assert {:ok, isotonic} = ModelRegistry.fetch(:isotonic_distilbert_ai4privacy_v2)
    assert isotonic.model == {:hf, "Isotonic/distilbert_finetuned_ai4privacy_v2"}
    assert isotonic.tokenizer == {:hf, "Isotonic/distilbert_finetuned_ai4privacy_v2"}
    assert isotonic.label_map == :isotonic_distilbert_ai4privacy_v2

    assert isotonic.entities == [:person, :organization, :location]

    assert isotonic.license == "cc-by-nc-4.0"
    assert isotonic.required? == false
    assert isotonic.status == :experimental
    assert isotonic.policy[:per_label_thresholds]["COMPANYNAME"] == 0.98
    assert isotonic.policy[:per_label_thresholds]["STREET"] == 0.96
    assert isotonic.policy[:context_required_below_labels]["COMPANYNAME"] == 0.99
    assert isotonic.policy[:context_required_below_labels]["ZIPCODE"] == 0.99
    assert isotonic.policy[:validate_structured_model_entities] == true
    assert "B-GENDER" in isotonic.policy[:labels_to_ignore]
    assert "I-VEHICLEVIN" in isotonic.policy[:labels_to_ignore]
    assert "B-EMAIL" in isotonic.policy[:labels_to_ignore]
    assert "I-PHONENUMBER" in isotonic.policy[:labels_to_ignore]
    assert "URL" in isotonic.policy[:labels_to_ignore]

    assert {:ok, dbmdz} = ModelRegistry.fetch(:dbmdz_bert_large_conll03)
    assert dbmdz.model == {:hf, "dbmdz/bert-large-cased-finetuned-conll03-english"}
    assert dbmdz.tokenizer == {:hf, "google-bert/bert-large-cased"}
    assert dbmdz.label_map == :dbmdz_bert_large_conll03
    assert dbmdz.license == "unknown"
    assert dbmdz.policy[:per_entity_thresholds] == %{organization: 0.9}

    assert {:ok, davlan} = ModelRegistry.fetch(:davlan_xlm_roberta_large_ner_hrl)
    assert davlan.model == {:hf, "Davlan/xlm-roberta-large-ner-hrl"}
    assert davlan.tokenizer == {:hf, "FacebookAI/xlm-roberta-large"}
    assert davlan.label_map == :davlan_xlm_roberta_large_ner_hrl
    assert davlan.license == "unknown"
    assert davlan.policy[:per_label_thresholds] == %{"PER" => 0.72, "ORG" => 0.98, "LOC" => 0.92}
    assert davlan.policy[:context_required_below_labels] == %{"ORG" => 0.99, "LOC" => 0.96}
    assert "MISC" in davlan.policy[:labels_to_ignore]

    assert {:ok, wikiann} = ModelRegistry.fetch(:davlan_xlm_roberta_base_wikiann_ner)
    assert wikiann.model == {:hf, "Davlan/xlm-roberta-base-wikiann-ner"}
    assert wikiann.tokenizer == {:hf, "Davlan/xlm-roberta-base-wikiann-ner"}
    assert wikiann.label_map == :davlan_xlm_roberta_base_wikiann_ner
    assert wikiann.entities == [:person, :organization, :location]
    assert wikiann.license == "unknown"
    assert wikiann.required? == false
    assert wikiann.status == :experimental

    assert wikiann.policy[:per_label_thresholds] == %{
             "PER" => 0.72,
             "ORG" => 0.98,
             "LOC" => 0.92
           }

    assert wikiann.policy[:context_required_below_labels] == %{"ORG" => 0.99, "LOC" => 0.96}
    assert wikiann.policy[:labels_to_ignore] == ["DATE", "B-DATE", "I-DATE"]
    refute "MISC" in wikiann.policy[:labels_to_ignore]

    assert {:ok, facebook} = ModelRegistry.fetch(:facebook_xlm_roberta_large_conll03_english)
    assert facebook.model == {:hf, "FacebookAI/xlm-roberta-large-finetuned-conll03-english"}
    assert facebook.tokenizer == {:hf, "FacebookAI/xlm-roberta-large-finetuned-conll03-english"}
    assert facebook.label_map == :facebook_xlm_roberta_large_conll03_english
    assert facebook.entities == [:person, :organization, :location]
    assert facebook.license == "unknown"
    assert facebook.required? == false
    assert facebook.status == :experimental

    assert facebook.policy[:per_label_thresholds] == %{
             "PER" => 0.72,
             "ORG" => 0.98,
             "LOC" => 0.92
           }

    assert facebook.policy[:context_required_below_labels] == %{"ORG" => 0.99, "LOC" => 0.96}
    assert "MISC" in facebook.policy[:labels_to_ignore]

    assert {:ok, tner} = ModelRegistry.fetch(:tner_roberta_large_ontonotes5)

    assert tner.model ==
             {:hf, "tner/roberta-large-ontonotes5",
              revision: "0bce50f7884d5bb040469c907c897d4b061ccbb4"}

    assert tner.tokenizer ==
             {:hf, "tner/roberta-large-ontonotes5",
              revision: "0bce50f7884d5bb040469c907c897d4b061ccbb4"}

    assert tner.label_map == :tner_roberta_large_ontonotes5
    assert tner.license == "unknown"
    assert tner.policy[:per_entity_thresholds] == %{organization: 0.95, location: 0.8}

    assert tner.policy[:per_label_thresholds] == %{
             "PERSON" => 0.72,
             "ORG" => 0.98,
             "GPE" => 0.9,
             "LOC" => 0.92,
             "FAC" => 0.97
           }

    assert tner.policy[:context_required_below_labels] == %{
             "ORG" => 0.99,
             "LOC" => 0.96,
             "FAC" => 0.99
           }

    assert tner.policy[:context_required_labels] == ["FAC"]

    assert tner.policy[:context_words_by_label]["FAC"] == [
             "airport",
             "building",
             "campus",
             "facility",
             "headquarters",
             "hospital",
             "office"
           ]

    assert tner.policy[:weak_context_words_by_label] == %{"FAC" => ["in"]}
    assert "invoice" in tner.policy[:negative_context_words_by_label]["GPE"]
    assert tner.policy[:negative_context_reject_labels] == ["GPE"]
    assert "B-DATE" in tner.policy[:labels_to_ignore]

    assert {:ok, learnrr} = ModelRegistry.fetch(:learnrr_roberta_large_ontonotes5_ner)
    assert learnrr.model == {:hf, "learnrr/roberta-large-ontonotes5-ner"}
    assert learnrr.tokenizer == {:hf, "learnrr/roberta-large-ontonotes5-ner"}
    assert learnrr.label_map == :learnrr_roberta_large_ontonotes5_ner
    assert learnrr.license == "MIT"
    assert learnrr.policy[:per_label_thresholds] == tner.policy[:per_label_thresholds]
    assert learnrr.policy[:context_required_labels] == ["FAC"]
  end

  test "normalizes V20 model candidate specs" do
    assert {:ok, base} = ModelRegistry.fetch(:learnrr_bert_base_ontonotes5_ner)
    assert base.model == {:hf, "learnrr/bert-base-ontonotes5-ner"}
    assert base.tokenizer == {:hf, "learnrr/bert-base-ontonotes5-ner"}
    assert base.label_map == :learnrr_bert_base_ontonotes5_ner
    assert base.license == "MIT"
    assert base.policy[:per_label_thresholds]["GPE"] == 0.9
    assert "B-DATE" in base.policy[:labels_to_ignore]

    assert {:ok, large} = ModelRegistry.fetch(:learnrr_bert_large_ontonotes5_ner)
    assert large.model == {:hf, "learnrr/bert-large-ontonotes5-ner"}
    assert large.tokenizer == {:hf, "learnrr/bert-large-ontonotes5-ner"}
    assert large.label_map == :learnrr_bert_large_ontonotes5_ner
    assert large.policy[:per_label_thresholds] == base.policy[:per_label_thresholds]
    assert large.policy[:context_required_labels] == ["FAC"]

    assert {:ok, nickprock} = ModelRegistry.fetch(:nickprock_bert_finetuned_ner_ontonotes)
    assert nickprock.model == {:hf, "nickprock/bert-finetuned-ner-ontonotes"}
    assert nickprock.tokenizer == {:hf, "nickprock/bert-finetuned-ner-ontonotes"}
    assert nickprock.label_map == :nickprock_bert_finetuned_ner_ontonotes
    assert nickprock.entities == [:person, :organization, :location]
    assert nickprock.license == "apache-2.0"
    assert nickprock.required? == false
    assert nickprock.status == :experimental
    assert nickprock.policy[:per_label_thresholds] == base.policy[:per_label_thresholds]
    assert nickprock.policy[:context_required_labels] == ["FAC"]
    assert "B-DATE" in nickprock.policy[:labels_to_ignore]

    assert {:ok, roberta} = ModelRegistry.fetch(:jean_baptiste_roberta_large_ner_english)

    assert roberta.model ==
             {:hf, "Jean-Baptiste/roberta-large-ner-english",
              revision: "8f3abc1ef81ffbbb0e80568d4fed1dd10d459548"}

    assert roberta.tokenizer ==
             {:hf, "FacebookAI/roberta-large",
              revision: "722cf37b1afa9454edce342e7895e588b6ff1d59"}

    assert roberta.label_map == :jean_baptiste_roberta_large_ner_english
    assert roberta.policy[:per_label_thresholds] == %{"PER" => 0.72, "ORG" => 0.98, "LOC" => 0.92}
    assert "MISC" in roberta.policy[:labels_to_ignore]
  end

  test "maps Davlan WikiANN labels and leaves DATE unsupported for targeted validation" do
    assert LabelMap.to_entity("B-PER", label_map: :davlan_xlm_roberta_base_wikiann_ner) ==
             {:ok, :person}

    assert LabelMap.to_entity("I-ORG", label_map: :davlan_xlm_roberta_base_wikiann_ner) ==
             {:ok, :organization}

    assert LabelMap.to_entity("LOC", label_map: :davlan_xlm_roberta_base_wikiann_ner) ==
             {:ok, :location}

    assert LabelMap.to_entity("B-DATE", label_map: :davlan_xlm_roberta_base_wikiann_ner) ==
             {:error, {:unknown_model_label, "B-DATE"}}
  end

  test "normalizes V11 leaderboard model candidate specs" do
    assert {:ok, privacy_filter} = ModelRegistry.fetch(:openai_privacy_filter)
    assert privacy_filter.model == {:hf, "openai/privacy-filter"}
    assert privacy_filter.tokenizer == {:hf, "openai/privacy-filter"}
    assert privacy_filter.label_map == :openai_privacy_filter
    assert privacy_filter.license == "apache-2.0"
    assert privacy_filter.required? == false
    assert :email in privacy_filter.entities

    assert {:ok, nemotron} = ModelRegistry.fetch(:openmed_privacy_filter_nemotron)
    assert nemotron.model == {:hf, "OpenMed/privacy-filter-nemotron"}
    assert nemotron.tokenizer == {:hf, "OpenMed/privacy-filter-nemotron"}
    assert nemotron.label_map == :openmed_privacy_filter_nemotron
    assert nemotron.license == "apache-2.0"
    assert :patient_id in nemotron.entities

    assert {:ok, small} = ModelRegistry.fetch(:openmed_pii_superclinical_small)
    assert small.model == {:hf, "OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1"}
    assert small.label_map == :openmed_pii_superclinical_small

    assert {:ok, large} = ModelRegistry.fetch(:openmed_pii_superclinical_large)
    assert large.model == {:hf, "OpenMed/OpenMed-PII-SuperClinical-Large-434M-v1"}
    assert large.label_map == :openmed_pii_superclinical_large
    assert large.policy[:per_label_thresholds]["company_name"] == 0.98
    assert large.policy[:validate_structured_model_entities] == true

    assert {:ok, bigmed} = ModelRegistry.fetch(:openmed_pii_bigmed_large)
    assert bigmed.model == {:hf, "OpenMed/OpenMed-PII-BigMed-Large-560M-v1"}
    assert bigmed.label_map == :openmed_pii_bigmed_large
    assert "private_address" in bigmed.policy[:labels_to_ignore]
    assert bigmed.policy[:validate_structured_model_entities] == true
  end

  test "normalizes explicit Hugging Face model ids with explicit label maps" do
    assert {:ok, spec} =
             ModelRegistry.fetch({:hf, "dslim/bert-base-NER"},
               tokenizer: {:hf, "google-bert/bert-base-cased"},
               label_map: :dslim_bert_base_ner
             )

    assert spec.model == {:hf, "dslim/bert-base-NER"}
    assert spec.label_map == :dslim_bert_base_ner
  end

  test "maps dslim labels and ignores MISC by default" do
    assert {:ok, :person} = LabelMap.to_entity("PER", label_map: :dslim_bert_base_ner)
    assert {:ok, :organization} = LabelMap.to_entity("B-ORG", label_map: :dslim_bert_base_ner)
    assert {:ok, :location} = LabelMap.to_entity("I-LOC", label_map: :dslim_bert_base_ner)

    assert {:error, {:unknown_model_label, "MISC"}} =
             LabelMap.to_entity("MISC", label_map: :dslim_bert_base_ner)
  end

  test "maps Presidio transformer labels without accepting unsupported ID and AGE labels" do
    assert {:ok, :person} =
             LabelMap.to_entity("PATIENT", label_map: :stanford_deidentifier_base)

    assert {:ok, :location} =
             LabelMap.to_entity("FACILITY", label_map: :stanford_deidentifier_base)

    assert {:ok, :organization} =
             LabelMap.to_entity("VENDOR", label_map: :obi_deid_roberta_i2b2)

    assert {:ok, :organization} =
             LabelMap.to_entity("U-PATORG", label_map: :obi_deid_roberta_i2b2)

    assert {:ok, :location} =
             LabelMap.to_entity("U-HOSP", label_map: :obi_deid_roberta_i2b2)

    assert {:ok, :date_time} =
             LabelMap.to_entity("L-DATE", label_map: :obi_deid_roberta_i2b2)

    assert {:error, {:unknown_model_label, "AGE"}} =
             LabelMap.to_entity("AGE", label_map: :stanford_deidentifier_base)

    assert {:error, {:unknown_model_label, "ID"}} =
             LabelMap.to_entity("ID", label_map: :obi_deid_roberta_i2b2)
  end

  test "maps V10 PII and BERT-large labels" do
    assert {:ok, :person} = LabelMap.to_entity("B-FIRSTNAME", label_map: :ab_ai_pii_model)

    assert {:ok, :credit_card} =
             LabelMap.to_entity("CREDITCARDNUMBER", label_map: :ab_ai_pii_model)

    assert {:ok, :url} = LabelMap.to_entity("I-URL", label_map: :ab_ai_pii_model)

    assert {:ok, :person} =
             LabelMap.to_entity("B-GIVENNAME", label_map: :ar86bat_multilang_pii_ner)

    assert {:ok, :phone} =
             LabelMap.to_entity("I-TELEPHONENUM", label_map: :ar86bat_multilang_pii_ner)

    assert {:ok, :location} =
             LabelMap.to_entity("B-CITY", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:ok, :location} =
             LabelMap.to_entity("I-STATE", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:ok, :organization} =
             LabelMap.to_entity("B-COMPANYNAME", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:ok, :person} =
             LabelMap.to_entity("B-FIRSTNAME", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:ok, :person} =
             LabelMap.to_entity("I-LASTNAME", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:ok, :location} =
             LabelMap.to_entity("B-STREET", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:ok, :location} =
             LabelMap.to_entity("B-ZIPCODE", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:ok, :location} =
             LabelMap.to_entity("B-LOC", label_map: :dbmdz_bert_large_conll03)

    assert {:ok, :person} =
             LabelMap.to_entity("B-PER", label_map: :dslim_bert_large_ner)

    assert {:ok, :person} =
             LabelMap.to_entity("I-PER", label_map: :dslim_bert_large_ner)

    assert {:ok, :organization} =
             LabelMap.to_entity("B-ORG", label_map: :dslim_bert_large_ner)

    assert {:ok, :organization} =
             LabelMap.to_entity("I-ORG", label_map: :dslim_bert_large_ner)

    assert {:ok, :location} =
             LabelMap.to_entity("B-LOC", label_map: :dslim_bert_large_ner)

    assert {:ok, :location} =
             LabelMap.to_entity("I-LOC", label_map: :dslim_bert_large_ner)

    assert {:error, {:unknown_model_label, "MISC"}} =
             LabelMap.to_entity("MISC", label_map: :dslim_bert_large_ner)

    assert {:error, {:unknown_model_label, "B-MISC"}} =
             LabelMap.to_entity("B-MISC", label_map: :dslim_bert_large_ner)

    assert {:error, {:unknown_model_label, "I-MISC"}} =
             LabelMap.to_entity("I-MISC", label_map: :dslim_bert_large_ner)

    assert {:ok, :person} =
             LabelMap.to_entity("B-PER", label_map: :davlan_xlm_roberta_large_ner_hrl)

    assert {:ok, :organization} =
             LabelMap.to_entity("I-ORG", label_map: :davlan_xlm_roberta_large_ner_hrl)

    assert {:ok, :location} =
             LabelMap.to_entity("LOC", label_map: :davlan_xlm_roberta_large_ner_hrl)

    assert {:ok, :person} =
             LabelMap.to_entity("I-PER", label_map: :facebook_xlm_roberta_large_conll03_english)

    assert {:ok, :organization} =
             LabelMap.to_entity("B-ORG", label_map: :facebook_xlm_roberta_large_conll03_english)

    assert {:ok, :location} =
             LabelMap.to_entity("I-LOC", label_map: :facebook_xlm_roberta_large_conll03_english)

    assert {:ok, :person} =
             LabelMap.to_entity("B-PERSON", label_map: :tner_roberta_large_ontonotes5)

    assert {:ok, :location} =
             LabelMap.to_entity("I-GPE", label_map: :tner_roberta_large_ontonotes5)

    assert {:ok, :location} =
             LabelMap.to_entity("B-FAC", label_map: :tner_roberta_large_ontonotes5)

    assert {:ok, :organization} =
             LabelMap.to_entity("B-ORG", label_map: :learnrr_roberta_large_ontonotes5_ner)

    assert {:ok, :location} =
             LabelMap.to_entity("I-GPE", label_map: :learnrr_roberta_large_ontonotes5_ner)

    assert {:ok, :person} =
             LabelMap.to_entity("B-PERSON", label_map: :learnrr_bert_base_ontonotes5_ner)

    assert {:ok, :location} =
             LabelMap.to_entity("B-FAC", label_map: :learnrr_bert_large_ontonotes5_ner)

    assert {:ok, :person} =
             LabelMap.to_entity("I-PERSON", label_map: :nickprock_bert_finetuned_ner_ontonotes)

    assert {:ok, :organization} =
             LabelMap.to_entity("B-ORG", label_map: :nickprock_bert_finetuned_ner_ontonotes)

    assert {:ok, :location} =
             LabelMap.to_entity("B-GPE", label_map: :nickprock_bert_finetuned_ner_ontonotes)

    assert {:ok, :location} =
             LabelMap.to_entity("I-FAC", label_map: :nickprock_bert_finetuned_ner_ontonotes)

    assert {:ok, :organization} =
             LabelMap.to_entity("ORG", label_map: :jean_baptiste_roberta_large_ner_english)

    assert {:ok, :location} =
             LabelMap.to_entity("LOC", label_map: :jean_baptiste_roberta_large_ner_english)

    assert {:error, {:unknown_model_label, "B-DATE"}} =
             LabelMap.to_entity("B-DATE", label_map: :tner_roberta_large_ontonotes5)

    assert {:error, {:unknown_model_label, "MISC"}} =
             LabelMap.to_entity("MISC", label_map: :jean_baptiste_roberta_large_ner_english)

    assert {:error, {:unknown_model_label, "MISC"}} =
             LabelMap.to_entity("MISC", label_map: :davlan_xlm_roberta_large_ner_hrl)

    assert {:error, {:unknown_model_label, "MISC"}} =
             LabelMap.to_entity("MISC", label_map: :facebook_xlm_roberta_large_conll03_english)

    assert {:error, {:unknown_model_label, "B-DATE"}} =
             LabelMap.to_entity("B-DATE", label_map: :nickprock_bert_finetuned_ner_ontonotes)

    assert {:error, {:unknown_model_label, "AGE"}} =
             LabelMap.to_entity("AGE", label_map: :ar86bat_multilang_pii_ner)

    assert {:error, {:unknown_model_label, "B-GENDER"}} =
             LabelMap.to_entity("B-GENDER", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:error, {:unknown_model_label, "B-VEHICLEVIN"}} =
             LabelMap.to_entity("B-VEHICLEVIN", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:error, {:unknown_model_label, "B-CURRENCY"}} =
             LabelMap.to_entity("B-CURRENCY", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:error, {:unknown_model_label, "B-EMAIL"}} =
             LabelMap.to_entity("B-EMAIL", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:error, {:unknown_model_label, "I-PHONENUMBER"}} =
             LabelMap.to_entity("I-PHONENUMBER", label_map: :isotonic_distilbert_ai4privacy_v2)

    assert {:error, {:unknown_model_label, "URL"}} =
             LabelMap.to_entity("URL", label_map: :isotonic_distilbert_ai4privacy_v2)
  end

  test "maps V11 leaderboard labels without accepting unsupported labels" do
    assert {:ok, :person} =
             LabelMap.to_entity("S-private_person", label_map: :openai_privacy_filter)

    assert {:ok, :email} =
             LabelMap.to_entity("B-private_email", label_map: :openai_privacy_filter)

    assert {:error, {:unknown_model_label, "S-secret"}} =
             LabelMap.to_entity("S-secret", label_map: :openai_privacy_filter)

    assert {:ok, :person} =
             LabelMap.to_entity("B-first_name", label_map: :openmed_privacy_filter_nemotron)

    assert {:ok, :phone} =
             LabelMap.to_entity("I-phone_number", label_map: :openmed_pii_superclinical_small)

    assert {:ok, :credit_card} =
             LabelMap.to_entity("B-credit_debit_card",
               label_map: :openmed_pii_superclinical_large
             )

    assert {:ok, :ip_address} =
             LabelMap.to_entity("B-ipv4", label_map: :openmed_pii_bigmed_large)

    assert {:ok, :patient_id} =
             LabelMap.to_entity("B-medical_record_number", label_map: :openmed_pii_bigmed_large)

    assert {:error, {:unknown_model_label, "B-age"}} =
             LabelMap.to_entity("B-age", label_map: :openmed_pii_bigmed_large)
  end

  test "maps every Piiranha PII label and rejects invented generic NER labels" do
    expected = %{
      "I-ACCOUNTNUM" => :id,
      "I-BUILDINGNUM" => :street_address,
      "I-CITY" => :location,
      "I-CREDITCARDNUMBER" => :credit_card,
      "I-DATEOFBIRTH" => :date_time,
      "I-DRIVERLICENSENUM" => :us_driver_license,
      "I-EMAIL" => :email,
      "I-GIVENNAME" => :person,
      "I-IDCARDNUM" => :id,
      "I-PASSWORD" => :password,
      "I-SOCIALNUM" => :us_ssn,
      "I-STREET" => :street_address,
      "I-SURNAME" => :person,
      "I-TAXNUM" => :id,
      "I-TELEPHONENUM" => :phone,
      "I-USERNAME" => :username,
      "I-ZIPCODE" => :zip_code
    }

    for {label, entity} <- expected do
      assert LabelMap.to_entity(label, label_map: :piiranha_v1) == {:ok, entity}

      assert LabelMap.to_entity(String.replace_prefix(label, "I-", ""),
               label_map: :piiranha_v1
             ) == {:ok, entity}
    end

    assert LabelMap.to_entity("I-PER", label_map: :piiranha_v1) ==
             {:error, {:unknown_model_label, "I-PER"}}

    assert LabelMap.to_entity("I-ORG", label_map: :piiranha_v1) ==
             {:error, {:unknown_model_label, "I-ORG"}}
  end
end
