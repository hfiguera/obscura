defmodule Obscura.Recognizer.NER.Serving do
  @moduledoc """
  Optional Nx/Bumblebee serving builder for local token-classification models.

  Model serving remains explicit. Default Obscura usage does not load model
  dependencies or download weights. Calling `build/1` is an opt-in local model
  setup path.
  """

  alias Obscura.Recognizer.NER.Backend
  alias Obscura.Recognizer.NER.ModelRegistry
  alias Obscura.Recognizer.NER.ModelSpec
  alias Obscura.Serving.StageTiming
  alias Obscura.Telemetry

  @enforce_keys [:serving, :model_spec]
  defstruct [
    :serving,
    :model_spec,
    :tokenizer,
    :sequence_length,
    :backend,
    :backend_metadata,
    :built_at
  ]

  @type t :: %__MODULE__{
          serving: term(),
          model_spec: ModelSpec.t(),
          tokenizer: term() | nil,
          sequence_length: pos_integer() | nil,
          backend: atom() | nil,
          backend_metadata: map() | nil,
          built_at: DateTime.t() | nil
        }

  @doc """
  Builds a NER serving when optional model dependencies are available.
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, term()}
  def build(opts \\ []) do
    start = System.monotonic_time()
    opts = Keyword.put_new(opts, :model, :dslim_bert_base_ner)
    observer = Keyword.get(opts, :stage_observer)

    result =
      with {:ok, spec} <-
             measured(:model_registry, observer, fn ->
               ModelRegistry.fetch(Keyword.fetch!(opts, :model), opts)
             end),
           {:ok, opts} <-
             measured(:backend_configuration, observer, fn -> Backend.configure(opts) end),
           :ok <-
             measured(:dependency_validation, observer, fn -> validate_dependencies(opts) end),
           :ok <- measured(:compiler_start, observer, fn -> maybe_start_compiler(opts) end),
           {:ok, model_info} <-
             measured(:model_load, observer, fn -> load_model(spec, opts) end),
           {:ok, tokenizer} <-
             measured(:tokenizer_load, observer, fn -> load_tokenizer(spec, opts) end),
           {:ok, serving} <-
             measured(:serving_construction, observer, fn ->
               build_token_classification(model_info, tokenizer, spec, opts)
             end) do
        {:ok,
         %__MODULE__{
           serving: serving,
           model_spec: spec,
           tokenizer: tokenizer,
           sequence_length: opts |> Keyword.get(:compile, []) |> Keyword.get(:sequence_length),
           backend: Keyword.get(opts, :backend),
           backend_metadata: Backend.metadata(opts),
           built_at: DateTime.utc_now()
         }}
      end

    emit_build(start, result, opts)
    result
  end

  @doc """
  Returns telemetry-safe metadata for a built serving.
  """
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{
        model_spec: spec,
        backend: backend,
        backend_metadata: backend_metadata
      }) do
    spec
    |> ModelSpec.metadata()
    |> Map.put(:backend, backend || :default)
    |> Map.put(:backend_metadata, backend_metadata || %{})
  end

  defp validate_dependencies(opts) do
    with :ok <- ensure_dependency(Module.concat([Nx, "Serving"]), :nx, opts),
         :ok <- ensure_dependency(Bumblebee, :bumblebee, opts) do
      ensure_dependency(Module.concat([Bumblebee, "Text"]), :bumblebee, opts)
    end
  end

  defp ensure_dependency(module, dependency, opts) do
    if dependency_available?(module, opts) do
      :ok
    else
      {:error, {:missing_optional_dependency, dependency}}
    end
  end

  defp dependency_available?(module, opts) do
    checker = Keyword.get(opts, :dependency_checker, &Code.ensure_loaded?/1)
    checker.(module)
  end

  defp maybe_start_compiler(opts) do
    opts
    |> Keyword.get(:defn_options, [])
    |> Keyword.get(:compiler)
    |> case do
      nil -> :ok
      EXLA -> ensure_application_started(:exla)
      _compiler -> :ok
    end
  end

  defp ensure_application_started(app) do
    case Application.ensure_all_started(app) do
      {:ok, _started} -> :ok
      {:error, reason} -> {:error, {:compiler_start_failed, app, reason}}
    end
  end

  defp load_model(%ModelSpec{} = spec, opts) do
    bumblebee = Keyword.get(opts, :bumblebee_module, Bumblebee)

    retry_online_load(
      :model,
      opts,
      fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(bumblebee, :load_model, [
          repository(spec.model, opts, :model_repository_opts),
          Keyword.get(opts, :model_load_opts, [])
        ])
      end
    )
    |> normalize_load_result(:model)
  end

  defp load_tokenizer(%ModelSpec{} = spec, opts) do
    bumblebee = Keyword.get(opts, :bumblebee_module, Bumblebee)

    retry_online_load(
      :tokenizer,
      opts,
      fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(bumblebee, :load_tokenizer, [
          repository(spec.tokenizer, opts, :tokenizer_repository_opts),
          Keyword.get(opts, :tokenizer_load_opts, [])
        ])
      end
    )
    |> normalize_load_result(:tokenizer)
  end

  defp retry_online_load(kind, opts, fun) do
    retries = if Keyword.get(opts, :offline, false), do: 0, else: retry_count(opts)
    do_retry_online_load(kind, opts, fun, retries)
  end

  defp do_retry_online_load(kind, opts, fun, retries) do
    result = safe_call(fun)

    if retries > 0 and retryable_load_error?(result) do
      Process.sleep(retry_delay(opts))

      StageTiming.measure(:ner_serving, :"#{kind}_load_retry", opts[:stage_observer], fn ->
        do_retry_online_load(kind, opts, fun, retries - 1)
      end)
    else
      result
    end
  end

  defp retryable_load_error?({:error, reason})
       when reason in [:dependency_error, :download_interrupted],
       do: true

  defp retryable_load_error?(_result), do: false

  defp retry_count(opts) do
    case Keyword.get(opts, :asset_load_retries, 1) do
      retries when is_integer(retries) and retries >= 0 -> retries
      _retries -> 1
    end
  end

  defp retry_delay(opts) do
    case Keyword.get(opts, :asset_load_retry_delay, 250) do
      delay when is_integer(delay) and delay >= 0 -> delay
      _delay -> 250
    end
  end

  defp build_token_classification(model_info, tokenizer, %ModelSpec{} = spec, opts) do
    text_module = Keyword.get(opts, :bumblebee_text_module, Module.concat([Bumblebee, "Text"]))

    serving_opts =
      [
        aggregation: Keyword.get(opts, :aggregation, spec.aggregation),
        compile: Keyword.get(opts, :compile, batch_size: 1, sequence_length: 128),
        defn_options: Keyword.get(opts, :defn_options, [])
      ]
      |> maybe_put(:preallocate_params, Keyword.get(opts, :preallocate_params))

    safe_call(fn ->
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(text_module, :token_classification, [model_info, tokenizer, serving_opts])
    end)
    |> case do
      {:ok, serving} -> {:ok, serving}
      {:error, reason} -> {:error, {:serving_build_failed, reason}}
    end
  end

  defp safe_call(fun) do
    case fun.() do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, sanitize_dependency_reason(reason)}
      value -> {:ok, value}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    :exit, _reason -> {:error, :exit}
  end

  defp sanitize_dependency_reason(reason) when is_atom(reason), do: reason

  defp sanitize_dependency_reason(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, [
        "outgoing traffic is disabled",
        "could not find file in local cache"
      ]) ->
        :cache_miss

      String.contains?(reason, ["download failed", "failed to make an HTTP request"]) ->
        :download_interrupted

      true ->
        :dependency_error
    end
  end

  defp sanitize_dependency_reason(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    case elem(reason, 0) do
      code when is_atom(code) -> code
      _value -> :dependency_error
    end
  end

  defp sanitize_dependency_reason(_reason), do: :dependency_error

  defp normalize_load_result({:ok, value}, _kind), do: {:ok, value}

  defp normalize_load_result({:error, :cache_miss}, :model),
    do: {:error, {:missing_model_asset, :model_cache}}

  defp normalize_load_result({:error, :cache_miss}, :tokenizer),
    do: {:error, {:missing_tokenizer_asset, :tokenizer_cache}}

  defp normalize_load_result({:error, :download_interrupted}, kind),
    do: {:error, {:model_download_interrupted, kind}}

  defp normalize_load_result({:error, reason}, kind),
    do: {:error, {:"#{kind}_load_failed", reason}}

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp repository({:hf, id}, opts, repository_opts_key) do
    case repository_opts(opts, repository_opts_key) do
      [] -> {:hf, id}
      source_opts -> {:hf, id, source_opts}
    end
  end

  defp repository({:hf, id, source_opts}, opts, repository_opts_key) do
    {:hf, id, Keyword.merge(source_opts, repository_opts(opts, repository_opts_key))}
  end

  defp repository(source, _opts, _repository_opts_key), do: source

  defp repository_opts(opts, key) do
    explicit = Keyword.get(opts, key, [])

    if Keyword.get(opts, :offline, false),
      do: Keyword.put(explicit, :offline, true),
      else: explicit
  end

  defp measured(stage, observer, fun) do
    StageTiming.measure(:ner_serving, stage, observer, fun)
  end

  defp emit_build(start, result, opts) do
    metadata =
      case result do
        {:ok, %__MODULE__{} = serving} ->
          serving
          |> metadata()
          |> Map.merge(%{status: :ok, cold_start: true})

        {:error, {:missing_optional_dependency, dep}} ->
          %{status: :error, dependency_availability: dep}

        {:error, _reason} ->
          %{status: :error}
      end

    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :recognizer, :ner, :serving, :build, :stop],
      %{duration: System.monotonic_time() - start},
      metadata
    )
  end
end
