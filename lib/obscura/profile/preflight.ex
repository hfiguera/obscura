defmodule Obscura.Profile.Preflight do
  @moduledoc """
  Report-safe readiness checks for product profiles.

  Preflight never analyzes source text. By default it performs local checks
  only. Passing `prepare: true` explicitly permits model/runtime preparation,
  which may consult the configured model cache or network.
  """

  alias Obscura.Diagnostic
  alias Obscura.PrivacyFilter.Checkpoint
  alias Obscura.Profile
  alias Obscura.Profile.Cache
  alias Obscura.Recognizer.NER.Backend

  @type report :: map()

  @doc """
  Checks a stable or experimental product profile and returns a JSON-safe report.
  """
  @spec run(Profile.name() | String.t(), keyword()) ::
          {:ok, report()} | {:error, Diagnostic.t(), report()}
  def run(profile, opts \\ []) when is_list(opts) do
    with {:ok, descriptor} <- Profile.fetch(profile),
         {:ok, backend} <- normalize_backend(descriptor, opts),
         :ok <- validate_backend(descriptor, backend, opts),
         :ok <- validate_checkpoint(descriptor, opts),
         {:ok, runtime_metadata} <- validate_or_prepare(descriptor, opts) do
      {:ok, build_report(descriptor, backend, runtime_metadata, nil, opts)}
    else
      {:error, %Diagnostic{} = diagnostic} ->
        {:error, diagnostic, failure_report(profile, diagnostic, opts)}
    end
  end

  defp validate_or_prepare(descriptor, opts) do
    if Keyword.get(opts, :prepare, false) do
      case Profile.prepare(descriptor.name, runtime_options(opts)) do
        {:ok, runtime} -> {:ok, runtime.backend_metadata}
        {:error, reason} -> {:error, reason}
      end
    else
      case Profile.validate_runtime(descriptor.name, runtime_options(opts)) do
        :ok -> {:ok, %{prepared: false}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp normalize_backend(%Profile{backend_policy: :none}, _opts), do: {:ok, :none}
  defp normalize_backend(%Profile{backend_policy: :ortex_cpu}, _opts), do: {:ok, :ortex_cpu}

  defp normalize_backend(_descriptor, opts) do
    value =
      Keyword.get(opts, :real_model_backend) ||
        Keyword.get(opts, :backend) ||
        System.get_env("OBSCURA_REAL_MODEL_BACKEND")

    case Backend.normalize(value) do
      {:ok, backend} -> {:ok, backend}
      {:error, reason} -> {:error, backend_diagnostic(reason)}
    end
  end

  defp validate_backend(%Profile{backend_policy: :none}, :none, _opts), do: :ok
  defp validate_backend(%Profile{backend_policy: :ortex_cpu}, :ortex_cpu, _opts), do: :ok
  defp validate_backend(_descriptor, :default, _opts), do: :ok
  defp validate_backend(_descriptor, :binary, opts), do: require_module(Nx, :nx, :binary, opts)
  defp validate_backend(_descriptor, :exla, opts), do: require_module(EXLA, :exla, :exla, opts)

  defp validate_backend(_descriptor, :emily, opts) do
    with :ok <- require_module(Emily, :emily, :emily, opts),
         :ok <- require_module(Emily.Backend, :emily, :emily, opts) do
      require_module(Emily.Compiler, :emily, :emily, opts)
    end
  end

  defp require_module(module, dependency, backend, opts) do
    checker = Keyword.get(opts, :module_checker, &Code.ensure_loaded?/1)

    if checker.(module) do
      :ok
    else
      {:error,
       Diagnostic.new(:backend_unavailable,
         component: :profile_preflight,
         dependency: dependency,
         backend: backend,
         message: "The requested #{backend} backend is not available."
       )}
    end
  end

  defp validate_checkpoint(%Profile{name: :openmed_pii}, opts) do
    checkpoint = checkpoint(opts)
    serving = Keyword.get(opts, :serving) || Keyword.get(opts, :privacy_filter_serving)

    cond do
      not is_nil(serving) ->
        :ok

      not is_binary(checkpoint) or checkpoint == "" ->
        :ok

      true ->
        case Checkpoint.validate(checkpoint, metadata_only: true) do
          {:ok, _summary} -> :ok
          {:error, reason} -> {:error, checkpoint_diagnostic(reason)}
        end
    end
  end

  defp validate_checkpoint(_descriptor, _opts), do: :ok

  defp checkpoint_diagnostic({:checkpoint_dir_not_found, _path}) do
    Diagnostic.new(:missing_checkpoint,
      component: :privacy_filter,
      asset: :checkpoint,
      message: "The configured privacy-filter checkpoint directory does not exist."
    )
  end

  defp checkpoint_diagnostic({:missing_checkpoint_config, _path}) do
    Diagnostic.new(:missing_model_config,
      component: :privacy_filter,
      asset: :config,
      message: "The privacy-filter checkpoint is missing config.json."
    )
  end

  defp checkpoint_diagnostic({:incomplete_safetensors_file, _path}) do
    Diagnostic.new(:checkpoint_incomplete,
      component: :privacy_filter,
      asset: :weights,
      message: "The privacy-filter checkpoint contains incomplete model weights."
    )
  end

  defp checkpoint_diagnostic(reason) do
    Diagnostic.new(:checkpoint_layout_mismatch,
      component: :privacy_filter,
      asset: :checkpoint,
      cause: reason,
      message: "The privacy-filter checkpoint does not match a supported layout."
    )
  end

  defp backend_diagnostic({:unsupported_real_model_backend, supported}) do
    Diagnostic.new(:unsupported_backend,
      component: :profile_preflight,
      message: "The requested model backend is not supported.",
      metadata: %{supported: supported}
    )
  end

  defp build_report(descriptor, backend, runtime_metadata, diagnostic, opts) do
    %{
      status: :ready,
      profile: descriptor.name,
      stability: descriptor.stability,
      implementation_profile: descriptor.implementation_profile,
      supported_entities: descriptor.supported_entities,
      requirements: requirement_map(descriptor),
      effective_configuration: effective_configuration(descriptor, backend, opts),
      runtime: runtime_metadata,
      warnings: warnings(descriptor, opts),
      diagnostic: diagnostic
    }
  end

  defp failure_report(profile, diagnostic, opts) do
    case Profile.fetch(profile) do
      {:ok, descriptor} ->
        backend = effective_backend(opts)

        %{
          build_report(descriptor, backend, %{}, Diagnostic.to_map(diagnostic), opts)
          | status: :error
        }

      {:error, _reason} ->
        %{
          status: :error,
          profile: safe_profile(profile),
          stability: nil,
          implementation_profile: nil,
          supported_entities: [],
          requirements: %{},
          effective_configuration: %{},
          runtime: %{},
          warnings: [],
          diagnostic: Diagnostic.to_map(diagnostic)
        }
    end
  end

  defp requirement_map(descriptor) do
    %{
      required_dependencies: descriptor.required_dependencies,
      optional_dependencies: descriptor.optional_dependencies,
      required_assets: descriptor.required_assets,
      default_models: descriptor.default_models,
      backend_policy: descriptor.backend_policy,
      automatic_download: descriptor.automatic_download
    }
  end

  defp effective_configuration(descriptor, backend, opts) do
    {_cache_directory, cache_directory_source} = Cache.effective_directory(opts)

    %{
      backend: backend,
      backend_source: backend_source(opts),
      emily_device:
        Keyword.get(opts, :emily_device, System.get_env("OBSCURA_EMILY_DEVICE", "gpu")),
      fallback_policy:
        Keyword.get(opts, :emily_fallback, System.get_env("OBSCURA_EMILY_FALLBACK", "raise")),
      compile: Keyword.get(opts, :compile),
      checkpoint_configured: not is_nil(checkpoint(opts)),
      preparation_requested: Keyword.get(opts, :prepare, false),
      allow_download: Keyword.get(opts, :allow_download, false),
      offline: Keyword.get(opts, :offline, false),
      preparation_timeout: Keyword.get(opts, :timeout),
      preparation_inactivity_timeout: Keyword.get(opts, :inactivity_timeout),
      cache_directory_source: cache_directory_source,
      network_may_be_used: network_may_be_used?(descriptor, opts),
      automatic_download: descriptor.automatic_download
    }
  end

  defp runtime_options(opts) do
    opts
    |> Keyword.put_new(:checkpoint, checkpoint(opts))
    |> Keyword.put_new(:real_model_backend, effective_backend(opts))
  end

  defp effective_backend(opts) do
    Keyword.get(opts, :real_model_backend) ||
      Keyword.get(opts, :backend) ||
      System.get_env("OBSCURA_REAL_MODEL_BACKEND") ||
      :default
  end

  defp backend_source(opts) do
    cond do
      Keyword.has_key?(opts, :real_model_backend) or Keyword.has_key?(opts, :backend) -> :option
      System.get_env("OBSCURA_REAL_MODEL_BACKEND") not in [nil, ""] -> :environment
      true -> :default
    end
  end

  defp checkpoint(opts) do
    Keyword.get(opts, :checkpoint) ||
      Keyword.get(opts, :privacy_filter_checkpoint) ||
      System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
  end

  defp warnings(%Profile{name: :fast}, _opts) do
    ["Parser-backed phone validity depends on caller-selected regions when enabled."]
  end

  defp warnings(%Profile{name: :balanced}, opts) do
    fallback_warning(opts) ++
      [
        "The profile implementation is stable, but Obscura does not distribute or license the optional TNER checkpoint; the deployer must review and accept its terms before use."
      ]
  end

  defp warnings(%Profile{name: :accurate}, opts) do
    fallback_warning(opts) ++
      [
        "This stable profile loads two large models and conditionally runs the Jean-Baptiste location specialist when TNER returns no accepted location.",
        "It has the highest measured general accuracy, but balanced remains the practical recommendation because it uses one model and has lower latency.",
        "Obscura does not distribute or license the optional TNER or Jean-Baptiste assets; the deployer must review and accept their terms before use."
      ]
  end

  defp warnings(%Profile{name: :openmed_pii}, opts) do
    fallback_warning(opts) ++
      [
        "This profile is experimental and is not a general-purpose recommendation.",
        "OpenMed checkpoint licensing and Python-reference parity must be reviewed for the deployment."
      ]
  end

  defp warnings(%Profile{name: :hybrid_gliner_urchade}, _opts) do
    [
      "This CPU-only profile is experimental and is recommended only when a GPU-free, license-clearer general NER option is preferred over the best measured accuracy.",
      "Its exact F1 is lower than balanced on all three shared datasets, and its ONNX/tokenizer/config assets must be exported and prepared explicitly."
    ]
  end

  defp network_may_be_used?(%Profile{name: :hybrid_gliner_urchade}, _opts), do: false

  defp network_may_be_used?(%Profile{name: name}, opts) do
    name in [:balanced, :accurate] and
      Keyword.get(opts, :prepare, false) and
      Keyword.get(opts, :allow_download, false) and
      not Keyword.get(opts, :offline, false)
  end

  defp fallback_warning(opts) do
    fallback =
      Keyword.get(opts, :emily_fallback, System.get_env("OBSCURA_EMILY_FALLBACK", "raise"))

    if to_string(fallback) == "raise" do
      []
    else
      ["Backend fallback is not set to raise, so accelerator claims require additional proof."]
    end
  end

  defp safe_profile(profile) when is_atom(profile) or is_binary(profile), do: profile
  defp safe_profile(_profile), do: "invalid"
end
