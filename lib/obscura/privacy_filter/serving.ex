defmodule Obscura.PrivacyFilter.Serving do
  @moduledoc """
  Reusable native privacy-filter serving runtime.

  `build/1` loads checkpoint-local config, weights, label info, and model
  parameters once. `run/3` tokenizes input text, executes the native model, and
  converts privacy-filter BIOES logits into normal Obscura analyzer results.
  """

  alias Obscura.Internal.StageDiagnostics
  alias Obscura.PrivacyFilter.Checkpoint.Layout
  alias Obscura.PrivacyFilter.Config
  alias Obscura.PrivacyFilter.DTypes
  alias Obscura.PrivacyFilter.LabelInfo
  alias Obscura.PrivacyFilter.Logprobs
  alias Obscura.PrivacyFilter.Model
  alias Obscura.PrivacyFilter.Model.Parameters
  alias Obscura.PrivacyFilter.SequenceLabeling
  alias Obscura.PrivacyFilter.SequenceLabeling.TokenizedExample
  alias Obscura.PrivacyFilter.Spans
  alias Obscura.PrivacyFilter.Tokenization
  alias Obscura.PrivacyFilter.Viterbi
  alias Obscura.PrivacyFilter.Viterbi.Calibration
  alias Obscura.PrivacyFilter.Weights
  alias Obscura.Serving.StageTiming

  @supported_backends [:default, :binary, :exla, :emily]
  @supported_emily_fallback_modes [:silent, :warn, :raise]
  @supported_emily_devices [:gpu, :cpu]
  @supported_logprob_conversions [:reference, :raw_logits]

  @enforce_keys [:config, :label_info]
  defstruct [
    :checkpoint,
    :config,
    :label_info,
    :weights,
    :params,
    :model_fun,
    :layout,
    :dtypes,
    backend: :default,
    backend_metadata: %{},
    decoder: :viterbi,
    viterbi_biases: %{},
    viterbi_calibration: :none,
    n_ctx: nil,
    pad_windows: false,
    sequence_length_buckets: nil,
    sequence_length_bucket_threshold: nil,
    logprob_conversion: :reference,
    trim_span_whitespace: true,
    discard_overlapping_spans: true,
    label_map: :default,
    min_span_logprob: nil
  ]

  @type t :: %__MODULE__{}

  @spec build(keyword()) :: {:ok, t()} | {:error, term()}
  def build(opts) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :config) ->
        build_from_config(opts)

      Keyword.has_key?(opts, :checkpoint) ->
        build_from_checkpoint(opts)

      true ->
        {:error, :missing_privacy_filter_checkpoint_or_config}
    end
  end

  @spec run(t(), String.t(), keyword()) :: {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def run(%__MODULE__{} = serving, text, opts \\ []) when is_binary(text) do
    case run_with_timings(serving, text, opts) do
      {:ok, results, _timings} -> {:ok, results}
      {:error, reason, _timings} -> {:error, reason}
    end
  end

  @spec run_with_timings(t(), String.t(), keyword()) ::
          {:ok, [Obscura.Analyzer.Result.t()], map()} | {:error, term(), map()}
  def run_with_timings(%__MODULE__{} = serving, text, opts \\ []) when is_binary(text) do
    total_start = System.monotonic_time()

    case timed(fn -> tokenize_with_diagnostics(serving, text) end) do
      {{:ok, tokenization}, tokenization_ms} ->
        timings = %{tokenization_ms: tokenization_ms}
        run_tokenized_with_timings(serving, tokenization, opts, timings, total_start)

      {{:error, reason}, tokenization_ms} ->
        {:error, reason, finalize_timings(%{tokenization_ms: tokenization_ms}, total_start)}
    end
  end

  @spec postprocess(t(), map(), Nx.Tensor.t(), keyword()) ::
          {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def postprocess(%__MODULE__{} = serving, tokenization, logits, opts \\ []) do
    with {:ok, logprob_rows} <- logits_to_logprobs(logits) do
      postprocess_logprobs(serving, tokenization, logprob_rows, opts)
    end
  end

  @spec postprocess_logprobs(t(), map(), [list(float())], keyword()) ::
          {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def postprocess_logprobs(%__MODULE__{} = serving, tokenization, logprob_rows, opts \\ []) do
    with :ok <- validate_logprob_rows(serving, logprob_rows),
         {:ok, labels_by_index} <-
           StageDiagnostics.measure(:viterbi_logprob_decode, fn ->
             decode_label_rows(serving, logprob_rows)
           end) do
      StageDiagnostics.measure(:span_reconstruction_entity_mapping, fn ->
        reconstruct_results(serving, tokenization, logprob_rows, labels_by_index, opts)
      end)
    end
  end

  defp reconstruct_results(serving, tokenization, logprob_rows, labels_by_index, opts) do
    with token_spans <- Spans.labels_to_spans(labels_by_index, serving.label_info),
         token_spans <-
           filter_token_spans_by_logprob(
             token_spans,
             labels_by_index,
             logprob_rows,
             Keyword.get(opts, :min_span_logprob, serving.min_span_logprob)
           ),
         char_spans <-
           Spans.token_spans_to_char_spans(
             token_spans,
             Map.fetch!(tokenization, :char_starts),
             Map.fetch!(tokenization, :char_ends)
           ),
         char_spans <- maybe_trim(serving, char_spans, Map.fetch!(tokenization, :text)),
         char_spans <- maybe_discard_overlaps(serving, char_spans),
         {:ok, spans} <-
           Spans.char_spans_to_detected_spans(
             char_spans,
             Map.fetch!(tokenization, :text),
             serving.label_info,
             label_map: Keyword.get(opts, :label_map, serving.label_map),
             metadata: runtime_metadata(serving),
             score: Keyword.get(opts, :score, 1.0)
           ) do
      {:ok, Spans.to_results(spans)}
    end
  end

  defp build_from_checkpoint(opts) do
    checkpoint = Keyword.fetch!(opts, :checkpoint)
    observer = Keyword.get(opts, :stage_observer)

    with {:ok, backend_config} <-
           measured(:backend_configuration, observer, fn -> configure_backend(opts) end),
         {:ok, layout} <-
           measured(:checkpoint_layout, observer, fn -> normalize_layout(opts) end),
         :ok <-
           measured(:checkpoint_validation, observer, fn ->
             validate_checkpoint(checkpoint, layout)
           end),
         {:ok, config} <-
           measured(:config_load, observer, fn ->
             Config.from_file(Path.join(checkpoint, "config.json"))
           end),
         {:ok, label_info} <-
           measured(:label_info_load, observer, fn ->
             LabelInfo.build(config.ner_class_names)
           end),
         {:ok, weights} <-
           measured(:weights_load, observer, fn -> Weights.load(checkpoint) end),
         {:ok, dtypes} <-
           measured(:dtypes_load, observer, fn ->
             load_layout_dtypes(checkpoint, layout, weights)
           end),
         {:ok, params} <-
           measured(:parameter_load, observer, fn -> Parameters.load(weights, config) end) do
      measured(:serving_construction, observer, fn ->
        build_runtime(opts,
          checkpoint: checkpoint,
          config: config,
          label_info: label_info,
          weights: weights,
          params: params,
          layout: layout,
          dtypes: dtypes,
          backend: backend_config.backend,
          backend_metadata: backend_config.metadata
        )
      end)
    end
  end

  defp validate_checkpoint_path(checkpoint) do
    cond do
      not File.dir?(checkpoint) ->
        {:error, {:checkpoint_dir_not_found, checkpoint}}

      not File.exists?(Path.join(checkpoint, "config.json")) ->
        {:error, {:missing_checkpoint_config, Path.join(checkpoint, "config.json")}}

      true ->
        :ok
    end
  end

  defp validate_checkpoint(checkpoint, layout) do
    with :ok <- Layout.validate(checkpoint, layout) do
      validate_checkpoint_path(checkpoint)
    end
  end

  defp build_from_config(opts) do
    config = Keyword.fetch!(opts, :config)
    observer = Keyword.get(opts, :stage_observer)

    with {:ok, backend_config} <-
           measured(:backend_configuration, observer, fn -> configure_backend(opts) end),
         {:ok, layout} <-
           measured(:checkpoint_layout, observer, fn -> normalize_layout(opts) end),
         {:ok, label_info} <-
           measured(:label_info_load, observer, fn -> label_info_from_opts(config, opts) end) do
      measured(:serving_construction, observer, fn ->
        build_runtime(opts,
          checkpoint: Keyword.get(opts, :checkpoint),
          config: config,
          label_info: label_info,
          params: Keyword.get(opts, :params),
          model_fun: Keyword.get(opts, :model_fun),
          layout: layout,
          dtypes: Keyword.get(opts, :dtypes),
          backend: backend_config.backend,
          backend_metadata: backend_config.metadata
        )
      end)
    end
  end

  defp build_runtime(opts, attrs) do
    with {:ok, {viterbi_biases, viterbi_calibration}} <-
           viterbi_biases(opts, Keyword.get(attrs, :checkpoint)),
         :ok <-
           validate_label_info_matches_config(
             Keyword.fetch!(attrs, :label_info),
             Keyword.fetch!(attrs, :config)
           ),
         {:ok, n_ctx} <- resolve_n_ctx(Keyword.fetch!(attrs, :config), opts),
         {:ok, sequence_length_buckets} <-
           resolve_sequence_length_buckets(Keyword.get(opts, :sequence_length_buckets), n_ctx),
         {:ok, sequence_length_bucket_threshold} <-
           resolve_sequence_length_bucket_threshold(
             Keyword.get(opts, :sequence_length_bucket_threshold),
             sequence_length_buckets
           ),
         {:ok, logprob_conversion} <-
           normalize_logprob_conversion(Keyword.get(opts, :logprob_conversion, :reference)),
         :ok <-
           validate_logprob_conversion(
             logprob_conversion,
             Keyword.get(opts, :decoder, :viterbi),
             Keyword.get(opts, :min_span_logprob)
           ) do
      {:ok,
       %__MODULE__{
         checkpoint: Keyword.get(attrs, :checkpoint),
         config: Keyword.fetch!(attrs, :config),
         label_info: Keyword.fetch!(attrs, :label_info),
         weights: Keyword.get(attrs, :weights),
         params: Keyword.get(attrs, :params),
         model_fun: Keyword.get(attrs, :model_fun),
         layout: Keyword.get(attrs, :layout, :native),
         dtypes: Keyword.get(attrs, :dtypes),
         backend: Keyword.get(attrs, :backend, :default),
         backend_metadata: Keyword.get(attrs, :backend_metadata, %{}),
         decoder: Keyword.get(opts, :decoder, :viterbi),
         viterbi_biases: viterbi_biases,
         viterbi_calibration: viterbi_calibration,
         n_ctx: n_ctx,
         pad_windows: Keyword.get(opts, :pad_windows, false),
         sequence_length_buckets: sequence_length_buckets,
         sequence_length_bucket_threshold: sequence_length_bucket_threshold,
         logprob_conversion: logprob_conversion,
         trim_span_whitespace: Keyword.get(opts, :trim_span_whitespace, true),
         discard_overlapping_spans: Keyword.get(opts, :discard_overlapping_spans, true),
         label_map: Keyword.get(opts, :label_map, :default),
         min_span_logprob: Keyword.get(opts, :min_span_logprob)
       }}
    end
  end

  defp normalize_layout(opts) do
    opts
    |> Keyword.get(:layout, :native)
    |> Layout.normalize()
  end

  defp load_layout_dtypes(checkpoint, :python_original, weights) do
    path = Path.join(checkpoint, "dtypes.json")

    with {:ok, dtypes} <- DTypes.load(path),
         {:ok, summary} <- DTypes.validate_against_weights(dtypes, weights) do
      {:ok, %{entries: dtypes, summary: summary}}
    end
  end

  defp load_layout_dtypes(_checkpoint, :native, _weights), do: {:ok, nil}

  defp configure_backend(opts) do
    selected_backend(opts)
    |> normalize_backend()
    |> case do
      {:ok, :default} ->
        {:ok, backend_config(:default, opts)}

      {:ok, :binary} ->
        with :ok <- set_nx_backend(Nx.BinaryBackend, opts) do
          {:ok, backend_config(:binary, opts)}
        end

      {:ok, :exla} ->
        exla = Module.concat(["EXLA"])
        exla_backend = Module.concat(["EXLA", "Backend"])

        with :ok <- ensure_dependency(exla, :exla, opts),
             :ok <- ensure_dependency(exla_backend, :exla, opts),
             {:ok, _started} <- start_application(:exla, opts),
             :ok <- set_nx_backend(exla_backend, opts) do
          {:ok, backend_config(:exla, opts)}
        else
          {:error, {:missing_optional_dependency, _dep} = reason} -> {:error, reason}
          {:error, reason} -> {:error, {:backend_configuration_failed, :exla, reason}}
        end

      {:ok, :emily} ->
        configure_emily_backend(opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp selected_backend(opts) do
    Keyword.get(opts, :backend) ||
      Keyword.get(opts, :real_model_backend) ||
      System.get_env("OBSCURA_PRIVACY_FILTER_BACKEND") ||
      :default
  end

  defp normalize_backend(""), do: {:ok, :default}
  defp normalize_backend(:default), do: {:ok, :default}
  defp normalize_backend(:binary), do: {:ok, :binary}
  defp normalize_backend(:exla), do: {:ok, :exla}
  defp normalize_backend(:emily), do: {:ok, :emily}

  defp normalize_backend(value) when is_binary(value) do
    case value |> String.downcase() |> String.replace("-", "_") do
      "default" -> {:ok, :default}
      "binary" -> {:ok, :binary}
      "exla" -> {:ok, :exla}
      "emily" -> {:ok, :emily}
      _other -> {:error, {:unsupported_privacy_filter_backend, @supported_backends}}
    end
  end

  defp normalize_backend(_other),
    do: {:error, {:unsupported_privacy_filter_backend, @supported_backends}}

  defp configure_emily_backend(opts) do
    emily = Module.concat(["Emily"])
    backend = Module.concat(["Emily", "Backend"])
    compiler = Module.concat(["Emily", "Compiler"])
    nx_defn = Module.concat(["Nx", "Defn"])

    with :ok <- ensure_dependency(emily, :emily, opts),
         :ok <- ensure_dependency(backend, :emily, opts),
         :ok <- ensure_dependency(compiler, :emily, opts),
         :ok <- ensure_dependency(nx_defn, :nx, opts),
         {:ok, fallback} <- emily_fallback(opts),
         {:ok, device} <- emily_device(opts),
         :ok <- put_emily_fallback(fallback, opts),
         {:ok, _started} <- start_application(:emily, opts),
         :ok <- set_nx_backend({backend, device: device}, opts),
         :ok <- set_nx_defn_options([compiler: compiler], opts) do
      {:ok,
       backend_config(:emily, opts,
         actual_device: device,
         emily_device: device,
         emily_fallback: fallback,
         exla_enabled: false,
         parity_warning: :python_original_bf16_qkv_backend_limited,
         parity_warning_reason:
           "Emily GPU BF16 QKV dot/matmul does not currently match Python OPF exactly; use BinaryBackend for Python-original numeric parity validation."
       )}
    else
      {:error, {:missing_optional_dependency, _dep} = reason} -> {:error, reason}
      {:error, {:unsupported_emily_fallback, _supported} = reason} -> {:error, reason}
      {:error, {:unsupported_emily_device, _supported} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:backend_configuration_failed, :emily, reason}}
    end
  end

  defp backend_config(backend, opts, metadata_overrides \\ []) do
    %{
      backend: backend,
      metadata:
        %{
          requested_backend: backend,
          actual_backend: backend,
          actual_device: configured_device(backend, opts),
          backend_source: backend_source(opts),
          backend_proven: backend != :default,
          exla_enabled: backend == :exla,
          fallback_occurred: false
        }
        |> Map.merge(Map.new(metadata_overrides))
    }
  end

  defp configured_device(:binary, _opts), do: :cpu
  defp configured_device(:emily, opts), do: Keyword.get(opts, :emily_device, :gpu)
  defp configured_device(:exla, opts), do: Keyword.get(opts, :exla_device, :unknown)
  defp configured_device(:default, _opts), do: :unknown

  defp ensure_dependency(module, dependency, opts) do
    checker = Keyword.get(opts, :dependency_checker, &Code.ensure_loaded?/1)

    if checker.(module) do
      :ok
    else
      {:error, {:missing_optional_dependency, dependency}}
    end
  end

  defp start_application(app, opts) do
    opts
    |> Keyword.get(:application_starter, &Application.ensure_all_started/1)
    |> then(& &1.(app))
  end

  defp put_emily_fallback(fallback, opts) do
    putter = Keyword.get(opts, :application_env_putter, &Application.put_env/3)
    putter.(:emily, :fallback, fallback)
    :ok
  end

  defp set_nx_backend(backend, opts) do
    case Keyword.get(opts, :nx_backend_setter) do
      nil -> Nx.global_default_backend(backend)
      setter -> setter.(backend)
    end

    :ok
  rescue
    error -> {:error, {:backend_configuration_failed, error.__struct__}}
  end

  defp set_nx_defn_options(defn_options, opts) do
    case Keyword.get(opts, :nx_defn_options_setter) do
      nil -> Nx.Defn.global_default_options(defn_options)
      setter -> setter.(defn_options)
    end

    :ok
  rescue
    error -> {:error, {:defn_configuration_failed, error.__struct__}}
  end

  defp emily_fallback(opts) do
    opts
    |> Keyword.get(:emily_fallback, System.get_env("OBSCURA_EMILY_FALLBACK", "raise"))
    |> normalize_emily_fallback()
  end

  defp normalize_emily_fallback(value)
       when is_atom(value) and value in @supported_emily_fallback_modes,
       do: {:ok, value}

  defp normalize_emily_fallback(value) when is_binary(value) do
    case String.downcase(value) do
      "silent" -> {:ok, :silent}
      "warn" -> {:ok, :warn}
      "raise" -> {:ok, :raise}
      _other -> {:error, {:unsupported_emily_fallback, @supported_emily_fallback_modes}}
    end
  end

  defp normalize_emily_fallback(_value),
    do: {:error, {:unsupported_emily_fallback, @supported_emily_fallback_modes}}

  defp emily_device(opts) do
    opts
    |> Keyword.get(:emily_device, System.get_env("OBSCURA_EMILY_DEVICE", "gpu"))
    |> normalize_emily_device()
  end

  defp normalize_emily_device(value) when is_atom(value) and value in @supported_emily_devices,
    do: {:ok, value}

  defp normalize_emily_device(value) when is_binary(value) do
    case String.downcase(value) do
      "gpu" -> {:ok, :gpu}
      "cpu" -> {:ok, :cpu}
      _other -> {:error, {:unsupported_emily_device, @supported_emily_devices}}
    end
  end

  defp normalize_emily_device(_value),
    do: {:error, {:unsupported_emily_device, @supported_emily_devices}}

  defp backend_source(opts) do
    cond do
      Keyword.has_key?(opts, :backend) -> :option
      Keyword.has_key?(opts, :real_model_backend) -> :real_model_backend_option
      System.get_env("OBSCURA_PRIVACY_FILTER_BACKEND") not in [nil, ""] -> :env
      true -> :default
    end
  end

  defp resolve_n_ctx(config, opts) do
    case Keyword.fetch(opts, :n_ctx) do
      {:ok, value} -> validate_n_ctx(value)
      :error -> {:ok, default_n_ctx(config, opts)}
    end
  end

  defp validate_n_ctx(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp validate_n_ctx(value), do: {:error, {:invalid_privacy_filter_n_ctx, value}}

  defp resolve_sequence_length_buckets(nil, _n_ctx), do: {:ok, nil}

  defp resolve_sequence_length_buckets(buckets, n_ctx)
       when is_list(buckets) and buckets != [] do
    valid? =
      Enum.all?(buckets, &(is_integer(&1) and &1 > 0)) and
        buckets == Enum.sort(Enum.uniq(buckets))

    cond do
      not valid? ->
        {:error, {:invalid_privacy_filter_sequence_length_buckets, buckets}}

      List.last(buckets) > n_ctx ->
        {:error,
         {:privacy_filter_sequence_length_bucket_exceeds_n_ctx, List.last(buckets), n_ctx}}

      true ->
        {:ok, buckets}
    end
  end

  defp resolve_sequence_length_buckets(buckets, _n_ctx),
    do: {:error, {:invalid_privacy_filter_sequence_length_buckets, buckets}}

  defp resolve_sequence_length_bucket_threshold(nil, _buckets), do: {:ok, nil}

  defp resolve_sequence_length_bucket_threshold(threshold, buckets)
       when is_integer(threshold) and threshold > 0 and is_list(buckets) do
    if threshold <= List.last(buckets) do
      {:ok, threshold}
    else
      {:error,
       {:privacy_filter_sequence_length_bucket_threshold_exceeds_maximum, threshold,
        List.last(buckets)}}
    end
  end

  defp resolve_sequence_length_bucket_threshold(threshold, buckets) do
    {:error, {:invalid_privacy_filter_sequence_length_bucket_threshold, threshold, buckets}}
  end

  defp normalize_logprob_conversion(mode) when mode in @supported_logprob_conversions,
    do: {:ok, mode}

  defp normalize_logprob_conversion(mode),
    do: {:error, {:unsupported_privacy_filter_logprob_conversion, mode}}

  defp validate_logprob_conversion(:raw_logits, :viterbi, nil), do: :ok

  defp validate_logprob_conversion(:raw_logits, decoder, min_span_logprob) do
    {:error,
     {:privacy_filter_viterbi_logit_mode_requires_viterbi_without_span_threshold, :raw_logits,
      decoder, min_span_logprob}}
  end

  defp validate_logprob_conversion(_mode, _decoder, _min_span_logprob), do: :ok

  defp default_n_ctx(config, opts) do
    if cpu_device?(Keyword.get(opts, :device, :cpu)) do
      4096
    else
      config_default_n_ctx(config) || 4096
    end
  end

  defp cpu_device?(device) when device in [:cpu, "cpu"], do: true
  defp cpu_device?(_device), do: false

  defp config_default_n_ctx(nil), do: nil

  defp config_default_n_ctx(config) do
    first_positive([
      config_value(config, :default_n_ctx),
      config_value(config, :initial_context_length),
      config_value(config, :max_position_embeddings)
    ])
  end

  defp first_positive(values) do
    Enum.find(values, &(is_integer(&1) and &1 > 0))
  end

  defp label_info_from_opts(config, opts) do
    case Keyword.fetch(opts, :label_info) do
      {:ok, %LabelInfo{} = label_info} -> {:ok, label_info}
      :error -> LabelInfo.build(Map.fetch!(config, :ner_class_names))
    end
  end

  defp validate_label_info_matches_config(%LabelInfo{} = label_info, config) do
    expected_labels = expected_label_count(config)
    actual_labels = map_size(label_info.token_to_span_label)

    if expected_labels == actual_labels do
      :ok
    else
      {:error, {:privacy_filter_label_info_mismatch, expected_labels, actual_labels}}
    end
  end

  defp expected_label_count(config) do
    config_value(config, :num_labels) || length(config_value(config, :ner_class_names) || [])
  end

  defp run_tokenized_with_timings(serving, tokenization, opts, timings, total_start) do
    {model_result, model_ms} = timed(fn -> run_logprob_rows(serving, tokenization) end)

    timings = Map.put(timings, :model_ms, model_ms)

    finish_tokenized_run(model_result, serving, tokenization, opts, timings, total_start)
  end

  defp finish_tokenized_run(
         {:ok, logprob_rows},
         serving,
         tokenization,
         opts,
         timings,
         total_start
       ) do
    {decode_result, decode_ms} =
      timed(fn -> postprocess_logprobs(serving, tokenization, logprob_rows, opts) end)

    finish_decode(decode_result, Map.put(timings, :decode_ms, decode_ms), total_start)
  end

  defp finish_tokenized_run(
         {:error, reason},
         _serving,
         _tokenization,
         _opts,
         timings,
         total_start
       ) do
    {:error, reason, finalize_timings(timings, total_start)}
  end

  defp finish_decode({:ok, results}, timings, total_start),
    do: {:ok, results, finalize_timings(timings, total_start)}

  defp finish_decode({:error, reason}, timings, total_start),
    do: {:error, reason, finalize_timings(timings, total_start)}

  defp run_logprob_rows(%__MODULE__{} = serving, tokenization) do
    token_ids = Map.fetch!(tokenization, :token_ids)
    background = serving.label_info.background_token_label
    StageDiagnostics.metadata(:token_count, length(token_ids))
    StageDiagnostics.unavailable(:privacy_filter_attention, :fused_compiled_device_graph)
    StageDiagnostics.unavailable(:privacy_filter_moe, :fused_compiled_device_graph)

    example = %TokenizedExample{
      tokens: List.to_tuple(token_ids),
      labels: List.duplicate(background, length(token_ids)) |> List.to_tuple(),
      example_id: "privacy-filter-input",
      text: Map.fetch!(tokenization, :text)
    }

    with {:ok, windows} <-
           StageDiagnostics.measure(:token_packing, fn ->
             build_windows(serving, example, tokenization, token_ids, background)
           end),
         {:ok, aggregation} <- run_windows(serving, windows) do
      record_window_metadata(windows, length(token_ids))

      {:ok,
       StageDiagnostics.measure(:window_logprob_aggregation, fn ->
         average_logprobs(aggregation)
       end)}
    end
  end

  defp build_windows(
         %__MODULE__{
           sequence_length_buckets: buckets,
           sequence_length_bucket_threshold: threshold
         },
         example,
         tokenization,
         token_ids,
         background
       )
       when is_list(buckets) and (is_nil(threshold) or length(token_ids) >= threshold) do
    SequenceLabeling.example_to_bucketed_windows(example, buckets,
      pad_token_id: Map.fetch!(tokenization, :pad_token_id),
      pad_label: background
    )
  end

  defp build_windows(serving, example, tokenization, token_ids, background) do
    SequenceLabeling.example_to_windows(
      example,
      window_size(serving, token_ids),
      window_opts(serving, tokenization, background)
    )
  end

  defp record_window_metadata(windows, token_count) do
    packed_tokens = Enum.reduce(windows, 0, &(&2 + tuple_size(&1.tokens)))
    padding_tokens = max(packed_tokens - token_count, 0)
    selected_bucket = windows |> Enum.map(&tuple_size(&1.tokens)) |> Enum.max(fn -> 0 end)

    StageDiagnostics.metadata(:window_count, length(windows))
    StageDiagnostics.metadata(:model_sequence_length, selected_bucket)
    StageDiagnostics.metadata(:model_packed_tokens, packed_tokens)
    StageDiagnostics.metadata(:model_padding_tokens, padding_tokens)

    ratio = if packed_tokens == 0, do: 0.0, else: padding_tokens / packed_tokens
    StageDiagnostics.metadata(:model_padding_ratio, ratio)
  end

  defp window_size(%__MODULE__{n_ctx: n_ctx}, _token_ids) when is_integer(n_ctx) and n_ctx > 0,
    do: n_ctx

  defp window_size(%__MODULE__{}, []), do: 1
  defp window_size(%__MODULE__{}, token_ids), do: length(token_ids)

  defp window_opts(%__MODULE__{n_ctx: n_ctx, pad_windows: true}, tokenization, background)
       when is_integer(n_ctx) and n_ctx > 0 do
    [
      pad_token_id: Map.fetch!(tokenization, :pad_token_id),
      pad_label: background
    ]
  end

  defp window_opts(%__MODULE__{}, _tokenization, _background), do: []

  defp run_windows(serving, windows) do
    Enum.reduce_while(windows, {:ok, %{}}, fn window, {:ok, aggregation} ->
      window_tokens = Tuple.to_list(window.tokens)
      window_mask = Tuple.to_list(window.mask)

      run_window(serving, window, window_tokens, window_mask, aggregation)
    end)
  end

  defp run_window(_serving, _window, [], _window_mask, aggregation),
    do: {:cont, {:ok, aggregation}}

  defp run_window(serving, window, window_tokens, window_mask, aggregation) do
    case run_window_logprobs(serving, window_tokens, window_mask) do
      {:ok, rows} -> {:cont, aggregate_window(aggregation, window, rows)}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp run_window_logprobs(%__MODULE__{} = serving, token_ids, attention_mask) do
    StageDiagnostics.metadata(:model_sequence_length, length(token_ids))

    with {:ok, logits} <-
           StageDiagnostics.measure(:model_serving, fn ->
             run_window_logits(serving, token_ids, attention_mask)
           end),
         {:ok, rows} <-
           StageDiagnostics.measure(:logprob_conversion, fn ->
             logits_to_logprobs(logits, serving.logprob_conversion)
           end),
         :ok <- validate_logprob_rows(serving, rows) do
      if length(rows) == length(token_ids) do
        {:ok, rows}
      else
        {:error, {:privacy_filter_logit_length_mismatch, length(token_ids), length(rows)}}
      end
    end
  end

  defp run_window_logits(%__MODULE__{model_fun: model_fun}, token_ids, attention_mask)
       when is_function(model_fun, 2) do
    token_ids = Nx.tensor([token_ids])
    attention_mask = Nx.tensor([attention_mask])

    model_fun.(token_ids, attention_mask)
    |> normalize_model_output()
  rescue
    error -> {:error, model_forward_error(error)}
  end

  defp run_window_logits(%__MODULE__{params: nil}, _token_ids, _attention_mask),
    do: {:error, :privacy_filter_model_params_not_loaded}

  defp run_window_logits(%__MODULE__{} = serving, token_ids, attention_mask) do
    token_ids = Nx.tensor([token_ids])
    attention_mask = Nx.tensor([attention_mask])

    token_ids
    |> Model.forward_result(serving.params, serving.config, attention_mask: attention_mask)
    |> normalize_model_output()
  rescue
    error -> {:error, model_forward_error(error)}
  end

  defp normalize_model_output(logits) when is_struct(logits, Nx.Tensor), do: {:ok, logits}

  defp normalize_model_output({:ok, logits}) when is_struct(logits, Nx.Tensor),
    do: {:ok, logits}

  defp normalize_model_output({:error, reason}), do: {:error, reason}

  defp normalize_model_output(_other),
    do: {:error, :privacy_filter_model_output_invalid}

  defp model_forward_error(error) do
    {:privacy_filter_model_forward_failed, error.__struct__}
  end

  defp decode_label_rows(%__MODULE__{} = serving, rows) do
    labels =
      case serving.decoder do
        :argmax ->
          Enum.map(rows, &argmax/1)

        :viterbi ->
          Viterbi.decode(Viterbi.new(serving.label_info, serving.viterbi_biases), rows)

        other ->
          return_error({:unsupported_privacy_filter_decoder, other})
      end

    case labels do
      {:error, reason} ->
        {:error, reason}

      labels ->
        {:ok, labels |> Enum.with_index() |> Map.new(fn {label, index} -> {index, label} end)}
    end
  end

  defp aggregate_window(aggregation, window, rows) do
    offsets = Tuple.to_list(window.offsets)
    masks = Tuple.to_list(window.mask)

    rows
    |> Enum.zip(offsets)
    |> Enum.zip(masks)
    |> Enum.reduce({:ok, aggregation}, fn
      {{row, offset}, mask}, {:ok, acc} when mask in [1, true] ->
        {:ok,
         Map.update(acc, offset, {row, 1}, fn {existing, count} ->
           {logaddexp_rows(existing, row), count + 1}
         end)}

      _item, acc ->
        acc
    end)
    |> elem(1)
    |> then(&{:ok, &1})
  end

  defp average_logprobs(aggregation) when map_size(aggregation) == 0, do: []

  defp average_logprobs(aggregation) do
    max_index = aggregation |> Map.keys() |> Enum.max()

    0..max_index
    |> Enum.flat_map(fn index ->
      case Map.fetch(aggregation, index) do
        {:ok, {row, count}} -> [Enum.map(row, &(&1 - :math.log(count)))]
        :error -> []
      end
    end)
  end

  defp logaddexp_rows(left, right) do
    Enum.zip_with(left, right, fn left_value, right_value ->
      max_value = max(left_value, right_value)

      max_value +
        :math.log(:math.exp(left_value - max_value) + :math.exp(right_value - max_value))
    end)
  end

  defp logits_to_logprobs(logits), do: logits_to_logprobs(logits, :reference)
  defp logits_to_logprobs(logits, mode), do: Logprobs.to_rows(logits, mode)

  defp validate_logprob_rows(%__MODULE__{} = serving, rows) when is_list(rows) do
    expected_labels = map_size(serving.label_info.token_to_span_label)

    rows
    |> Enum.with_index()
    |> Enum.find(fn {row, _index} -> not is_list(row) or length(row) != expected_labels end)
    |> case do
      nil ->
        :ok

      {row, index} ->
        {:error,
         {:privacy_filter_logit_label_count_mismatch, index, expected_labels, row_length(row)}}
    end
  end

  defp row_length(row) when is_list(row), do: length(row)
  defp row_length(_row), do: :invalid_row

  defp maybe_trim(%__MODULE__{trim_span_whitespace: true}, spans, text),
    do: Spans.trim_char_spans_whitespace(spans, text)

  defp maybe_trim(%__MODULE__{}, spans, _text), do: spans

  defp maybe_discard_overlaps(%__MODULE__{discard_overlapping_spans: true}, spans),
    do: Spans.discard_overlapping_spans_by_label(spans)

  defp maybe_discard_overlaps(%__MODULE__{}, spans), do: spans

  defp filter_token_spans_by_logprob(spans, _labels_by_index, _rows, nil), do: spans

  defp filter_token_spans_by_logprob(spans, labels_by_index, rows, threshold)
       when is_number(threshold) do
    Enum.filter(spans, fn {_label_idx, start, ending} ->
      mean_decoded_logprob(labels_by_index, rows, start, ending) >= threshold
    end)
  end

  defp mean_decoded_logprob(labels_by_index, rows, start, ending) do
    start..(ending - 1)
    |> Enum.map(fn index ->
      label_id = Map.fetch!(labels_by_index, index)
      rows |> Enum.at(index) |> Enum.at(label_id)
    end)
    |> then(fn values -> Enum.sum(values) / length(values) end)
  end

  defp argmax(row) do
    row
    |> Enum.with_index()
    |> Enum.max_by(fn {value, _index} -> value end)
    |> elem(1)
  end

  defp return_error(reason), do: {:error, reason}

  defp viterbi_biases(opts, checkpoint) do
    cond do
      Keyword.has_key?(opts, :viterbi_biases) ->
        {:ok, {Keyword.fetch!(opts, :viterbi_biases), :explicit_biases}}

      path = Keyword.get(opts, :viterbi_calibration_path) ->
        with {:ok, biases} <- Calibration.load(path) do
          {:ok, {biases, :explicit_path}}
        end

      is_binary(checkpoint) ->
        checkpoint
        |> Path.join("viterbi_calibration.json")
        |> load_optional_calibration()

      true ->
        {:ok, {%{}, :none}}
    end
  end

  defp load_optional_calibration(path) do
    if File.exists?(path) do
      with {:ok, biases} <- Calibration.load(path) do
        {:ok, {biases, :checkpoint_file}}
      end
    else
      {:ok, {%{}, :none}}
    end
  end

  defp runtime_metadata(%__MODULE__{} = serving) do
    %{
      recognizer: :privacy_filter_native,
      model_type: config_value(serving.config, :model_type),
      checkpoint: serving.checkpoint,
      encoding: config_value(serving.config, :encoding),
      category_version: config_value(serving.config, :category_version),
      layout: serving.layout,
      backend: serving.backend,
      backend_metadata: serving.backend_metadata,
      decoder: serving.decoder,
      viterbi_calibration: serving.viterbi_calibration,
      n_ctx: serving.n_ctx,
      pad_windows: serving.pad_windows,
      trim_span_whitespace: serving.trim_span_whitespace,
      discard_overlapping_spans: serving.discard_overlapping_spans,
      label_map: serving.label_map,
      min_span_logprob: serving.min_span_logprob
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil

  defp timed(fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    result = fun.()
    {result, elapsed_ms(start)}
  end

  defp tokenize_with_diagnostics(serving, text) do
    StageDiagnostics.measure(:tokenization, fn ->
      Tokenization.from_config(serving.config, text)
    end)
  end

  defp finalize_timings(timings, total_start) do
    timings
    |> Map.put(:total_ms, elapsed_ms(total_start))
    |> Map.put_new(:tokenization_ms, 0.0)
    |> Map.put_new(:model_ms, 0.0)
    |> Map.put_new(:decode_ms, 0.0)
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end

  defp measured(stage, observer, fun) do
    StageTiming.measure(:privacy_filter_serving, stage, observer, fun)
  end
end
