defmodule Obscura.Recognizer.GLiNER.Ortex do
  @moduledoc """
  Optional Ortex-backed serving for GLiNER span models.
  """

  alias Obscura.Recognizer.Batch
  alias Obscura.Recognizer.GLiNER.AdapterSupport
  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.Decoder
  alias Obscura.Recognizer.GLiNER.Inputs
  alias Obscura.Recognizer.GLiNER.ModelRegistry
  alias Obscura.Recognizer.GLiNER.Ortex.CoreML

  defstruct [
    :model,
    :tokenizer,
    :config,
    :model_spec,
    :paths,
    :runtime_module,
    :profile_prefix,
    :provider_metadata,
    execution_providers: [:cpu]
  ]

  @type t :: %__MODULE__{}

  @doc """
  Builds an Ortex GLiNER serving from local model assets.
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, term()}
  def build(opts \\ []) do
    deps = Keyword.get(opts, :dependency_checker, &Code.ensure_loaded?/1)

    with :ok <- ensure_dependency(deps, Module.concat([Ortex]), :ortex),
         :ok <- ensure_dependency(deps, Module.concat([Tokenizers, Tokenizer]), :tokenizers),
         {:ok, config} <- Config.new(opts),
         {:ok, spec} <- ModelRegistry.fetch(config.model),
         {:ok, paths} <- ModelRegistry.resolve_paths(spec, opts),
         {:ok, model_config} <- Config.from_model_config_file(paths.config_path, config),
         {:ok, tokenizer} <- load_tokenizer(paths.tokenizer_path),
         {:ok, provider_config} <- provider_config(opts),
         {:ok, model} <-
           load_model(paths.onnx_path, provider_config) do
      {:ok,
       %__MODULE__{
         model: model,
         tokenizer: tokenizer,
         config: model_config,
         model_spec: spec,
         paths: paths,
         runtime_module: provider_config.runtime_module,
         profile_prefix: provider_config.profile_prefix,
         provider_metadata: provider_config.metadata,
         execution_providers: provider_config.execution_providers
       }}
    end
  end

  @doc """
  Runs GLiNER inference for one text.
  """
  @spec run(t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def run(%__MODULE__{} = serving, text, opts \\ []) when is_binary(text) do
    config = AdapterSupport.merge_config(serving.config, opts)

    with {:ok, prepared} <- Inputs.prepare(serving.tokenizer, text, config),
         {:ok, output} <-
           run_model(serving.runtime_module, serving.model, prepared.tensors),
         {:ok, logits} <- output_logits(output) do
      Decoder.decode(logits, prepared, config, text)
    end
  end

  @doc """
  Runs GLiNER inference for many texts.
  """
  @spec run_many(t(), [String.t()], keyword()) :: {:ok, [[map()]]} | {:error, term()}
  def run_many(%__MODULE__{} = serving, texts, opts \\ []) when is_list(texts) do
    Batch.run_many(texts, &run(serving, &1, opts))
  end

  @doc """
  Flushes an enabled ONNX Runtime profile and summarizes execution-provider use.

  CoreML participation proves that ONNX Runtime assigned work to CoreML. It does
  not prove GPU-only execution because CoreML has no GPU-only compute-unit mode.
  """
  @spec finish_profiling(t()) :: {:ok, map()} | {:error, term()}
  def finish_profiling(%__MODULE__{profile_prefix: nil}),
    do: {:error, :ortex_profiling_not_enabled}

  def finish_profiling(%__MODULE__{} = serving) do
    runtime = serving.runtime_module

    if function_exported?(runtime, :end_profiling, 1) do
      profile_path = runtime.end_profiling(serving.model)
      CoreML.summarize_profile(profile_path)
    else
      {:error, {:unsupported_ortex_capability, :profiling}}
    end
  rescue
    error -> {:error, {:ortex_profiling_failed, error.__struct__, Exception.message(error)}}
  end

  defp ensure_dependency(checker, module, app) do
    if checker.(module), do: :ok, else: {:error, {:missing_optional_dependency, app}}
  end

  defp load_tokenizer(path) do
    Tokenizers.Tokenizer.from_file(path)
  rescue
    error -> {:error, {:gliner_tokenizer_load_failed, error.__struct__}}
  end

  defp load_model(path, %{mode: :legacy} = config) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    {:ok, apply(config.runtime_module, :load, [path, config.execution_providers])}
  rescue
    error -> {:error, {:gliner_onnx_load_failed, error.__struct__, Exception.message(error)}}
  end

  defp load_model(path, %{mode: :structured} = config) do
    runtime = config.runtime_module

    if function_exported?(runtime, :load_with_options, 3) do
      opts =
        [optimization_level: config.optimization_level]
        |> maybe_put(:profile_prefix, config.profile_prefix)

      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      {:ok, apply(runtime, :load_with_options, [path, config.providers, opts])}
    else
      {:error, {:unsupported_ortex_capability, :structured_coreml_options}}
    end
  rescue
    error -> {:error, {:gliner_onnx_load_failed, error.__struct__, Exception.message(error)}}
  end

  defp run_model(runtime_module, model, tensors) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    {:ok, apply(runtime_module, :run, [model, tensors])}
  rescue
    error -> {:error, {:gliner_onnx_run_failed, error.__struct__}}
  end

  defp output_logits({logits}), do: {:ok, logits}
  defp output_logits(logits) when is_struct(logits, Nx.Tensor), do: {:ok, logits}
  defp output_logits(_other), do: {:error, :unsupported_gliner_ortex_output}

  defp provider_config(opts) do
    execution_providers = Keyword.get(opts, :execution_providers, [:cpu])
    runtime_module = Keyword.get(opts, :ortex_module, Module.concat([Ortex]))
    profile_prefix = Keyword.get(opts, :profile_prefix)
    optimization_level = Keyword.get(opts, :optimization_level, 3)

    if :coreml in execution_providers do
      with {:ok, coreml_options} <-
             opts |> Keyword.get(:coreml_options, []) |> CoreML.validate_options(),
           :ok <- ensure_profile_parent(profile_prefix) do
        providers = Enum.map(execution_providers, &provider_options(&1, coreml_options))

        {:ok,
         %{
           mode: :structured,
           runtime_module: runtime_module,
           execution_providers: execution_providers,
           providers: providers,
           profile_prefix: profile_prefix,
           optimization_level: optimization_level,
           metadata: %{
             requested_execution_providers: execution_providers,
             coreml_options: Map.new(coreml_options),
             verification: if(profile_prefix, do: :pending_profile, else: :not_profiled),
             gpu_only_claim_allowed: false
           }
         }}
      end
    else
      {:ok,
       %{
         mode: :legacy,
         runtime_module: runtime_module,
         execution_providers: execution_providers,
         profile_prefix: nil,
         metadata: %{
           requested_execution_providers: execution_providers,
           verification: if(execution_providers == [:cpu], do: :cpu_only, else: :not_profiled)
         }
       }}
    end
  end

  defp ensure_profile_parent(nil), do: :ok

  defp ensure_profile_parent(path) when is_binary(path) do
    path |> Path.dirname() |> File.mkdir_p()
  end

  defp ensure_profile_parent(path), do: {:error, {:invalid_ortex_profile_prefix, path}}

  defp provider_options(:coreml, options), do: {:coreml, options}
  defp provider_options(provider, _options), do: provider

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)
end
