defmodule Obscura.Profile.Runtime do
  @moduledoc """
  Explicit reusable runtime resources for product profiles.

  Building a runtime is opt-in and may load local or Hugging Face model assets.
  Analyzer calls only consume an already prepared runtime or caller-provided
  serving and never invoke `prepare/2` themselves.
  """

  alias Obscura.Diagnostic
  alias Obscura.PrivacyFilter.OpenMedPolicy
  alias Obscura.PrivacyFilter.Serving, as: PrivacyFilterServing
  alias Obscura.Profile
  alias Obscura.Recognizer.GLiNER
  alias Obscura.Recognizer.GLiNER.Ortex, as: GLiNEROrtex
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.Routing
  alias Obscura.Recognizer.NER.Serving, as: NERServing
  alias Obscura.Recognizer.PrivacyFilter.Native, as: PrivacyFilterNative

  @urchade_thresholds %{
    "person" => 0.5,
    "organization" => 0.9,
    "location" => 0.5
  }

  @accurate_cascade_policy [
    cascade_trigger: :missing,
    cascade_secondary_threshold: 0.999,
    cascade_context_policy: :none
  ]

  @enforce_keys [:profile, :implementation_profile, :resources, :analyzer_options, :prepared_at]
  defstruct [
    :profile,
    :implementation_profile,
    :resources,
    :analyzer_options,
    :prepared_at,
    backend_metadata: %{}
  ]

  @type t :: %__MODULE__{
          profile: Profile.name(),
          implementation_profile: atom(),
          resources: map(),
          analyzer_options: keyword(),
          prepared_at: DateTime.t(),
          backend_metadata: map()
        }

  @doc false
  @spec build(Profile.name() | String.t(), keyword()) ::
          {:ok, t()} | {:error, Diagnostic.t()}
  def build(profile, opts \\ []) when is_list(opts) do
    with {:ok, descriptor} <- Profile.fetch(profile) do
      do_prepare(descriptor, opts)
    end
  end

  @doc false
  @spec configure_options(keyword()) :: {:ok, keyword()} | {:error, Diagnostic.t()}
  def configure_options(opts) when is_list(opts) do
    case Keyword.get(opts, :profile, :regex_only) do
      %__MODULE__{} = runtime ->
        configure_runtime(runtime, opts)

      profile
      when profile in [:fast, :balanced, :accurate, :hybrid_gliner_urchade, :openmed_pii] ->
        configure_product(profile, opts)

      _implementation_profile ->
        {:ok, opts}
    end
  end

  defp do_prepare(%Profile{name: :fast} = descriptor, _opts) do
    {:ok, runtime(descriptor, %{}, base_options(descriptor), %{})}
  end

  defp do_prepare(%Profile{name: :balanced} = descriptor, opts) do
    serving_opts =
      opts
      |> Keyword.put(:model, :tner_roberta_large_ontonotes5)
      |> Keyword.put(:model_index, 1)
      |> Keyword.put(:model_count, 1)
      |> Keyword.put_new(:compile, batch_size: 1, sequence_length: 128)

    case build_ner_serving(serving_opts) do
      {:ok, serving} ->
        options = balanced_options(descriptor, serving, opts)
        {:ok, runtime(descriptor, %{primary: serving}, options, ner_serving_metadata(serving))}

      {:error, reason} ->
        {:error, serving_diagnostic(descriptor, reason)}
    end
  end

  defp do_prepare(%Profile{name: :accurate} = descriptor, opts) do
    base = Keyword.put_new(opts, :compile, batch_size: 1, sequence_length: 128)

    with {:ok, primary} <-
           base
           |> Keyword.put(:model, :tner_roberta_large_ontonotes5)
           |> Keyword.put(:model_index, 1)
           |> Keyword.put(:model_count, 2)
           |> build_ner_serving(),
         {:ok, location} <-
           base
           |> Keyword.put(:model, :jean_baptiste_roberta_large_ner_english)
           |> Keyword.put(:model_index, 2)
           |> Keyword.put(:model_count, 2)
           |> build_ner_serving() do
      resources = %{primary: primary, location: location}
      options = accurate_options(descriptor, resources, opts)

      metadata = %{
        primary: ner_serving_metadata(primary),
        location: ner_serving_metadata(location)
      }

      {:ok, runtime(descriptor, resources, options, metadata)}
    else
      {:error, reason} -> {:error, serving_diagnostic(descriptor, reason)}
    end
  end

  defp do_prepare(%Profile{name: :openmed_pii} = descriptor, opts) do
    serving_opts = privacy_filter_serving_options(opts)

    case build_privacy_filter_serving(serving_opts, opts) do
      {:ok, serving} ->
        options = openmed_options(descriptor, serving, opts)
        metadata = privacy_filter_metadata(serving)
        {:ok, runtime(descriptor, %{privacy_filter: serving}, options, metadata)}

      {:error, reason} ->
        {:error, serving_diagnostic(descriptor, reason)}
    end
  end

  defp do_prepare(%Profile{name: :hybrid_gliner_urchade} = descriptor, opts) do
    serving_opts = gliner_serving_options(opts)

    case build_gliner_serving(serving_opts, opts) do
      {:ok, serving} ->
        options = gliner_urchade_options(descriptor, serving, opts)
        metadata = gliner_metadata(serving)
        {:ok, runtime(descriptor, %{gliner: serving}, options, metadata)}

      {:error, reason} ->
        {:error, serving_diagnostic(descriptor, reason)}
    end
  end

  defp configure_runtime(runtime, opts) do
    overrides = Keyword.delete(opts, :profile)

    analyzer_options =
      runtime.analyzer_options
      |> Keyword.merge(overrides)
      |> scope_runtime_recognizers(runtime)

    {:ok,
     analyzer_options
     |> Keyword.put(:profile, runtime.profile)
     |> Keyword.put(:profile_runtime, runtime)}
  end

  defp scope_runtime_recognizers(opts, %__MODULE__{profile: :balanced} = runtime) do
    {:ok, descriptor} = Profile.fetch(:balanced)
    dynamic = balanced_options(descriptor, runtime.resources.primary, opts)
    Keyword.put(opts, :recognizers, Keyword.fetch!(dynamic, :recognizers))
  end

  defp scope_runtime_recognizers(opts, %__MODULE__{profile: :accurate} = runtime) do
    {:ok, descriptor} = Profile.fetch(:accurate)
    dynamic = accurate_options(descriptor, runtime.resources, opts)
    Keyword.put(opts, :recognizers, Keyword.fetch!(dynamic, :recognizers))
  end

  defp scope_runtime_recognizers(opts, _runtime), do: opts

  defp configure_product(:fast, opts) do
    {:ok, Keyword.put(opts, :profile, :fast)}
  end

  defp configure_product(:balanced, opts) do
    serving = Keyword.get(opts, :serving) || Keyword.get(opts, :primary_serving)

    with :ok <- require_reusable_serving(:balanced, :primary_serving, serving),
         {:ok, descriptor} <- Profile.fetch(:balanced) do
      {:ok,
       descriptor
       |> balanced_options(serving, opts)
       |> Keyword.merge(opts)
       |> Keyword.put(:profile, :balanced)}
    end
  end

  defp configure_product(:accurate, opts) do
    servings = Keyword.get(opts, :servings, %{})
    primary = Keyword.get(opts, :primary_serving) || map_get(servings, :primary)
    location = Keyword.get(opts, :location_serving) || map_get(servings, :location)

    with :ok <- require_reusable_serving(:accurate, :primary_serving, primary),
         :ok <- require_reusable_serving(:accurate, :location_serving, location),
         {:ok, descriptor} <- Profile.fetch(:accurate) do
      {:ok,
       descriptor
       |> accurate_options(%{primary: primary, location: location}, opts)
       |> Keyword.merge(opts)
       |> Keyword.put(:profile, :accurate)}
    end
  end

  defp configure_product(:openmed_pii, opts) do
    serving = Keyword.get(opts, :serving) || Keyword.get(opts, :privacy_filter_serving)

    with :ok <- require_reusable_serving(:openmed_pii, :privacy_filter_serving, serving),
         {:ok, descriptor} <- Profile.fetch(:openmed_pii) do
      {:ok,
       descriptor
       |> openmed_options(serving, opts)
       |> Keyword.merge(opts)
       |> Keyword.put(:profile, :openmed_pii)}
    end
  end

  defp configure_product(:hybrid_gliner_urchade, opts) do
    serving = Keyword.get(opts, :serving) || Keyword.get(opts, :gliner_serving)

    with :ok <- require_reusable_serving(:hybrid_gliner_urchade, :gliner_serving, serving),
         {:ok, descriptor} <- Profile.fetch(:hybrid_gliner_urchade) do
      {:ok,
       descriptor
       |> gliner_urchade_options(serving, opts)
       |> Keyword.merge(opts)
       |> Keyword.put(:profile, :hybrid_gliner_urchade)}
    end
  end

  defp balanced_options(descriptor, serving, opts) do
    entities = Keyword.get(opts, :entities, descriptor.supported_entities)
    model_entities = Enum.filter(entities, &(&1 in [:person, :organization, :location]))

    recognizers =
      if model_entities == [] do
        [:default]
      else
        ner_opts = model_ner_options(serving, model_entities, opts)
        [:default, {NER, ner_opts}]
      end

    descriptor
    |> base_options()
    |> Keyword.put(:entities, entities)
    |> Keyword.put(:recognizers, recognizers)
    |> Keyword.put(:recognizer_timeout, Keyword.get(opts, :recognizer_timeout, 60_000))
  end

  defp accurate_options(descriptor, resources, opts) do
    entities = Keyword.get(opts, :entities, descriptor.supported_entities)

    primary_opts = model_ner_options(resources.primary, [:person, :organization, :location], opts)

    location_opts =
      resources.location
      |> model_ner_options([:location], opts)
      |> Keyword.put(:per_label_thresholds, %{
        "LOC" => @accurate_cascade_policy[:cascade_secondary_threshold]
      })

    descriptor
    |> base_options()
    |> Keyword.put(:entities, entities)
    |> Keyword.put(
      :recognizers,
      Routing.tner_jean_cascade_recognizers(
        entities,
        primary_opts,
        location_opts,
        @accurate_cascade_policy
      )
    )
    |> Keyword.put(:recognizer_timeout, Keyword.get(opts, :recognizer_timeout, 120_000))
  end

  defp openmed_options(descriptor, serving, opts) do
    descriptor
    |> base_options()
    |> Keyword.put(:built_ins, false)
    |> Keyword.put(:recognizers, [{PrivacyFilterNative, [serving: serving]}])
    |> Keyword.put(:recognizer_timeout, Keyword.get(opts, :recognizer_timeout, 300_000))
    |> Keyword.put(:conflict_strategy, :none)
  end

  defp gliner_urchade_options(descriptor, serving, opts) do
    gliner_opts =
      serving
      |> gliner_recognizer_options(opts)
      |> Keyword.put(:model, :urchade_gliner_multi_pii_v1)
      |> Keyword.put(:label_profile, :open_class)

    descriptor
    |> base_options()
    |> Keyword.put(:recognizers, [:default, {GLiNER, gliner_opts}])
    |> Keyword.put(:recognizer_timeout, Keyword.get(opts, :recognizer_timeout, 120_000))
  end

  defp base_options(descriptor) do
    [
      profile: descriptor.name,
      entities: descriptor.supported_entities
    ]
  end

  defp model_ner_options(%NERServing{} = serving, entities, opts) do
    serving.model_spec.policy
    |> Keyword.put(:serving, serving)
    |> Keyword.put(:label_map, serving.model_spec.label_map)
    |> Keyword.put_new(:aggregation_strategy, serving.model_spec.aggregation)
    |> Keyword.put_new(:alignment_mode, :expand)
    |> Keyword.put_new(:score_threshold, Keyword.get(opts, :score_threshold, 0.7))
    |> Keyword.put(:entities, entities)
  end

  defp model_ner_options(serving, entities, opts) do
    opts
    |> Keyword.get(:ner, [])
    |> Keyword.put(:serving, serving)
    |> Keyword.put(:entities, entities)
  end

  defp privacy_filter_serving_options(opts) do
    [
      checkpoint:
        Keyword.get(opts, :checkpoint) ||
          Keyword.get(opts, :privacy_filter_checkpoint) ||
          System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT"),
      pad_windows: Keyword.get(opts, :pad_windows, false),
      trim_span_whitespace: true,
      discard_overlapping_spans: true
    ]
    |> Keyword.merge(OpenMedPolicy.effective_options(opts))
    |> maybe_put(:backend, Keyword.get(opts, :backend) || Keyword.get(opts, :real_model_backend))
    |> maybe_put(:stage_observer, Keyword.get(opts, :stage_observer))
    |> maybe_put(:label_map, Keyword.get(opts, :privacy_filter_label_map))
  end

  defp gliner_serving_options(opts) do
    opts
    |> Keyword.put(:model, :urchade_gliner_multi_pii_v1)
    |> Keyword.put(:label_profile, :open_class)
    |> Keyword.put_new(:execution_providers, [:cpu])
    |> Keyword.put_new(:threshold, Keyword.get(opts, :gliner_threshold, 0.5))
    |> Keyword.put_new(
      :per_label_thresholds,
      Keyword.get(opts, :gliner_per_label_thresholds, @urchade_thresholds)
    )
    |> Keyword.put_new(:flat_ner, Keyword.get(opts, :gliner_flat_ner, true))
    |> Keyword.put_new(:multi_label, Keyword.get(opts, :gliner_multi_label, false))
  end

  defp gliner_recognizer_options(serving, opts) do
    [
      serving: serving,
      threshold: Keyword.get(opts, :gliner_threshold, Keyword.get(opts, :threshold, 0.5)),
      per_label_thresholds:
        Keyword.get(
          opts,
          :gliner_per_label_thresholds,
          Keyword.get(opts, :per_label_thresholds, @urchade_thresholds)
        ),
      flat_ner: Keyword.get(opts, :gliner_flat_ner, Keyword.get(opts, :flat_ner, true)),
      multi_label: Keyword.get(opts, :gliner_multi_label, Keyword.get(opts, :multi_label, false))
    ]
  end

  defp privacy_filter_metadata(serving) do
    %{
      backend: Map.get(serving, :backend, :default),
      backend_metadata: Map.get(serving, :backend_metadata, %{}),
      checkpoint_configured: not is_nil(Map.get(serving, :checkpoint)),
      openmed_optimization: privacy_filter_optimization_metadata(serving)
    }
  end

  defp privacy_filter_optimization_metadata(%PrivacyFilterServing{} = serving),
    do: OpenMedPolicy.metadata(serving)

  defp privacy_filter_optimization_metadata(_custom_serving), do: OpenMedPolicy.default_metadata()

  defp build_ner_serving(opts) do
    builder = Keyword.get(opts, :ner_serving_builder, &NERServing.build/1)

    contextual_observer =
      case Keyword.get(opts, :stage_observer) do
        observer when is_function(observer, 1) ->
          fn event ->
            observer.(
              Map.merge(event, %{
                model: Keyword.fetch!(opts, :model),
                model_index: Keyword.get(opts, :model_index, 1),
                model_count: Keyword.get(opts, :model_count, 1)
              })
            )
          end

        _observer ->
          nil
      end

    opts
    |> Keyword.put(:stage_observer, contextual_observer)
    |> builder.()
  end

  defp build_privacy_filter_serving(serving_opts, opts) do
    builder = Keyword.get(opts, :privacy_filter_serving_builder, &PrivacyFilterServing.build/1)
    builder.(serving_opts)
  end

  defp build_gliner_serving(serving_opts, opts) do
    builder = Keyword.get(opts, :gliner_serving_builder, &GLiNEROrtex.build/1)
    builder.(serving_opts)
  end

  defp ner_serving_metadata(%NERServing{} = serving), do: NERServing.metadata(serving)
  defp ner_serving_metadata(_serving), do: %{backend: :test_or_custom}

  defp gliner_metadata(%GLiNEROrtex{} = serving) do
    %{
      adapter: :ortex,
      backend: gliner_backend(serving.execution_providers),
      model: serving.model_spec.id,
      execution_providers: serving.execution_providers,
      provider_metadata: serving.provider_metadata
    }
  end

  defp gliner_metadata(_serving),
    do: %{adapter: :ortex, backend: :test_or_custom, execution_providers: [:cpu]}

  defp gliner_backend([:cpu]), do: :cpu
  defp gliner_backend(_providers), do: :provider_dependent

  defp runtime(descriptor, resources, analyzer_options, backend_metadata) do
    %__MODULE__{
      profile: descriptor.name,
      implementation_profile: descriptor.implementation_profile,
      resources: resources,
      analyzer_options: analyzer_options,
      prepared_at: DateTime.utc_now(),
      backend_metadata: backend_metadata
    }
  end

  defp require_reusable_serving(profile, asset, nil) do
    {:error,
     Diagnostic.new(:missing_model_asset,
       profile: profile,
       component: :profile_runtime,
       asset: asset,
       message: "The #{profile} profile requires a reusable #{asset}.",
       remediation: "Call Obscura.Profile.prepare/2 or pass the prepared serving explicitly."
     )}
  end

  defp require_reusable_serving(_profile, _asset, _serving), do: :ok

  defp serving_diagnostic(descriptor, {:missing_optional_dependency, dependency}) do
    Diagnostic.new(:missing_optional_dependency,
      profile: descriptor.name,
      component: :profile_runtime,
      dependency: dependency,
      message: "The #{descriptor.name} profile requires the #{dependency} dependency."
    )
  end

  defp serving_diagnostic(descriptor, {code, _reason} = reason)
       when code in [
              :missing_model_asset,
              :missing_tokenizer_asset,
              :model_download_interrupted,
              :model_load_failed,
              :tokenizer_load_failed,
              :serving_build_failed
            ] do
    Diagnostic.new(code,
      profile: descriptor.name,
      component: :profile_runtime,
      cause: reason
    )
  end

  defp serving_diagnostic(descriptor, {:unsupported_real_model_backend, _supported} = reason) do
    Diagnostic.new(:unsupported_backend,
      profile: descriptor.name,
      component: :profile_runtime,
      cause: reason
    )
  end

  defp serving_diagnostic(descriptor, {code, _backend, _reason} = reason)
       when code in [:backend_configuration_failed, :compiler_start_failed] do
    Diagnostic.new(:backend_unavailable,
      profile: descriptor.name,
      component: :profile_runtime,
      cause: reason
    )
  end

  defp serving_diagnostic(descriptor, reason) do
    Diagnostic.new(:serving_build_failed,
      profile: descriptor.name,
      component: :profile_runtime,
      cause: reason,
      message: "Could not prepare the #{descriptor.name} profile runtime."
    )
  end

  defp map_get(map, key) when is_map(map), do: Map.get(map, key)
  defp map_get(_map, _key), do: nil

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
