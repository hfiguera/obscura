defmodule Obscura.Eval.PresidioCompatibilityTest do
  use ExUnit.Case, async: false

  alias Obscura.Eval.PresidioCompatibility
  alias Obscura.Eval.PresidioResearchLoader

  test "accuracy output fingerprints are canonical across prediction order" do
    first = %{
      sample: %{id: 1},
      predicted: [
        %{
          entity: :person,
          byte_start: 0,
          byte_end: 3,
          score: 1.0,
          metadata: %{recognizer: :privacy_filter_native, model_label: "private_person"}
        },
        %{
          entity: :location,
          byte_start: 7,
          byte_end: 12,
          score: 1.0,
          metadata: %{model_label: "city", recognizer: :privacy_filter_native}
        }
      ]
    }

    second = %{first | predicted: Enum.reverse(first.predicted)}

    assert PresidioCompatibility.output_fingerprint([first]) ==
             PresidioCompatibility.output_fingerprint([second])
  end

  test "runs a CI-safe compatibility smoke against generated_small when present" do
    {:ok, path} = PresidioResearchLoader.path_for(:generated_small)

    if File.exists?(path) do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :regex_only,
                 limit: 3
               )

      assert report.run_id == "presidio_compatibility_generated_small_regex_only_smoke"
      assert report.phase == "presidio_compatibility"
      assert report.dataset.name == "generated_small"
      assert report.dataset.sample_count == 3
      assert report.dataset.smoke == true
      assert report.dataset.template_summary.template_count >= 1
      assert Map.has_key?(report.metrics, :offset_mismatches)
      assert byte_size(report.metrics.output_fingerprint_sha256) == 64
      assert report.metrics.unsupported_expected_spans >= 0

      unsupported_examples =
        report.metrics.error_buckets.unsupported
        |> Enum.flat_map(fn {_entity, bucket} -> bucket.examples end)

      assert Enum.any?(unsupported_examples, &Map.has_key?(&1.metadata, :sample_id))
    else
      assert {:error, {:missing_presidio_research_dataset, ^path, :enoent}} =
               PresidioCompatibility.run(dataset: :generated_small, profile: :regex_only)
    end
  end

  test "entity-scoped runs exclude predictions outside the requested policy" do
    assert {:ok, report} =
             PresidioCompatibility.run(
               dataset: :generated_small,
               profile: :deterministic_plus,
               entities: [:email],
               full: true
             )

    assert report.dataset.requested_entities == [:email]
    assert Map.keys(report.per_entity) == ["email"]
  end

  test "writes a skipped real-model report without model opt-in" do
    previous = System.get_env("OBSCURA_EVAL_REAL_MODEL")
    System.delete_env("OBSCURA_EVAL_REAL_MODEL")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :real_ner,
                 real_model: false
               )

      assert report.dataset.status == "skipped"
      assert report.run_id == "presidio_compatibility_generated_small_real_ner_skipped"
      assert report.model.model_alias == :dslim_bert_base_ner
    after
      if previous, do: System.put_env("OBSCURA_EVAL_REAL_MODEL", previous)
    end
  end

  test "writes a skipped hybrid NER report without model opt-in" do
    previous = System.get_env("OBSCURA_EVAL_REAL_MODEL")
    System.delete_env("OBSCURA_EVAL_REAL_MODEL")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :hybrid_ner,
                 real_model: false
               )

      assert report.dataset.status == "skipped"
      assert report.run_id == "presidio_compatibility_generated_small_hybrid_ner_skipped"
      assert report.model.model_alias == :dslim_bert_base_ner
      assert report.metrics.span_iou.iou_threshold == 0.9
    after
      if previous, do: System.put_env("OBSCURA_EVAL_REAL_MODEL", previous)
    end
  end

  test "stable balanced profile fixes its TNER model contract" do
    previous = System.get_env("OBSCURA_EVAL_REAL_MODEL")
    System.delete_env("OBSCURA_EVAL_REAL_MODEL")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :balanced,
                 model: :dslim_bert_base_ner,
                 real_model: false
               )

      assert report.dataset.status == "skipped"
      assert report.requested_profile == "balanced"
      assert report.resolved_profile == "hybrid_ner_tner_conservative"
      assert report.model.model_alias == :tner_roberta_large_ontonotes5
      assert report.model.model_id == "tner/roberta-large-ontonotes5"
    after
      if previous do
        System.put_env("OBSCURA_EVAL_REAL_MODEL", previous)
      else
        System.delete_env("OBSCURA_EVAL_REAL_MODEL")
      end
    end
  end

  test "experimental OpenMed profile fixes its model identity contract" do
    previous_opt_in = System.get_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
    previous_checkpoint = System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    System.delete_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
    System.delete_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :openmed_pii,
                 privacy_filter_model_id: "OpenMed/privacy-filter-nemotron",
                 privacy_filter_native: false
               )

      assert report.dataset.status == "skipped"
      assert report.requested_profile == "openmed_pii"
      assert report.resolved_profile == "privacy_filter_native"
      assert report.model.model_id == "OpenMed/privacy-filter-nemotron-v2"
      assert report.model.optimization_policy.matches_default
      assert report.model.optimization_policy.sequence_length_buckets == [192, 256, 384, 512, 768]
      assert report.model.optimization_policy.sequence_length_bucket_threshold == 129
      assert report.model.optimization_policy.logprob_conversion == :raw_logits
    after
      if previous_opt_in do
        System.put_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE", previous_opt_in)
      else
        System.delete_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
      end

      if previous_checkpoint do
        System.put_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT", previous_checkpoint)
      else
        System.delete_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
      end
    end
  end

  test "writes a skipped org-enabled hybrid NER report without model opt-in" do
    previous = System.get_env("OBSCURA_EVAL_REAL_MODEL")
    System.delete_env("OBSCURA_EVAL_REAL_MODEL")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :hybrid_ner_org,
                 real_model: false
               )

      assert report.dataset.status == "skipped"
      assert report.run_id == "presidio_compatibility_generated_small_hybrid_ner_org_skipped"
      assert report.model.model_alias == :dslim_bert_base_ner
    after
      if previous, do: System.put_env("OBSCURA_EVAL_REAL_MODEL", previous)
    end
  end

  test "writes a skipped hybrid GLiNER report without GLiNER opt-in" do
    previous = System.get_env("OBSCURA_EVAL_GLINER_ORTEX")
    System.delete_env("OBSCURA_EVAL_GLINER_ORTEX")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :hybrid_gliner_ortex,
                 gliner_ortex: false
               )

      assert report.dataset.status == "skipped"
      assert report.run_id == "presidio_compatibility_generated_small_hybrid_gliner_ortex_skipped"
      assert Enum.any?(report.limitations, &String.contains?(&1, "GLiNER Ortex opt-in"))
    after
      if previous, do: System.put_env("OBSCURA_EVAL_GLINER_ORTEX", previous)
    end
  end

  test "writes a skipped native GLiNER report without opt-in" do
    previous = System.get_env("OBSCURA_EVAL_GLINER_NATIVE")
    System.delete_env("OBSCURA_EVAL_GLINER_NATIVE")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :hybrid_gliner_urchade_native,
                 gliner_native: false
               )

      assert report.dataset.status == "skipped"

      assert report.run_id ==
               "presidio_compatibility_generated_small_hybrid_gliner_urchade_native_skipped"

      assert report.skip_reason.category == "opt_in_missing"
      assert report.skip_reason.profile == "hybrid_gliner_urchade_native"
      assert report.skip_reason.message == "Native GLiNER opt-in missing."
      assert Enum.any?(report.limitations, &String.contains?(&1, "Native GLiNER opt-in"))
    after
      if previous,
        do: System.put_env("OBSCURA_EVAL_GLINER_NATIVE", previous),
        else: System.delete_env("OBSCURA_EVAL_GLINER_NATIVE")
    end
  end

  test "writes a skipped native privacy-filter report without opt-in" do
    previous_opt_in = System.get_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
    previous_checkpoint = System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    System.delete_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
    System.delete_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :privacy_filter_native,
                 privacy_filter_native: false,
                 privacy_filter_model_id: "OpenMed/privacy-filter-nemotron"
               )

      assert report.dataset.status == "skipped"

      assert report.run_id ==
               "presidio_compatibility_generated_small_privacy_filter_native_skipped"

      assert report.model.model_id == "OpenMed/privacy-filter-nemotron"
      assert report.model.n_ctx == "auto"
      assert report.model.pad_windows == false
      assert report.model.decoder == :viterbi
      assert report.model.label_map_mode == :presidio_research
      assert report.recognizer_execution.built_ins == false
      assert report.recognizer_execution.mode == :custom_recognizers_only
      assert report.runtime_backend.model_id_env == "OBSCURA_PRIVACY_FILTER_MODEL_ID"
      assert report.skip_reason.category == "opt_in_missing"
      assert report.skip_reason.profile == "privacy_filter_native"
      assert report.skip_reason.message == "Native privacy-filter opt-in missing."
      assert Enum.any?(report.limitations, &String.contains?(&1, "privacy-filter opt-in"))
    after
      if previous_opt_in,
        do: System.put_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE", previous_opt_in)

      if previous_checkpoint,
        do: System.put_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT", previous_checkpoint)
    end
  end

  test "writes a skipped native privacy-filter report when checkpoint validation fails" do
    previous_opt_in = System.get_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
    previous_checkpoint = System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    checkpoint = Path.join(System.tmp_dir!(), "obscura-missing-privacy-filter")
    File.rm_rf!(checkpoint)

    System.put_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE", "1")
    System.delete_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :privacy_filter_native,
                 privacy_filter_checkpoint: checkpoint,
                 privacy_filter_native: true,
                 privacy_filter_n_ctx: 64,
                 privacy_filter_pad_windows: true,
                 privacy_filter_decoder: :argmax
               )

      assert report.dataset.status == "skipped"

      assert Enum.any?(
               report.limitations,
               &String.contains?(&1, "Native privacy-filter compatibility run failed")
             )

      assert report.model.checkpoint == checkpoint
      assert report.model.n_ctx == 64
      assert report.model.pad_windows == true
      assert report.model.decoder == :argmax
      assert report.runtime_backend.adapter == :native_privacy_filter
      assert report.skip_reason.category == "run_failed"
      assert report.skip_reason.profile == "privacy_filter_native"
      assert report.skip_reason.message =~ "Native privacy-filter compatibility run failed"
      assert report.skip_reason.message =~ "checkpoint_dir_not_found"
    after
      if previous_opt_in do
        System.put_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE", previous_opt_in)
      else
        System.delete_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
      end

      if previous_checkpoint do
        System.put_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT", previous_checkpoint)
      else
        System.delete_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
      end
    end
  end

  test "categorizes incomplete native privacy-filter checkpoint reports" do
    previous_opt_in = System.get_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
    previous_checkpoint = System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    checkpoint = tmp_dir!("obscura-incomplete-privacy-filter")

    File.write!(Path.join(checkpoint, "config.json"), Jason.encode!(privacy_filter_config()))

    safetensors_path = Path.join(checkpoint, "model.safetensors")
    Safetensors.write!(safetensors_path, %{"x" => Nx.tensor([[1.0, 2.0]])})
    contents = File.read!(safetensors_path)
    File.write!(safetensors_path, binary_part(contents, 0, byte_size(contents) - 1))

    System.put_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE", "1")
    System.delete_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :privacy_filter_native,
                 privacy_filter_checkpoint: checkpoint,
                 privacy_filter_native: true
               )

      assert report.dataset.status == "skipped"
      assert report.skip_reason.category == "checkpoint_incomplete"
      assert report.skip_reason.profile == "privacy_filter_native"
      assert report.skip_reason.message =~ "incomplete_safetensors_file"
    after
      if previous_opt_in do
        System.put_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE", previous_opt_in)
      else
        System.delete_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE")
      end

      if previous_checkpoint do
        System.put_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT", previous_checkpoint)
      else
        System.delete_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
      end
    end
  end

  test "threshold sweep skips cleanly without real model opt-in" do
    previous = System.get_env("OBSCURA_EVAL_REAL_MODEL")
    System.delete_env("OBSCURA_EVAL_REAL_MODEL")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run_threshold_sweep(
                 dataset: :generated_small,
                 profile: :hybrid_ner_org,
                 real_model: false,
                 thresholds: [0.7, 0.8]
               )

      assert report.dataset.status == "skipped"
      assert report.run_id == "presidio_compatibility_generated_small_hybrid_ner_org_skipped"
      assert Enum.any?(report.limitations, &String.contains?(&1, "Real local model opt-in"))
    after
      if previous, do: System.put_env("OBSCURA_EVAL_REAL_MODEL", previous)
    end
  end

  test "label-threshold sweep skips cleanly without real model opt-in" do
    previous = System.get_env("OBSCURA_EVAL_REAL_MODEL")
    System.delete_env("OBSCURA_EVAL_REAL_MODEL")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run_label_threshold_sweep(
                 dataset: :generated_small,
                 profile: :hybrid_ner_tner_conservative,
                 real_model: false
               )

      assert report.dataset.status == "skipped"

      assert report.run_id ==
               "presidio_compatibility_generated_small_hybrid_ner_tner_conservative_skipped"

      assert Enum.any?(report.limitations, &String.contains?(&1, "Real local model opt-in"))
    after
      if previous, do: System.put_env("OBSCURA_EVAL_REAL_MODEL", previous)
    end
  end

  test "policy sweep skips cleanly without real model opt-in" do
    previous = System.get_env("OBSCURA_EVAL_REAL_MODEL")
    System.delete_env("OBSCURA_EVAL_REAL_MODEL")

    try do
      assert {:ok, report} =
               PresidioCompatibility.run_policy_sweep(
                 dataset: :generated_small,
                 profile: :hybrid_ner_tner_conservative,
                 real_model: false
               )

      assert report.dataset.status == "skipped"

      assert report.run_id ==
               "presidio_compatibility_generated_small_hybrid_ner_tner_conservative_skipped"

      assert Enum.any?(report.limitations, &String.contains?(&1, "Real local model opt-in"))
    after
      if previous, do: System.put_env("OBSCURA_EVAL_REAL_MODEL", previous)
    end
  end

  test "label-threshold candidates vary one label at a time from the base policy" do
    candidates =
      PresidioCompatibility.label_threshold_candidates(
        [label_threshold_values: %{"GPE" => [0.84, 0.9], "FAC" => [0.92, 0.97]}],
        :hybrid_ner_tner_conservative
      )

    assert %{"PERSON" => 0.72, "ORG" => 0.98, "GPE" => 0.9, "LOC" => 0.92, "FAC" => 0.97} in candidates

    assert %{"PERSON" => 0.72, "ORG" => 0.98, "GPE" => 0.84, "LOC" => 0.92, "FAC" => 0.97} in candidates

    assert %{"PERSON" => 0.72, "ORG" => 0.98, "GPE" => 0.9, "LOC" => 0.92, "FAC" => 0.92} in candidates
  end

  test "label-threshold candidates can start from a model-specific policy" do
    serving = %{
      model_spec: %{
        policy: [
          per_label_thresholds: %{"PATIENT" => 0.72, "PATORG" => 0.94, "LOC" => 0.88}
        ]
      }
    }

    candidates =
      PresidioCompatibility.label_threshold_candidates(
        [label_threshold_values: %{"PATORG" => [0.9, 0.94]}],
        :hybrid_ner_tner_conservative,
        serving
      )

    assert %{"PATIENT" => 0.72, "PATORG" => 0.94, "LOC" => 0.88} in candidates
    assert %{"PATIENT" => 0.72, "PATORG" => 0.9, "LOC" => 0.88} in candidates
  end

  test "label-threshold candidates can start from V20 CoNLL model policy" do
    serving = %{
      model_spec: %{
        policy: [
          per_label_thresholds: %{"PER" => 0.72, "ORG" => 0.98, "LOC" => 0.92}
        ]
      }
    }

    candidates =
      PresidioCompatibility.label_threshold_candidates(
        [label_threshold_values: %{"ORG" => [0.94, 0.98], "LOC" => [0.88, 0.92]}],
        :hybrid_ner_tner_conservative,
        serving
      )

    assert %{"PER" => 0.72, "ORG" => 0.98, "LOC" => 0.92} in candidates
    assert %{"PER" => 0.72, "ORG" => 0.94, "LOC" => 0.92} in candidates
    assert %{"PER" => 0.72, "ORG" => 0.98, "LOC" => 0.88} in candidates
  end

  test "GLiNER label-threshold candidates vary only open-class labels from the base policy" do
    candidates =
      PresidioCompatibility.gliner_label_threshold_candidates(
        [
          label_threshold_values: %{
            "person" => [0.5, 0.55],
            "organization" => [0.5, 0.6],
            "location" => [0.45, 0.5]
          }
        ],
        :hybrid_gliner_ortex
      )

    assert %{"person" => 0.5, "organization" => 0.5, "location" => 0.5} in candidates
    assert %{"person" => 0.55, "organization" => 0.5, "location" => 0.5} in candidates
    assert %{"person" => 0.5, "organization" => 0.6, "location" => 0.5} in candidates
    assert %{"person" => 0.5, "organization" => 0.5, "location" => 0.45} in candidates
  end

  test "GLiNER label-threshold candidates follow the selected label profile" do
    candidates =
      PresidioCompatibility.gliner_label_threshold_candidates(
        [
          gliner_label_profile: :edge_open_class,
          gliner_threshold: 0.3,
          label_threshold_values: %{
            "name" => [0.3, 0.5],
            "location city" => [0.3, 0.5]
          }
        ],
        :hybrid_gliner_ortex
      )

    assert %{
             "name" => 0.3,
             "organization" => 0.3,
             "location" => 0.3,
             "location address" => 0.3,
             "location city" => 0.3,
             "location state" => 0.3,
             "location country" => 0.3
           } in candidates

    assert Enum.any?(candidates, &(Map.get(&1, "name") == 0.5))
    assert Enum.any?(candidates, &(Map.get(&1, "location city") == 0.5))
  end

  test "V21 policy candidates include named threshold, context, negative context, and boundary variants" do
    candidates =
      PresidioCompatibility.policy_candidates([], :hybrid_ner_tner_conservative)

    names = Enum.map(candidates, & &1.name)

    assert :v18_train_selected in names
    assert :org_context_recall in names
    assert :gpe_negative_context_extended in names
    assert :loc_context_recall in names
    assert :fac_required_context_balanced in names
    assert :boundary_conservative in names
    assert :organization_suffix_expansion in names
    assert :location_suffix_expansion in names
    assert :open_class_suffix_expansion in names
    assert :presidio_character_chunking in names
    assert :guarded_high_recall in names

    boundary = Enum.find(candidates, &(&1.name == :boundary_conservative))
    assert Keyword.fetch!(boundary.opts, :ner_boundary_normalization) == :conservative

    fac = Enum.find(candidates, &(&1.name == :fac_required_context_balanced))
    assert "FAC" in Keyword.fetch!(fac.opts, :ner_context_required_labels)

    suffix = Enum.find(candidates, &(&1.name == :open_class_suffix_expansion))

    assert Keyword.fetch!(suffix.opts, :ner_model_postprocessors) == [
             :organization_suffix_expansion,
             :location_suffix_expansion
           ]

    chunked = Enum.find(candidates, &(&1.name == :presidio_character_chunking))
    assert Keyword.fetch!(chunked.opts, :ner_model_chunking) == :character
    assert Keyword.fetch!(chunked.opts, :ner_model_chunk_size) == 400
    assert Keyword.fetch!(chunked.opts, :ner_model_chunk_overlap) == 40
  end

  test "V21 policy candidate options merge into runtime options" do
    candidate =
      []
      |> PresidioCompatibility.policy_candidates(:hybrid_ner_tner_conservative)
      |> Enum.find(&(&1.name == :guarded_high_recall))

    opts =
      PresidioCompatibility.policy_candidate_opts(
        [model: :tner_roberta_large_ontonotes5, real_model: true],
        candidate
      )

    assert opts[:model] == :tner_roberta_large_ontonotes5
    assert opts[:real_model] == true
    assert opts[:ner_per_label_thresholds]["ORG"] == 0.95
    assert opts[:ner_context_required_below_labels]["FAC"] == 0.99
    assert opts[:ner_negative_context_reject_labels] == ["GPE"]
  end

  test "V21 policy candidates do not add deterministic open-class recognizers" do
    candidates = PresidioCompatibility.policy_candidates([], :hybrid_ner_tner_conservative)

    assert Enum.all?(candidates, fn candidate ->
             candidate.opts
             |> Keyword.keys()
             |> Enum.all?(&(&1 |> to_string() |> String.starts_with?("ner_")))
           end)
  end

  test "FacebookAI organization profile uses a targeted policy candidate set" do
    candidates = PresidioCompatibility.policy_candidates([], :hybrid_ner_tner_facebookai_org)
    names = Enum.map(candidates, & &1.name)

    assert names == [
             :facebookai_org_current,
             :facebookai_org_threshold_099,
             :facebookai_org_threshold_0995,
             :facebookai_org_required_context_098,
             :facebookai_org_context_recall_096,
             :facebookai_org_conflict_higher_confidence,
             :facebookai_org_conflict_longer
           ]

    threshold_099 = Enum.find(candidates, &(&1.name == :facebookai_org_threshold_099))
    assert threshold_099.opts[:ner_per_label_thresholds]["ORG"] == 0.99

    required_context =
      Enum.find(candidates, &(&1.name == :facebookai_org_required_context_098))

    assert required_context.opts[:ner_context_required_labels] == ["ORG"]

    conflict_candidate =
      Enum.find(candidates, &(&1.name == :facebookai_org_conflict_higher_confidence))

    assert conflict_candidate.opts[:conflict_strategy] == :prefer_higher_confidence
  end

  test "TNER Jean-Baptiste location profile uses a fixed targeted policy candidate" do
    candidates = PresidioCompatibility.policy_candidates([], :hybrid_ner_tner_jean_location)

    assert [%{name: :tner_jean_location_current, opts: []}] = candidates
  end

  test "output-aware cascade exposes train-selectable policies and a TNER-only control" do
    candidates =
      PresidioCompatibility.policy_candidates(
        [],
        :hybrid_ner_tner_jean_location_cascade
      )

    assert [first | _rest] = candidates
    assert first.name == :cascade_disabled
    assert first.opts[:cascade_trigger] == :never

    assert Enum.any?(candidates, fn candidate ->
             candidate.name == :cascade_missing_0995 and
               candidate.opts[:cascade_secondary_threshold] == 0.995
           end)

    assert Enum.any?(candidates, fn candidate ->
             candidate.name == :cascade_uncertain_context_0995 and
               candidate.opts[:cascade_context_policy] == :strong_or_overlap
           end)
  end

  test "target-aware policy selector chooses by requested location and organization objective" do
    rows = [
      policy_row(:v18_train_selected,
        f1: 0.9,
        recall: 0.7,
        false_positives: 10,
        location: %{recall: 0.4, f1: 0.5, true_positives: 4, false_negatives: 6},
        organization: %{recall: 0.3, f1: 0.4, true_positives: 3, false_negatives: 7}
      ),
      policy_row(:target_recall,
        f1: 0.86,
        recall: 0.75,
        false_positives: 20,
        location: %{recall: 0.7, f1: 0.64, true_positives: 7, false_negatives: 3},
        organization: %{recall: 0.6, f1: 0.55, true_positives: 6, false_negatives: 4}
      )
    ]

    assert PresidioCompatibility.select_policy_row(rows,
             policy_selection_objective: :location_organization_recall
           ).policy_name == :target_recall

    assert PresidioCompatibility.select_policy_row(rows,
             policy_selection_objective: :location_organization_f1
           ).policy_name == :target_recall
  end

  test "target-aware policy selector can choose entity-specific F1 objectives" do
    rows = [
      policy_row(:balanced,
        f1: 0.9,
        location: %{recall: 0.7, f1: 0.7, true_positives: 7, false_negatives: 3},
        organization: %{
          recall: 0.4,
          f1: 0.5,
          true_positives: 4,
          false_positives: 1,
          false_negatives: 6
        }
      ),
      policy_row(:org_specialist,
        f1: 0.86,
        location: %{recall: 0.6, f1: 0.6, true_positives: 6, false_negatives: 4},
        organization: %{
          recall: 0.7,
          f1: 0.65,
          true_positives: 7,
          false_positives: 2,
          false_negatives: 3
        }
      ),
      policy_row(:location_specialist,
        f1: 0.85,
        location: %{recall: 0.8, f1: 0.75, true_positives: 8, false_negatives: 2},
        organization: %{
          recall: 0.35,
          f1: 0.45,
          true_positives: 3,
          false_positives: 0,
          false_negatives: 7
        }
      )
    ]

    assert PresidioCompatibility.select_policy_row(rows,
             policy_selection_objective: :organization_f1
           ).policy_name == :org_specialist

    assert PresidioCompatibility.select_policy_row(rows,
             policy_selection_objective: :location_f1
           ).policy_name == :location_specialist
  end

  test "target-aware policy selector respects FP cap and global F1 floor" do
    rows = [
      policy_row(:too_many_fp,
        f1: 0.91,
        recall: 0.8,
        false_positives: 25,
        location: %{recall: 0.7, f1: 0.7, true_positives: 7, false_negatives: 3},
        organization: %{recall: 0.6, f1: 0.6, true_positives: 6, false_negatives: 4}
      ),
      policy_row(:under_cap,
        f1: 0.88,
        recall: 0.7,
        false_positives: 10,
        location: %{recall: 0.5, f1: 0.5, true_positives: 5, false_negatives: 5},
        organization: %{recall: 0.4, f1: 0.4, true_positives: 4, false_negatives: 6}
      ),
      policy_row(:below_floor,
        f1: 0.7,
        recall: 0.9,
        false_positives: 5,
        location: %{recall: 0.9, f1: 0.8, true_positives: 9, false_negatives: 1},
        organization: %{recall: 0.9, f1: 0.8, true_positives: 9, false_negatives: 1}
      )
    ]

    assert PresidioCompatibility.select_policy_row(rows,
             policy_selection_objective: :global_f1_under_fp_cap,
             policy_fp_cap: 10
           ).policy_name == :under_cap

    assert PresidioCompatibility.select_policy_row(rows,
             policy_selection_objective: :open_class_recall_under_global_f1_floor,
             policy_global_f1_floor: 0.8
           ).policy_name == :too_many_fp
  end

  test "policy deltas include per-entity and model-label false-positive changes" do
    rows =
      PresidioCompatibility.policy_deltas([
        policy_row(:v18_train_selected,
          f1: 0.8,
          false_positives: 10,
          false_negatives: 20,
          location: %{f1: 0.5, true_positives: 10, false_positives: 4, false_negatives: 8},
          organization: %{f1: 0.4, true_positives: 5, false_positives: 1, false_negatives: 10},
          model_label_false_positives: %{
            "GPE" => 6,
            "FAC" => 2,
            "LOC" => 1,
            "ORG" => 1,
            "PERSON" => 0
          }
        ),
        policy_row(:candidate,
          f1: 0.82,
          false_positives: 8,
          false_negatives: 18,
          location: %{f1: 0.55, true_positives: 12, false_positives: 3, false_negatives: 6},
          organization: %{f1: 0.42, true_positives: 6, false_positives: 1, false_negatives: 9},
          model_label_false_positives: %{
            "GPE" => 4,
            "FAC" => 2,
            "LOC" => 1,
            "ORG" => 1,
            "PERSON" => 0
          }
        )
      ])

    candidate = Enum.find(rows, &(&1.policy_name == :candidate))

    assert_in_delta candidate.delta_from_baseline.global.f1, 0.02, 0.0001
    assert candidate.delta_from_baseline.location.false_negatives == -2
    assert candidate.delta_from_baseline.organization.false_negatives == -1
    assert candidate.delta_from_baseline.model_label_false_positives["GPE"] == -2
  end

  test "can run compatibility reports against explicit sample IDs" do
    {:ok, path} = PresidioResearchLoader.path_for(:generated_small)

    if File.exists?(path) do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :nlp,
                 sample_ids: [0, 2],
                 run_suffix: "presidio_spacy_subset"
               )

      assert report.run_id ==
               "presidio_compatibility_generated_small_nlp_smoke_presidio_spacy_subset"

      assert report.dataset.sample_ids == [0, 2]
      assert report.dataset.sample_count == 2
    else
      assert {:error, {:missing_presidio_research_dataset, ^path, :enoent}} =
               PresidioCompatibility.run(dataset: :generated_small, profile: :nlp)
    end
  end

  test "can run a template-heldout compatibility report" do
    {:ok, path} = PresidioResearchLoader.path_for(:generated_small)

    if File.exists?(path) do
      assert {:ok, report} =
               PresidioCompatibility.run(
                 dataset: :generated_small,
                 profile: :deterministic_plus,
                 template_split: :template_heldout,
                 template_train_ratio: 0.7,
                 full: true,
                 run_suffix: "v8"
               )

      assert report.run_id ==
               "presidio_compatibility_generated_small_deterministic_plus_template_heldout_full_v8"

      assert report.dataset.scope == "template_heldout_full"
      assert report.dataset.smoke == false
      assert report.dataset.template_split.name == :template_heldout
      assert report.dataset.template_split.selected_template_count > 0

      assert report.dataset.template_summary.template_count ==
               report.dataset.template_split.selected_template_count
    else
      assert {:error, {:missing_presidio_research_dataset, ^path, :enoent}} =
               PresidioCompatibility.run(dataset: :generated_small, profile: :deterministic_plus)
    end
  end

  defp policy_row(name, attrs) do
    defaults = [
      f1: 0.0,
      recall: 0.0,
      precision: 0.0,
      true_positives: 0,
      false_positives: 0,
      false_negatives: 0,
      location: %{},
      organization: %{},
      model_label_false_positives: %{
        "GPE" => 0,
        "FAC" => 0,
        "LOC" => 0,
        "ORG" => 0,
        "PERSON" => 0
      }
    ]

    defaults
    |> Keyword.merge(attrs)
    |> Map.new()
    |> Map.put(:policy_name, name)
  end

  defp tmp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp privacy_filter_config do
    %{
      "model_type" => "privacy_filter",
      "encoding" => "o200k_base",
      "num_hidden_layers" => 1,
      "num_experts" => 1,
      "experts_per_token" => 1,
      "vocab_size" => 10,
      "num_labels" => 5,
      "hidden_size" => 2,
      "intermediate_size" => 2,
      "head_dim" => 2,
      "num_attention_heads" => 2,
      "num_key_value_heads" => 1,
      "sliding_window" => 3,
      "bidirectional_context" => true,
      "bidirectional_left_context" => 1,
      "bidirectional_right_context" => 1,
      "initial_context_length" => 16,
      "rope_theta" => 10_000.0,
      "rope_scaling_factor" => 1.0,
      "rope_ntk_alpha" => 1.0,
      "rope_ntk_beta" => 32.0,
      "param_dtype" => "bfloat16",
      "ner_class_names" => [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person"
      ]
    }
  end
end
