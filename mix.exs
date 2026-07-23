defmodule Obscura.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/hfiguera/obscura"
  @security_url "#{@source_url}/security/advisories/new"

  def project do
    [
      app: :obscura,
      version: @version,
      elixir: "~> 1.20",
      source_url: @source_url,
      homepage_url: @source_url,
      elixirc_options: [no_warn_undefined: optional_modules()],
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix, :credence, :credo, :ex_dna, :ex_slop]
      ],
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        "ci.base": :test,
        "ci.optional": :test,
        "ci.real_model_smoke": :test
      ]
    ]
  end

  defp deps do
    base_deps = [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.3"},
      {:plug, "~> 1.16"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.35", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:credence, "~> 0.6", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.4", only: :test},
      {:nx, "~> 0.12", optional: true},
      {:bumblebee, "~> 0.7", optional: true},
      {:safetensors, "~> 0.1.3", optional: true},
      {:ex_phone_number, "~> 0.4.11", optional: true}
    ]

    base_deps ++
      real_model_deps() ++ mlx_model_deps() ++ gliner_ortex_deps() ++ gliner_tokenizer_deps()
  end

  defp docs do
    {manifest, _binding} = Code.eval_file("priv/obscura/public_api.exs")

    documented_modules =
      manifest.stable
      |> Map.keys()
      |> Kernel.++(Map.keys(manifest.experimental))
      |> Kernel.++(manifest.stable_mix_tasks)
      |> Kernel.++(manifest.experimental_mix_tasks)
      |> MapSet.new()

    [
      main: "Obscura",
      source_url: @source_url,
      source_ref: source_ref(),
      filter_modules: fn module, _metadata -> MapSet.member?(documented_modules, module) end,
      groups_for_modules: [
        "Stable API": &(Map.has_key?(manifest.stable, &1) or &1 in manifest.stable_mix_tasks),
        "Experimental API":
          &(Map.has_key?(manifest.experimental, &1) or &1 in manifest.experimental_mix_tasks)
      ],
      groups_for_extras: [
        "Start Here":
          ~r/README|profiles|public-api-stability|security-threat-model|operators|model-asset-licensing|benchmark-status|known-limitations/,
        Operations: ~r/optional-dependencies|runtime-diagnostics/,
        Guides:
          ~r/cli|recognizers|model-backed|language-detection|context-enhancement|structured-redaction|vaults|pseudonymization|rehydration|llm-workflows|streaming-rehydration|logger-and-plug|telemetry/
      ],
      extras: [
        "README.md",
        "docs/profiles.md",
        "docs/public-api-stability.md",
        "docs/security-threat-model.md",
        "docs/operators.md",
        "docs/model-asset-licensing.md",
        "docs/benchmark-status.md",
        "docs/optional-dependencies-and-assets.md",
        "docs/runtime-diagnostics.md",
        "docs/cli.md",
        "docs/recognizers.md",
        "docs/model-backed-recognition.md",
        "docs/language-detection.md",
        "docs/context-enhancement.md",
        "docs/structured-redaction.md",
        "docs/vaults.md",
        "docs/pseudonymization.md",
        "docs/rehydration.md",
        "docs/llm-workflows.md",
        "docs/streaming-rehydration.md",
        "docs/logger-and-plug.md",
        "docs/telemetry.md",
        "docs/known-limitations.md"
      ]
    ]
  end

  defp real_model_deps do
    if System.get_env("OBSCURA_REAL_MODEL") == "1" do
      [{:exla, "~> 0.12", only: [:dev, :test], optional: true}]
    else
      []
    end
  end

  defp mlx_model_deps do
    if System.get_env("OBSCURA_REAL_MODEL_BACKEND") == "emily" or
         System.get_env("OBSCURA_MLX_MODEL") == "1" or
         System.get_env("OBSCURA_GLINER_NATIVE") == "1" do
      [{:emily, "~> 0.6", only: [:dev, :test], optional: true}]
    else
      []
    end
  end

  defp gliner_ortex_deps do
    if System.get_env("OBSCURA_GLINER_ORTEX") == "1" do
      [{:ortex, path: "vendor/ortex", only: [:dev, :test], optional: true}]
    else
      []
    end
  end

  defp gliner_tokenizer_deps do
    if System.get_env("OBSCURA_GLINER_ORTEX") == "1" or
         System.get_env("OBSCURA_GLINER_NATIVE") == "1" do
      [{:tokenizers, "~> 0.5.1", optional: true}]
    else
      []
    end
  end

  defp aliases do
    [
      fixtures: ["obscura.fixtures"],
      "eval.smoke": ["obscura.eval --profile nlp --dataset synth_dataset_v2 --smoke"],
      "ci.authoritative_validate": ["obscura.benchmarks.verify"],
      "ci.operational_validate": ["obscura.operational.verify"],
      "ci.soak_validate": ["obscura.operational.soak.verify"],
      "ci.diagnostic_validate": ["obscura.operational.diagnostic.verify"],
      "ci.optional": [
        "test test/obscura/recognizer/deterministic_plus_test.exs test/obscura/recognizer/ner/serving_build_test.exs test/obscura/recognizer/gliner test/obscura/privacy_filter/checkpoint_test.exs test/obscura/privacy_filter/checkpoint"
      ],
      "ci.real_model_smoke": [
        "cmd mix obscura.eval --compatibility --dataset generated_small --profile balanced --limit 3 --real-model --run-suffix ci_real_model_smoke",
        "cmd mix obscura.eval --compatibility --dataset generated_small --profile accurate --limit 3 --real-model --run-suffix ci_real_model_smoke",
        "cmd mix obscura.eval --compatibility --dataset generated_small --profile openmed_pii --limit 3 --real-model --run-suffix ci_real_model_smoke"
      ],
      "deps.check_unused": [
        "cmd env MIX_ENV=test OBSCURA_REAL_MODEL=1 OBSCURA_REAL_MODEL_BACKEND=emily OBSCURA_GLINER_ORTEX=1 mix deps.get --only test",
        "cmd env MIX_ENV=test OBSCURA_REAL_MODEL=1 OBSCURA_REAL_MODEL_BACKEND=emily OBSCURA_GLINER_ORTEX=1 mix deps.unlock --check-unused"
      ],
      "ci.base": [
        "deps.check_unused",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "obscura.fixtures",
        "obscura.fixtures --suite accuracy",
        "obscura.eval --compatibility --dataset generated_small --profile fast --limit 5 --run-suffix ci_base",
        "ci.authoritative_validate",
        "ci.operational_validate",
        "ci.soak_validate",
        "ci.diagnostic_validate",
        "credo --strict --all",
        "dialyzer",
        "ex_dna",
        "ex_slop",
        "credence",
        "obscura.docs.verify",
        "docs"
      ],
      quality: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "ex_dna",
        "ex_slop",
        "credence"
      ],
      ci: [
        "ci.base"
      ]
    ]
  end

  defp package do
    [
      description: "Privacy-first PII detection and anonymization toolkit for Elixir.",
      exclude_patterns: ["eval/datasets"],
      files:
        ~w(lib priv/tiktoken priv/obscura .formatter.exs mix.exs README.md CHANGELOG.md SECURITY.md LICENSE THIRD_PARTY_NOTICES.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Security" => @security_url}
    ]
  end

  defp optional_modules do
    [
      Axon,
      Bumblebee,
      Bumblebee.Text,
      Credence,
      Emily,
      Emily.Backend,
      Emily.Compiler,
      ExPhoneNumber,
      ExPhoneNumber.Metadata,
      Nx,
      Nx.BinaryBackend,
      Nx.Defn,
      Nx.Tensor,
      Ortex,
      Ortex.Serving,
      Safetensors,
      Safetensors.FileTensor,
      Tokenizers.Encoding,
      Tokenizers.Tokenizer
    ]
  end

  defp source_ref do
    if String.ends_with?(@version, "-dev"), do: "main", else: "v#{@version}"
  end
end
