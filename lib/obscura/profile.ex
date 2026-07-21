defmodule Obscura.Profile do
  @moduledoc """
  Product profiles and runtime requirement checks.

  Stable profiles are user-facing aliases over benchmarked implementation
  profiles. Experimental aliases and existing implementation profiles remain
  available for explicit evaluation use. Only stable aliases and public return
  shapes follow the `0.1.x` policy in `docs/public-api-stability.md`.
  """

  alias Obscura.Diagnostic
  alias Obscura.Eval.EntityMapping
  alias Obscura.Profile.Preflight
  alias Obscura.Profile.Preparation
  alias Obscura.Profile.Runtime
  alias Obscura.Recognizer.GLiNER.ModelRegistry, as: GLiNERModelRegistry
  alias Obscura.Recognizer.PrivacyFilter.Native, as: PrivacyFilterNative

  @enforce_keys [
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
    :automatic_download
  ]
  defstruct [
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
    benchmark_ids: []
  ]

  @type stable_name :: :fast | :balanced | :accurate
  @type experimental_name :: :hybrid_gliner_urchade | :openmed_pii
  @type name :: stable_name() | experimental_name()
  @type stability :: :stable | :advanced | :experimental | :historical | :deprecated
  @type t :: %__MODULE__{
          name: name(),
          stability: stability(),
          implementation_profile: atom(),
          category: atom(),
          recognizer_mode: atom(),
          supported_entities: [atom()],
          required_dependencies: [atom()],
          optional_dependencies: [atom()],
          required_assets: [atom()],
          default_models: [atom()],
          backend_policy: atom(),
          automatic_download: boolean(),
          benchmark_ids: [String.t()]
        }

  @stable_names [:fast, :balanced, :accurate]
  @experimental_names [:hybrid_gliner_urchade, :openmed_pii]

  @advanced_profiles [
    :regex_only,
    :context,
    :llm_safe,
    :deterministic_plus,
    :hybrid_ner_tner_conservative,
    :hybrid_privacy_filter_native
  ]

  @experimental_profiles [
    :hybrid_ner_tner_jean_location,
    :privacy_filter_native,
    :hybrid_ner,
    :hybrid_ner_conservative,
    :hybrid_ner_balanced,
    :hybrid_ner_org,
    :hybrid_ner_org_high_recall,
    :hybrid_ner_dbmdz_conservative,
    :hybrid_ner_tner_high_recall,
    :hybrid_ner_tner_facebookai_org,
    :hybrid_ner_tner_jean_location_gated,
    :hybrid_ner_tner_jean_location_cascade,
    :hybrid_ner_bigmed_conservative,
    :ner_ortex_openmed_superclinical_small,
    :hybrid_ner_ortex_openmed_superclinical_small,
    :ner_ortex_piiranha_v1,
    :hybrid_ner_ortex_piiranha_v1,
    :gliner_ortex,
    :hybrid_gliner_ortex,
    :hybrid_gliner_urchade_native,
    :phi,
    :real_ner,
    :real_pii
  ]

  @historical_profiles [:nlp]

  @doc """
  Lists stable user-facing profile names.
  """
  @spec names() :: [stable_name()]
  def names, do: @stable_names

  @doc """
  Lists opt-in product aliases outside the compatibility promise.

  Experimental aliases remain callable for controlled evaluation, but they are
  not generally recommended and may change or be removed before release.
  """
  @spec experimental_names() :: [experimental_name()]
  def experimental_names, do: @experimental_names

  @doc """
  Lists all implementation profiles accepted for backward compatibility.
  """
  @spec implementation_profiles() :: [atom()]
  def implementation_profiles do
    (@advanced_profiles ++ @experimental_profiles ++ @historical_profiles)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns a stable or explicitly experimental product profile descriptor.
  """
  @spec fetch(name() | String.t()) :: {:ok, t()} | {:error, Diagnostic.t()}
  def fetch(profile) do
    with {:ok, profile} <- normalize_name(profile) do
      fetch_product(profile)
    end
  end

  @doc """
  Resolves a product alias or known implementation profile.
  """
  @spec resolve(atom() | String.t()) :: {:ok, atom()} | {:error, Diagnostic.t()}
  def resolve(profile) do
    with {:ok, profile} <- normalize_name(profile) do
      cond do
        profile in product_names() -> {:ok, fetch_product!(profile).implementation_profile}
        profile in implementation_profiles() -> {:ok, profile}
        true -> {:error, unknown_profile(profile)}
      end
    end
  end

  @doc """
  Returns the requested profile and resolved implementation profile.
  """
  @spec normalize(atom() | String.t()) ::
          {:ok, %{requested: atom(), implementation: atom()}} | {:error, Diagnostic.t()}
  def normalize(profile) do
    with {:ok, requested} <- normalize_name(profile),
         {:ok, implementation} <- resolve(requested) do
      {:ok, %{requested: requested, implementation: implementation}}
    end
  end

  @doc """
  Returns the stability classification for a known profile.
  """
  @spec classification(atom() | String.t()) :: {:ok, stability()} | {:error, Diagnostic.t()}
  def classification(profile) do
    with {:ok, profile} <- normalize_name(profile) do
      cond do
        profile in @stable_names -> {:ok, :stable}
        profile in @experimental_names -> {:ok, :experimental}
        profile in @advanced_profiles -> {:ok, :advanced}
        profile in @experimental_profiles -> {:ok, :experimental}
        profile in @historical_profiles -> {:ok, :historical}
        true -> {:error, unknown_profile(profile)}
      end
    end
  end

  @doc """
  Returns the runtime requirements for a product profile.
  """
  @spec requirements(name() | String.t()) :: {:ok, map()} | {:error, Diagnostic.t()}
  def requirements(profile) do
    with {:ok, descriptor} <- fetch(profile) do
      {:ok,
       %{
         profile: descriptor.name,
         stability: descriptor.stability,
         implementation_profile: descriptor.implementation_profile,
         required_dependencies: descriptor.required_dependencies,
         optional_dependencies: descriptor.optional_dependencies,
         required_assets: descriptor.required_assets,
         default_models: descriptor.default_models,
         backend_policy: descriptor.backend_policy,
         automatic_download: descriptor.automatic_download
       }}
    end
  end

  @doc """
  Returns whether a product profile is ready without running inference.
  """
  @spec available?(name() | String.t(), keyword()) :: boolean()
  def available?(profile, opts \\ []) do
    validate_runtime(profile, opts) == :ok
  end

  @doc """
  Returns a report-safe readiness result without analyzing PII.

  Local checks are the default. `prepare: true` explicitly permits runtime and
  model preparation.
  """
  @spec preflight(name() | String.t(), keyword()) ::
          {:ok, map()} | {:error, Diagnostic.t(), map()}
  def preflight(profile, opts \\ []), do: Preflight.run(profile, opts)

  @doc """
  Validates dependencies and reusable runtime assets without running inference.
  """
  @spec validate_runtime(name() | String.t(), keyword()) :: :ok | {:error, Diagnostic.t()}
  def validate_runtime(profile, opts \\ []) when is_list(opts) do
    with {:ok, descriptor} <- fetch(profile),
         :ok <- validate_dependencies(descriptor, opts) do
      validate_assets(descriptor, opts)
    end
  end

  @doc """
  Returns report-safe profile metadata.
  """
  @spec describe(name() | String.t()) :: {:ok, map()} | {:error, Diagnostic.t()}
  def describe(profile) do
    with {:ok, descriptor} <- fetch(profile) do
      {:ok, Map.from_struct(descriptor)}
    end
  end

  @doc """
  Explicitly prepares reusable resources for a product profile.

  This is the only product-profile API which may load model assets. Ordinary
  analysis never calls it implicitly. Remote downloads require
  `allow_download: true`; preparation is cache-only by default and
  `offline: true` always forbids network access.

  Model-backed preparation runs in a monitored worker with a 30-minute overall
  timeout and a five-minute inactivity timeout by default. Set `timeout` or
  `inactivity_timeout` to a positive millisecond value or `:infinity`.
  `progress: fn event -> ... end` receives safe lifecycle events; callback
  failures are isolated from preparation. Online preparation retries one
  transient model or tokenizer load failure. Offline preparation never retries
  asset access. Authorized recovery quarantines unreferenced partial files and
  reports cache recovery before replacement download progress.
  """
  @spec prepare(name() | String.t(), keyword()) ::
          {:ok, Runtime.t()} | {:error, Diagnostic.t()}
  def prepare(profile, opts \\ []), do: Preparation.prepare(profile, opts)

  @doc false
  @spec configure_options(keyword()) :: {:ok, keyword()} | {:error, Diagnostic.t()}
  def configure_options(opts) when is_list(opts), do: Runtime.configure_options(opts)

  defp fetch_product(:fast) do
    {:ok,
     profile(
       :fast,
       :deterministic_plus,
       category: :general_pii,
       recognizer_mode: :deterministic,
       supported_entities: EntityMapping.deterministic_plus_supported_entities(),
       optional_dependencies: [:ex_phone_number],
       backend_policy: :none
     )}
  end

  defp fetch_product(:balanced) do
    {:ok,
     profile(
       :balanced,
       :hybrid_ner_tner_conservative,
       category: :general_pii,
       recognizer_mode: :deterministic_plus_model,
       supported_entities: EntityMapping.hybrid_ner_supported_entities(),
       required_dependencies: [:nx, :bumblebee],
       optional_dependencies: [:emily, :exla],
       required_assets: [:primary_serving, :model, :tokenizer],
       default_models: [:tner_roberta_large_ontonotes5]
     )}
  end

  defp fetch_product(:accurate) do
    {:ok,
     profile(
       :accurate,
       :hybrid_ner_tner_jean_location_cascade,
       category: :general_pii,
       recognizer_mode: :deterministic_plus_multi_model,
       supported_entities: EntityMapping.hybrid_ner_supported_entities(),
       required_dependencies: [:nx, :bumblebee],
       optional_dependencies: [:emily, :exla],
       required_assets: [:primary_serving, :location_serving, :models, :tokenizers],
       default_models: [
         :tner_roberta_large_ontonotes5,
         :jean_baptiste_roberta_large_ner_english
       ]
     )}
  end

  defp fetch_product(:openmed_pii) do
    {:ok,
     profile(
       :openmed_pii,
       :privacy_filter_native,
       stability: :experimental,
       category: :openmed_pii,
       recognizer_mode: :model_only,
       supported_entities: PrivacyFilterNative.supported_entities(),
       required_dependencies: [:nx, :safetensors],
       optional_dependencies: [:emily, :exla],
       required_assets: [:privacy_filter_serving, :checkpoint],
       default_models: [:openmed_privacy_filter_nemotron_v2]
     )}
  end

  defp fetch_product(:hybrid_gliner_urchade) do
    {:ok,
     profile(
       :hybrid_gliner_urchade,
       :hybrid_gliner_urchade,
       stability: :experimental,
       category: :general_pii,
       recognizer_mode: :deterministic_plus_model,
       supported_entities: EntityMapping.hybrid_gliner_supported_entities(),
       required_dependencies: [:ortex, :tokenizers],
       optional_dependencies: [:ex_phone_number],
       required_assets: [:gliner_serving, :onnx_model, :tokenizer, :model_config],
       default_models: [:urchade_gliner_multi_pii_v1],
       backend_policy: :ortex_cpu
     )}
  end

  defp fetch_product(profile), do: {:error, unknown_profile(profile)}

  defp fetch_product!(profile) do
    {:ok, descriptor} = fetch_product(profile)
    descriptor
  end

  defp profile(name, implementation, attrs) do
    %__MODULE__{
      name: name,
      stability: Keyword.get(attrs, :stability, :stable),
      implementation_profile: implementation,
      category: Keyword.fetch!(attrs, :category),
      recognizer_mode: Keyword.fetch!(attrs, :recognizer_mode),
      supported_entities: Keyword.fetch!(attrs, :supported_entities),
      required_dependencies: Keyword.get(attrs, :required_dependencies, []),
      optional_dependencies: Keyword.get(attrs, :optional_dependencies, []),
      required_assets: Keyword.get(attrs, :required_assets, []),
      default_models: Keyword.get(attrs, :default_models, []),
      backend_policy: Keyword.get(attrs, :backend_policy, :explicit),
      automatic_download: false
    }
  end

  @doc false
  @spec validate_dependencies(t(), keyword()) :: :ok | {:error, Diagnostic.t()}
  def validate_dependencies(descriptor, opts) do
    checker = Keyword.get(opts, :dependency_checker, &dependency_loaded?/1)

    Enum.find(descriptor.required_dependencies, &(not checker.(&1)))
    |> case do
      nil -> :ok
      dependency -> {:error, missing_dependency(descriptor, dependency)}
    end
  end

  defp validate_assets(%__MODULE__{name: :fast}, _opts), do: :ok

  defp validate_assets(%__MODULE__{name: :balanced} = descriptor, opts) do
    if present?(Keyword.get(opts, :serving)) or present?(Keyword.get(opts, :primary_serving)) do
      :ok
    else
      {:error, missing_asset(descriptor, :primary_serving)}
    end
  end

  defp validate_assets(%__MODULE__{name: :accurate} = descriptor, opts) do
    servings = Keyword.get(opts, :servings, %{})
    primary = Keyword.get(opts, :primary_serving) || get_in_map(servings, :primary)
    location = Keyword.get(opts, :location_serving) || get_in_map(servings, :location)

    cond do
      not present?(primary) -> {:error, missing_asset(descriptor, :primary_serving)}
      not present?(location) -> {:error, missing_asset(descriptor, :location_serving)}
      true -> :ok
    end
  end

  defp validate_assets(%__MODULE__{name: :openmed_pii} = descriptor, opts) do
    serving = Keyword.get(opts, :serving) || Keyword.get(opts, :privacy_filter_serving)
    checkpoint = Keyword.get(opts, :checkpoint) || Keyword.get(opts, :privacy_filter_checkpoint)

    cond do
      present?(serving) -> :ok
      is_binary(checkpoint) and File.dir?(checkpoint) -> :ok
      true -> {:error, missing_checkpoint(descriptor, checkpoint)}
    end
  end

  defp validate_assets(%__MODULE__{name: :hybrid_gliner_urchade} = descriptor, opts) do
    serving = Keyword.get(opts, :serving) || Keyword.get(opts, :gliner_serving)

    if present?(serving) do
      :ok
    else
      validate_gliner_assets(descriptor, opts)
    end
  end

  defp validate_gliner_assets(descriptor, opts) do
    with {:ok, spec} <- GLiNERModelRegistry.fetch(:urchade_gliner_multi_pii_v1),
         {:ok, _paths} <- GLiNERModelRegistry.resolve_paths(spec, opts) do
      :ok
    else
      {:error, reason} -> {:error, gliner_asset_diagnostic(descriptor, reason)}
    end
  end

  defp dependency_loaded?(:nx), do: Code.ensure_loaded?(Nx)
  defp dependency_loaded?(:bumblebee), do: Code.ensure_loaded?(Bumblebee)
  defp dependency_loaded?(:safetensors), do: Code.ensure_loaded?(Safetensors)
  defp dependency_loaded?(dependency), do: Application.spec(dependency) != nil

  defp normalize_name(profile) when is_atom(profile), do: {:ok, profile}

  defp normalize_name(profile) when is_binary(profile) do
    known = product_names() ++ implementation_profiles()

    case Enum.find(known, &(Atom.to_string(&1) == profile)) do
      nil -> {:error, unknown_profile(profile)}
      value -> {:ok, value}
    end
  end

  defp normalize_name(profile), do: {:error, unknown_profile(profile)}

  defp missing_dependency(descriptor, dependency) do
    Diagnostic.new(:missing_optional_dependency,
      profile: descriptor.name,
      component: :profile_runtime,
      dependency: dependency,
      message: "The #{descriptor.name} profile requires the #{dependency} dependency."
    )
  end

  defp missing_asset(descriptor, asset) do
    Diagnostic.new(:missing_model_asset,
      profile: descriptor.name,
      component: :profile_runtime,
      asset: asset,
      message: "The #{descriptor.name} profile requires a reusable #{asset}."
    )
  end

  defp missing_checkpoint(descriptor, checkpoint) do
    Diagnostic.new(:missing_checkpoint,
      profile: descriptor.name,
      component: :privacy_filter,
      asset: :checkpoint,
      path: checkpoint,
      message: "The #{descriptor.name} profile requires a validated local checkpoint."
    )
  end

  defp gliner_asset_diagnostic(descriptor, :missing_gliner_model_dir) do
    missing_asset(descriptor, :gliner_model_dir)
  end

  defp gliner_asset_diagnostic(descriptor, {:missing_gliner_onnx, _path}) do
    missing_asset(descriptor, :onnx_model)
  end

  defp gliner_asset_diagnostic(descriptor, {:missing_gliner_tokenizer, _path}) do
    Diagnostic.new(:missing_tokenizer_asset,
      profile: descriptor.name,
      component: :profile_runtime,
      asset: :tokenizer,
      message: "The #{descriptor.name} profile requires the pinned GLiNER tokenizer."
    )
  end

  defp gliner_asset_diagnostic(descriptor, {:missing_gliner_config, _path}) do
    Diagnostic.new(:missing_model_config,
      profile: descriptor.name,
      component: :profile_runtime,
      asset: :model_config,
      message: "The #{descriptor.name} profile requires the pinned GLiNER model config."
    )
  end

  defp gliner_asset_diagnostic(descriptor, _reason),
    do: missing_asset(descriptor, :gliner_serving)

  defp unknown_profile(profile) do
    Diagnostic.new(:unknown_profile,
      profile: profile,
      component: :profile,
      message: "Unknown Obscura profile: #{inspect(profile)}.",
      metadata: %{supported: @stable_names, experimental: @experimental_names}
    )
  end

  defp product_names, do: @stable_names ++ @experimental_names

  defp get_in_map(map, key) when is_map(map), do: Map.get(map, key)
  defp get_in_map(_map, _key), do: nil

  defp present?(nil), do: false
  defp present?(_value), do: true
end
