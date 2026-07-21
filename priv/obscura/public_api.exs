%{
  baseline_version: 1,
  release_line: "0.1.x",
  stable: %{
    Obscura => %{
      functions: [
        analyze: 1,
        analyze: 2,
        analyze_many: 1,
        analyze_many: 2,
        anonymize: 2,
        anonymize: 3,
        redact: 1,
        redact: 2,
        rehydrate: 1,
        rehydrate: 2
      ]
    },
    Obscura.Analyzer => %{functions: [analyze: 1, analyze: 2, analyze_many: 1, analyze_many: 2]},
    Obscura.Analyzer.Explanation => %{
      fields: [
        :recognizer,
        :pattern,
        :score,
        :original_score,
        :validation,
        :context_words,
        :score_context_delta,
        :metadata
      ]
    },
    Obscura.Analyzer.Result => %{
      fields: [
        :entity,
        :start,
        :end,
        :byte_start,
        :byte_end,
        :score,
        :text,
        :source_entity,
        :recognizer,
        :explanation,
        :metadata
      ]
    },
    Obscura.Anonymizer => %{functions: [anonymize: 2, anonymize: 3, validate_options: 1]},
    Obscura.Anonymizer.Error => %{
      functions: [message: 1],
      fields: [:code, :operator, :field, :reason, :metadata]
    },
    Obscura.Anonymizer.Item => %{
      fields: [
        :entity,
        :operator,
        :source_byte_start,
        :source_byte_end,
        :replacement_byte_start,
        :replacement_byte_end,
        :replacement,
        :metadata
      ]
    },
    Obscura.Anonymizer.Result => %{
      fields: [:text, :items, :status, :metadata]
    },
    Obscura.Capabilities => %{
      functions: [
        assets_for_profile: 1,
        fetch: 1,
        for_profile: 1,
        load: 0,
        load_assets: 0,
        path: 1
      ]
    },
    Obscura.Diagnostic => %{
      functions: [
        codes: 0,
        format: 1,
        new: 1,
        new: 2,
        normalize: 2,
        remediation: 1,
        to_map: 1
      ],
      fields: [
        :code,
        :message,
        :remediation,
        :component,
        :profile,
        :dependency,
        :backend,
        :asset,
        :path,
        :cause,
        :metadata
      ]
    },
    Obscura.Language => %{functions: [normalize: 1, supported: 0]},
    Obscura.Language.Detector => %{callbacks: [detect: 2]},
    Obscura.LLM => %{
      functions: [
        redact_messages: 1,
        redact_messages: 2,
        rehydrate_messages: 1,
        rehydrate_messages: 2,
        rehydrate_response: 1,
        rehydrate_response: 2
      ]
    },
    Obscura.Logger => %{
      functions: [
        redact_metadata: 1,
        redact_metadata: 2,
        redact_term: 1,
        redact_term: 2,
        safe_inspect: 1,
        safe_inspect: 2
      ]
    },
    Obscura.Operator.Custom => %{callbacks: [apply: 3]},
    Obscura.Operator.Hash => %{functions: [verify: 2]},
    Obscura.Phoenix.Plug => %{functions: [call: 2, init: 1]},
    Obscura.Profile => %{
      functions: [
        available?: 1,
        available?: 2,
        classification: 1,
        describe: 1,
        experimental_names: 0,
        fetch: 1,
        implementation_profiles: 0,
        names: 0,
        normalize: 1,
        preflight: 1,
        preflight: 2,
        prepare: 1,
        prepare: 2,
        requirements: 1,
        resolve: 1,
        validate_runtime: 1,
        validate_runtime: 2
      ],
      fields: [
        :name,
        :stability,
        :implementation_profile,
        :category,
        :recognizer_mode,
        :supported_entities,
        :required_dependencies,
        :optional_dependencies,
        :required_assets,
        :default_models,
        :backend_policy,
        :automatic_download,
        :benchmark_ids
      ]
    },
    Obscura.Profile.Runtime => %{
      fields: [
        :profile,
        :implementation_profile,
        :resources,
        :analyzer_options,
        :prepared_at,
        :backend_metadata
      ]
    },
    Obscura.Profile.Preparer => %{
      functions: [
        await: 1,
        await: 2,
        child_spec: 1,
        runtime: 1,
        start_link: 1,
        status: 1,
        subscribe: 1
      ]
    },
    Obscura.Recognizer => %{
      callbacks: [analyze: 2, analyze_many: 2, entity: 0, name: 0, supported_entities: 0]
    },
    Obscura.Recognizer.PatternDefinition => %{functions: [new!: 1]},
    Obscura.Redactable => %{functions: [redact: 2]},
    Obscura.Rehydrator => %{functions: [rehydrate: 1, rehydrate: 2]},
    Obscura.Rehydrator.Structured => %{functions: [rehydrate: 1, rehydrate: 2]},
    Obscura.Stream.Rehydrator => %{
      functions: [feed: 2, flush: 1, new: 1],
      opaque_struct: true
    },
    Obscura.Structured => %{
      functions: [analyze: 1, analyze: 2, redact: 1, redact: 2]
    },
    Obscura.Structured.Item => %{
      fields: [
        :path,
        :entity,
        :operator,
        :source_byte_start,
        :source_byte_end,
        :replacement,
        :metadata
      ]
    },
    Obscura.Structured.Result => %{fields: [:data, :items, :status, :metadata]},
    Obscura.Vault => %{
      functions: [
        clear: 1,
        clear: 2,
        get_or_create: 3,
        get_or_create: 4,
        info: 1,
        lookup_token: 2,
        lookup_token: 3,
        lookup_value: 3,
        lookup_value: 4,
        rehydrate: 2,
        rehydrate: 3
      ]
    },
    Obscura.Vault.Backend => %{callbacks: [handle_call: 3, init: 1, start_link: 1]},
    Obscura.Vault.Entry => %{
      fields: [:entity, :token, :created_at, :last_used_at, :use_count, :metadata, :value]
    },
    Obscura.Vault.ETS => %{functions: [child_spec: 1, start_link: 0, start_link: 1]},
    Obscura.Vault.Memory => %{functions: [child_spec: 1, start_link: 0, start_link: 1]}
  },
  experimental: %{
    Obscura.NLP.Artifacts => "Model artifact representation may evolve with adapters.",
    Obscura.NLP.Engine => "The model-engine callback contract is not frozen.",
    Obscura.NLP.Engine.Bumblebee => "Optional Bumblebee adapter.",
    Obscura.PrivacyFilter.Checkpoint => "OpenMed checkpoint contract remains model-specific.",
    Obscura.PrivacyFilter.Checkpoint.Setup => "OpenMed asset preparation remains experimental.",
    Obscura.PrivacyFilter.Serving => "Native Privacy Filter serving remains experimental.",
    Obscura.Recognizer.GLiNER => "GLiNER adapter and label policy remain experimental.",
    Obscura.Recognizer.GLiNER.Native =>
      "Optional native Nx/Emily GLiNER adapter and shape policy may change.",
    Obscura.Recognizer.GLiNER.Ortex => "Optional Ortex adapter and tensor contract may change.",
    Obscura.Recognizer.NER => "Low-level NER adapter remains experimental.",
    Obscura.Recognizer.NER.FakeServing => "Testing adapter; not a production accuracy path.",
    Obscura.Recognizer.NER.ModelSpec => "Model identity and label metadata may evolve.",
    Obscura.Recognizer.NER.Serving => "Optional model-serving construction may change.",
    Obscura.Recognizer.Phone.ExPhoneNumberValidator =>
      "Optional parser adapter depends on ex_phone_number.",
    Obscura.Recognizer.PrivacyFilter.Native => "Native OpenMed recognizer remains experimental.",
    Obscura.Tiktoken => "Tokenizer compatibility API is not yet part of the core release promise.",
    Obscura.Tiktoken.Encoding => "Encoding representation and low-level functions may change."
  },
  deprecated: %{},
  internal_default: true,
  stable_profiles: [:fast, :balanced, :accurate],
  experimental_profiles: [:hybrid_gliner_urchade, :openmed_pii],
  operators: %{
    replace: %{required: [:type], optional: %{value: "[REDACTED]"}},
    redact: %{required: [:type], optional: %{}},
    mask: %{required: [:type], optional: %{char: "*", keep_last: 0}},
    hash: %{required: [:type], optional: %{algorithm: :sha256, mode: :secure}},
    pseudonymize: %{required: [:type], optional: %{vault: nil}},
    custom: %{required: [:type, :module], optional: %{options: %{}}}
  },
  anonymizer_error_codes: [
    :invalid_operator_collection,
    :invalid_operator_config,
    :unsupported_operator,
    :unknown_operator_option,
    :missing_operator_option,
    :invalid_operator_option,
    :operator_failed,
    :invalid_operator_result
  ],
  diagnostic_codes: [
    :backend_device_unavailable,
    :backend_fallback_forbidden,
    :backend_unavailable,
    :checkpoint_hash_mismatch,
    :checkpoint_incomplete,
    :checkpoint_layout_mismatch,
    :inference_timeout,
    :missing_checkpoint,
    :missing_model_asset,
    :missing_model_config,
    :missing_optional_dependency,
    :missing_tokenizer_asset,
    :model_asset_incomplete,
    :model_cache_failure,
    :model_download_interrupted,
    :model_download_not_allowed,
    :model_load_failed,
    :preparation_inactivity_timeout,
    :preparation_timeout,
    :profile_requirements_unsatisfied,
    :serving_build_failed,
    :tokenizer_load_failed,
    :unknown_profile,
    :unsupported_backend,
    :unsupported_model_architecture
  ],
  stable_mix_tasks: [
    Mix.Tasks.Obscura.Detect,
    Mix.Tasks.Obscura.Docs.Verify,
    Mix.Tasks.Obscura.Profile.Check,
    Mix.Tasks.Obscura.Profile.Prepare,
    Mix.Tasks.Obscura.Redact
  ],
  experimental_mix_tasks: [
    Mix.Tasks.Obscura.Ner.Smoke,
    Mix.Tasks.Obscura.Operational.Benchmark,
    Mix.Tasks.Obscura.Operational.Promote,
    Mix.Tasks.Obscura.Operational.Soak,
    Mix.Tasks.Obscura.Operational.Soak.Promote,
    Mix.Tasks.Obscura.Operational.Soak.Verify,
    Mix.Tasks.Obscura.Operational.Verify,
    Mix.Tasks.Obscura.PrivacyFilter.Checkpoint,
    Mix.Tasks.Obscura.PrivacyFilter.Setup
  ]
}
