defmodule Obscura.Recognizer.GLiNER.Native do
  @moduledoc """
  Experimental native Nx/Emily serving for the pinned Urchade GLiNER model.

  This adapter requires an explicit local Safetensors export and never downloads
  model assets. Both Emily backend fallback and compiler fallback are forced to
  `:raise`, so successful inference is evidence of native execution rather than
  silent evaluator or BinaryBackend fallback.
  """

  alias Obscura.Recognizer.Batch
  alias Obscura.Recognizer.GLiNER.AdapterSupport
  alias Obscura.Recognizer.GLiNER.Config
  alias Obscura.Recognizer.GLiNER.Decoder
  alias Obscura.Recognizer.GLiNER.Inputs
  alias Obscura.Recognizer.GLiNER.ModelRegistry
  alias Obscura.Recognizer.GLiNER.Native.Input
  alias Obscura.Recognizer.GLiNER.Native.Model
  alias Obscura.Recognizer.GLiNER.Native.Weights

  @model :urchade_gliner_multi_pii_v1
  @model_revision "1fcf13e85f4eef5394e1fcd406cf2ca9ea82351d"
  @default_shape_buckets [
    {24, 12},
    {32, 16},
    {48, 24},
    {64, 32},
    {80, 48},
    {96, 64},
    {128, 96},
    {192, 128},
    {256, 192},
    {384, 256},
    {576, 384},
    {768, 512},
    {1024, 768},
    {1152, 768}
  ]

  defstruct [
    :tokenizer,
    :config,
    :model_spec,
    :paths,
    :params,
    :compiled,
    :trace_compiled,
    :shape_buckets,
    :backend,
    :compiler,
    :metadata
  ]

  @type t :: %__MODULE__{}

  @doc """
  Builds a strict Emily GPU serving from a local native Urchade export.
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, term()}
  def build(opts \\ []) do
    model = Keyword.get(opts, :model, @model)

    with :ok <- require_model(model),
         {:ok, shape_buckets} <- shape_buckets(opts),
         :ok <- ensure_dependency(Module.concat(["Nx"]), :nx, opts),
         :ok <- ensure_dependency(Module.concat(["Safetensors"]), :safetensors, opts),
         :ok <- ensure_dependency(Module.concat(["Tokenizers", "Tokenizer"]), :tokenizers, opts),
         {:ok, runtime} <- configure_emily(opts),
         {:ok, config} <- Config.new(Keyword.put(opts, :model, model)),
         {:ok, spec} <- ModelRegistry.fetch(model),
         {:ok, paths} <- ModelRegistry.resolve_native_paths(spec, opts),
         {:ok, model_config} <- Config.from_model_config_file(paths.config_path, config),
         :ok <- validate_config(model_config),
         {:ok, manifest} <- validate_manifest(paths, opts),
         {:ok, tokenizer} <- load_tokenizer(paths.tokenizer_path),
         {:ok, params} <- Weights.load(paths.weights_path, runtime.backend, opts),
         {:ok, compiled} <- compile(&Model.forward/2, runtime, opts),
         {:ok, trace_compiled} <- compile(&Model.trace/2, runtime, opts) do
      {:ok,
       %__MODULE__{
         tokenizer: tokenizer,
         config: model_config,
         model_spec: spec,
         paths: paths,
         params: params,
         compiled: compiled,
         trace_compiled: trace_compiled,
         shape_buckets: shape_buckets,
         backend: runtime.backend,
         compiler: runtime.compiler,
         metadata: %{
           adapter: __MODULE__,
           model: model,
           model_revision: @model_revision,
           backend: :emily,
           device: runtime.device,
           native: true,
           fuse: false,
           backend_fallback: :raise,
           compiler_fallback: :raise,
           manifest_sha256: manifest.sha256,
           weights_sha256: manifest.weights_sha256,
           shape_buckets: shape_buckets
         }
       }}
    end
  end

  @doc """
  Runs native GLiNER inference for one text.
  """
  @spec run(t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def run(%__MODULE__{} = serving, text, opts \\ []) when is_binary(text) do
    config = AdapterSupport.merge_config(serving.config, opts)

    with {:ok, prepared} <- Inputs.prepare(serving.tokenizer, text, config),
         {:ok, input} <-
           Input.build(prepared, config,
             shape_buckets: serving.shape_buckets,
             max_width: config.max_width
           ),
         {:ok, logits} <- execute(serving, input, serving.compiled),
         {:ok, spans} <- Decoder.decode(logits, prepared, config, text) do
      {:ok, Enum.map(spans, &native_metadata/1)}
    end
  end

  @doc """
  Runs native GLiNER inference for multiple texts while reusing one serving.
  """
  @spec run_many(t(), [String.t()], keyword()) :: {:ok, [[map()]]} | {:error, term()}
  def run_many(%__MODULE__{} = serving, texts, opts \\ []) when is_list(texts) do
    Batch.run_many(texts, &run(serving, &1, opts))
  end

  @doc false
  @spec trace(t(), String.t(), keyword()) :: {:ok, map(), map()} | {:error, term()}
  def trace(%__MODULE__{} = serving, text, opts \\ []) do
    config = AdapterSupport.merge_config(serving.config, opts)

    with {:ok, prepared} <- Inputs.prepare(serving.tokenizer, text, config),
         {:ok, input} <-
           Input.build(prepared, config, shape_buckets: false, max_width: config.max_width),
         {:ok, {trace, logits}} <- execute(serving, input, serving.trace_compiled) do
      {:ok, Map.put(trace, "logits", logits), prepared}
    end
  end

  defp execute(serving, input, compiled) do
    input = Nx.backend_transfer(input, serving.backend)
    result = compiled.(input, serving.params)
    assert_backend(result, serving.backend)
  rescue
    error -> {:error, {:gliner_native_run_failed, error.__struct__, Exception.message(error)}}
  end

  defp assert_backend(result, {backend_module, _options}) do
    tensor =
      cond do
        is_struct(result, Nx.Tensor) -> result
        is_map(result) -> result["logits"]
        is_tuple(result) -> elem(result, tuple_size(result) - 1)
      end

    tensor =
      if is_map(tensor) and not is_struct(tensor, Nx.Tensor), do: tensor["logits"], else: tensor

    actual = tensor |> Map.fetch!(:data) |> Map.fetch!(:__struct__)

    if actual == backend_module,
      do: {:ok, result},
      else: {:error, {:gliner_native_backend_mismatch, backend_module, actual}}
  end

  defp require_model(@model), do: :ok
  defp require_model(model), do: {:error, {:native_gliner_not_supported, model}}

  defp ensure_dependency(module, dependency, opts) do
    checker = Keyword.get(opts, :dependency_checker, &Code.ensure_loaded?/1)

    case checker.(module) do
      true -> :ok
      false -> {:error, {:missing_optional_dependency, dependency}}
    end
  end

  defp shape_buckets(opts) do
    case Keyword.get(opts, :shape_buckets, @default_shape_buckets) do
      false -> {:ok, false}
      buckets when is_list(buckets) -> validate_shape_buckets(buckets)
      value -> {:error, {:invalid_gliner_native_shape_buckets, value}}
    end
  end

  defp validate_shape_buckets(buckets) do
    ordered? =
      buckets
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [{left_tokens, left_words}, {right_tokens, right_words}] ->
        right_tokens > left_tokens and right_words >= left_words
      end)

    valid? =
      buckets != [] and
        Enum.all?(buckets, fn
          {tokens, words}
          when is_integer(tokens) and tokens > 0 and is_integer(words) and words > 0 ->
            true

          _other ->
            false
        end) and ordered?

    if valid?, do: {:ok, buckets}, else: {:error, {:invalid_gliner_native_shape_buckets, buckets}}
  end

  defp configure_emily(opts) do
    backend = Module.concat(["Emily", "Backend"])
    compiler = Module.concat(["Emily", "Compiler"])

    with :ok <- ensure_dependency(Module.concat(["Emily"]), :emily, opts),
         :ok <- ensure_dependency(backend, :emily, opts),
         :ok <- ensure_dependency(compiler, :emily, opts),
         :ok <- put_emily_policy(opts),
         {:ok, _applications} <- start_application(opts) do
      {:ok, %{backend: {backend, device: :gpu}, compiler: compiler, device: :gpu}}
    end
  end

  defp put_emily_policy(opts) do
    putter = Keyword.get(opts, :application_env_putter, &Application.put_env/3)
    putter.(:emily, :fallback, :raise)
    putter.(:emily, :native_fallback, :raise)
    :ok
  end

  defp start_application(opts) do
    opts
    |> Keyword.get(:application_starter, &Application.ensure_all_started/1)
    |> then(& &1.(:emily))
  end

  defp compile(function, runtime, opts) do
    compiler = Keyword.get(opts, :defn_jit, &Nx.Defn.jit/2)

    {:ok,
     compiler.(function,
       compiler: runtime.compiler,
       device: runtime.device,
       native: true,
       native_fallback: :raise,
       fuse: false
     )}
  rescue
    error -> {:error, {:gliner_native_compile_failed, error.__struct__, Exception.message(error)}}
  end

  defp load_tokenizer(path) do
    Tokenizers.Tokenizer.from_file(path)
  rescue
    error -> {:error, {:gliner_tokenizer_load_failed, error.__struct__}}
  end

  defp validate_config(%Config{} = config) do
    cond do
      config.span_mode != :span_level ->
        {:error, {:unsupported_gliner_span_mode, config.span_mode}}

      config.max_width != 12 ->
        {:error, {:unsupported_gliner_max_width, config.max_width}}

      config.class_token_index != 250_103 ->
        {:error, {:unsupported_gliner_class_token_index, config.class_token_index}}

      true ->
        :ok
    end
  end

  defp validate_manifest(paths, opts) do
    with {:ok, binary} <- File.read(paths.manifest_path),
         {:ok, manifest} <- Jason.decode(binary),
         :ok <- validate_manifest_contract(manifest),
         :ok <-
           maybe_validate_file_hash(manifest, ["weights", "sha256"], paths.weights_path, opts),
         :ok <-
           maybe_validate_file_hash(
             manifest,
             ["assets", "tokenizer.json", "sha256"],
             paths.tokenizer_path,
             opts
           ),
         :ok <-
           maybe_validate_file_hash(
             manifest,
             ["assets", "gliner_config.json", "sha256"],
             paths.config_path,
             opts
           ) do
      {:ok,
       %{
         sha256: sha256_binary(binary),
         weights_sha256: get_in(manifest, ["weights", "sha256"])
       }}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_gliner_native_manifest, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_manifest_contract(manifest) do
    cond do
      Map.get(manifest, "schema_version") != 1 ->
        {:error, :gliner_native_manifest_schema_mismatch}

      get_in(manifest, ["model", "id"]) != "urchade/gliner_multi_pii-v1" ->
        {:error, :gliner_native_manifest_model_mismatch}

      get_in(manifest, ["model", "revision"]) != @model_revision ->
        {:error, :gliner_native_manifest_revision_mismatch}

      get_in(manifest, ["weights", "tensor_count"]) != map_size(Weights.expected_shapes()) ->
        {:error, :gliner_native_manifest_tensor_count_mismatch}

      true ->
        :ok
    end
  end

  defp maybe_validate_file_hash(manifest, hash_path, path, opts) do
    if Keyword.get(opts, :verify_weights_hash, true) do
      expected = get_in(manifest, hash_path)
      actual = sha256_file(path)

      if expected == actual,
        do: :ok,
        else: {:error, {:gliner_native_asset_hash_mismatch, path, expected, actual}}
    else
      :ok
    end
  end

  defp sha256_binary(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp sha256_file(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp native_metadata(span) do
    metadata =
      span.metadata
      |> Map.put(:source, :gliner_native)
      |> Map.put(:adapter, "Obscura.Recognizer.GLiNER.Native")
      |> Map.put(:backend, :emily)
      |> Map.put(:device, :gpu)
      |> Map.put(:fallback, :raise)

    %{span | metadata: metadata}
  end
end
