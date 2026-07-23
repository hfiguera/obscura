%{
  "README.md" => %{
    "Product Profiles" => [
      {:test, "test/obscura/documented_examples_test.exs"},
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Model preparation requires optional dependencies, model assets, and an explicit backend."},
      {:test, "test/mix/tasks/obscura.profile.check_test.exs"}
    ],
    "Installation" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Analyze" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Anonymize" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Redact" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Extensibility" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Custom NER Integration" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Structs, Logger, and Plug" => [
      {:test, "test/obscura/documented_examples_test.exs"},
      {:test, "test/obscura/phoenix/plug_test.exs"}
    ],
    "Vaults and Rehydration" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "LLM Workflows" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/profiles.md" => %{
    "Fast" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Balanced" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Requires the TNER model, Bumblebee/Nx, and an explicitly configured accelerator backend."}
    ],
    "Urchade GLiNER CPU (Experimental)" => [
      {:opt_in, "test/obscura/recognizer/gliner/real_model_test.exs",
       "Requires the pinned Urchade ONNX/tokenizer/config assets plus optional Ortex and Tokenizers dependencies."}
    ],
    "Accurate" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Requires two local model assets and an explicitly configured accelerator backend."}
    ],
    "OpenMed PII (Experimental)" => [
      {:opt_in, "test/obscura/privacy_filter/real_model_test.exs",
       "Requires a local OpenMed checkpoint and an explicitly configured accelerator backend."},
      {:test, "test/obscura/privacy_filter/checkpoint_test.exs"}
    ],
    "Preflight" => [{:test, "test/mix/tasks/obscura.profile.check_test.exs"}],
    "First Preparation And Runtime Ownership" => [
      {:test, "test/obscura/profile/preparation_test.exs"},
      {:test, "test/obscura/profile/preparer_test.exs"},
      {:test, "test/mix/tasks/obscura.profile.prepare_test.exs"}
    ]
  },
  "docs/benchmark-status.md" => %{
    "Regression Policy" => [
      {:test, "test/obscura/eval/authoritative_manifest_test.exs"}
    ]
  },
  "docs/cli.md" => %{
    "Detect" => [{:test, "test/mix/tasks/obscura_detect_test.exs"}],
    "Redact" => [{:test, "test/mix/tasks/obscura_redact_test.exs"}],
    "Config" => [{:test, "test/mix/tasks/obscura_gen_config_test.exs"}],
    "Prediction Export" => [
      {:test, "test/mix/tasks/obscura_export_predictions_test.exs"}
    ]
  },
  "docs/operators.md" => %{
    "Replace" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Redact" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Mask" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Secure Mode" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Deterministic Mode" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Pseudonymize" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Custom Operators" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/optional-dependencies-and-assets.md" => %{
    "Base Installation" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Parser-Backed Phone Validation" => [
      {:test, "test/obscura/recognizer/deterministic_plus_test.exs"}
    ],
    "Bumblebee/Nx Profiles" => [
      {:test, "test/obscura/profile/preflight_test.exs"},
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Inference requires optional Nx/Bumblebee dependencies and local model assets."}
    ],
    "Emily on macOS Apple Silicon" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Requires Apple Silicon, Emily, local model assets, and GPU backend proof."}
    ],
    "EXLA" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Requires optional EXLA and local model assets."}
    ],
    "Explicit Runtime Preparation" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Preparation intentionally loads optional model assets outside the base test suite."}
    ],
    "Urchade GLiNER Multi PII" => [
      {:opt_in, "test/obscura/recognizer/gliner/urchade_coreml_test.exs",
       "Requires the pinned Urchade ONNX assets, Apple CoreML, and the conditional Ortex fork."}
    ],
    "Native Privacy Filter" => [
      {:test, "test/obscura/privacy_filter/checkpoint/setup_test.exs"},
      {:opt_in, "test/obscura/privacy_filter/real_model_test.exs",
       "Inference requires a local checkpoint and explicit accelerator backend."}
    ],
    "GLiNER, Native Emily, and Generic Ortex" => [
      {:opt_in, "test/obscura/recognizer/gliner/real_model_test.exs",
       "Requires optional Ortex/Tokenizers dependencies and local ONNX assets."}
    ]
  },
  "docs/runtime-diagnostics.md" => %{
    "Runtime Diagnostics" => [
      {:test, "test/obscura/documented_examples_test.exs"},
      {:test, "test/mix/tasks/obscura.profile.check_test.exs"}
    ]
  },
  "docs/recognizers.md" => %{
    "Optional Phone Parser" => [
      {:test, "test/obscura/recognizer/deterministic_plus_test.exs"}
    ],
    "NER Recognizer" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Custom Modules" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Inline Patterns" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Deny Lists" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Allow Lists" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/model-backed-recognition.md" => %{
    "Fake Serving" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Real Local Serving" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Requires model assets, optional dependencies, and an explicit backend."}
    ],
    "Optional Backend Selection" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Requires the selected optional backend and local model assets."}
    ],
    "Hybrid Deterministic Plus Real NER" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Accuracy evaluation requires real model inference and pinned datasets."}
    ],
    "Batch Analysis" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Artifact-Backed Model Output" => [
      {:test, "test/obscura/analyzer/artifacts_pipeline_test.exs"}
    ],
    "Analyzer-Level NLP Engine" => [
      {:opt_in, "test/obscura/recognizer/ner/real_model_test.exs",
       "Bumblebee NLP-engine execution requires optional model dependencies and assets."}
    ]
  },
  "docs/language-detection.md" => %{
    "Language Detection" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/context-enhancement.md" => %{
    "Usage" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Context Policies" => [{:test, "test/obscura/context/context_test.exs"}]
  },
  "docs/structured-redaction.md" => %{
    "Maps and Lists" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Structs" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/vaults.md" => %{
    "Vaults" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Session Isolation" => [{:test, "test/obscura/vault/vault_test.exs"}]
  },
  "docs/pseudonymization.md" => %{
    "Pseudonymization" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Structured Data" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/rehydration.md" => %{
    "Rehydration" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/llm-workflows.md" => %{
    "LLM Workflows" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/streaming-rehydration.md" => %{
    "Streaming Rehydration" => [{:test, "test/obscura/documented_examples_test.exs"}]
  },
  "docs/logger-and-plug.md" => %{
    "Logger Helpers" => [{:test, "test/obscura/documented_examples_test.exs"}],
    "Plug-Compatible Helper" => [{:test, "test/obscura/phoenix/plug_test.exs"}]
  }
}
