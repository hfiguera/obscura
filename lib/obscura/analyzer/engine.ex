defmodule Obscura.Analyzer.Engine do
  @moduledoc """
  Coordinates recognizers, filtering, scoring, and conflict resolution.
  """

  alias Obscura.AllowList
  alias Obscura.Analyzer.Options
  alias Obscura.Analyzer.Result
  alias Obscura.Conflict
  alias Obscura.Context
  alias Obscura.Eval.Offset
  alias Obscura.Input
  alias Obscura.Internal.ResultText
  alias Obscura.Internal.StageDiagnostics
  alias Obscura.NLP.Engine, as: NLPEngine
  alias Obscura.Profile
  alias Obscura.Recognizer.DenyList
  alias Obscura.Recognizer.PatternDefinition
  alias Obscura.Recognizer.Registry
  alias Obscura.Telemetry

  @doc """
  Runs built-in recognizers for a string.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    with :ok <- Input.validate_text(text),
         {:ok, opts} <- Profile.configure_options(opts),
         {:ok, options} <- Options.new(opts),
         {:ok, options} <- maybe_detect_language(text, options),
         {:ok, recognizers} <-
           Registry.fetch(options.entities,
             recognizers: options.recognizers,
             deny_lists: options.deny_lists,
             built_ins: options.built_ins
           ),
         {:ok, artifacts} <- artifacts_for_text(text, options),
         options = %{options | nlp_artifacts: artifacts},
         {:ok, raw_results} <-
           StageDiagnostics.measure(:recognizer_execution, fn ->
             run_recognizers(recognizers, text, options)
           end) do
      start = System.monotonic_time()

      Telemetry.execute(
        options.telemetry,
        [:obscura, :analyze, :start],
        %{},
        telemetry_metadata(options, :start, 0)
      )

      raw_results
      |> post_process(text, options)
      |> tap(fn results ->
        StageDiagnostics.metadata(:result_count, length(results))

        Telemetry.execute(
          options.telemetry,
          [:obscura, :analyze, :stop],
          %{duration: elapsed_native(start)},
          telemetry_metadata(options, :ok, length(results))
        )
      end)
      |> then(&{:ok, &1})
    end
  end

  @doc """
  Runs recognizers across many strings while preserving input order.
  """
  @spec analyze_many([String.t()], keyword()) ::
          {:ok, [[Obscura.Analyzer.Result.t()]]} | {:error, term()}
  def analyze_many(texts, opts) when is_list(texts) and is_list(opts) do
    start = System.monotonic_time()

    with :ok <- validate_texts(texts),
         {:ok, opts} <- Profile.configure_options(opts),
         {:ok, options} <- Options.new(opts),
         {:ok, recognizers} <-
           Registry.fetch(options.entities,
             recognizers: options.recognizers,
             deny_lists: options.deny_lists,
             built_ins: options.built_ins
           ),
         {:ok, artifacts_by_text} <- artifacts_for_many(texts, options),
         {:ok, results_by_text} <-
           run_many_recognizers(recognizers, texts, options, artifacts_by_text) do
      results =
        texts
        |> Enum.zip(results_by_text)
        |> Enum.zip(artifacts_by_text)
        |> Enum.map(fn {{text, results}, artifacts} ->
          post_process(results, text, %{options | nlp_artifacts: artifacts})
        end)

      Telemetry.execute(
        options.telemetry,
        [:obscura, :analyzer, :analyze_many, :stop],
        %{duration: elapsed_native(start)},
        %{
          status: :ok,
          input_count: length(texts),
          result_count: results |> List.flatten() |> length(),
          entities: options.entities,
          profile: options.profile,
          requested_profile: options.requested_profile
        }
      )

      {:ok, results}
    end
  end

  defp validate_texts(texts) do
    Input.validate_texts(texts)
  end

  defp run_recognizers(recognizers, text, %{parallel_recognizers: true} = options) do
    recognizers
    |> Task.async_stream(&run_recognizer(&1, text, options),
      max_concurrency: max(length(recognizers), 1),
      on_timeout: :kill_task,
      ordered: true,
      timeout: options.recognizer_timeout
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, results}}, {:ok, acc} ->
        {:cont, {:ok, acc ++ results}}

      {:ok, {:error, reason}}, {:ok, _acc} ->
        {:halt, {:error, reason}}

      {:exit, _reason}, {:ok, _acc} ->
        {:halt, {:error, {:recognizer_failed, :parallel, :exit}}}
    end)
  end

  defp run_recognizers(recognizers, text, options) do
    Enum.reduce_while(recognizers, {:ok, []}, fn recognizer, {:ok, acc} ->
      case run_recognizer(recognizer, text, options) do
        {:ok, results} -> {:cont, {:ok, acc ++ results}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_recognizer(%PatternDefinition{} = definition, text, options) do
    {:ok, PatternDefinition.analyze(definition, text, Options.to_keyword(options))}
  end

  defp run_recognizer({:deny_list, deny_lists}, text, options) do
    {:ok, DenyList.analyze(text, deny_lists, Options.to_keyword(options))}
  end

  defp run_recognizer({module, recognizer_opts}, text, options) when is_atom(module) do
    run_module_recognizer(
      module,
      text,
      Options.to_keyword(options) |> Keyword.merge(recognizer_opts)
    )
  end

  defp run_recognizer(module, text, options) when is_atom(module) do
    run_module_recognizer(module, text, Options.to_keyword(options))
  end

  defp run_module_recognizer(module, text, opts) do
    case module.analyze(text, opts) do
      {:ok, results} ->
        validate_callback_results(results, text, module)

      {:error, reason} ->
        {:error, {:recognizer_failed, recognizer_name(module), safe_callback_reason(reason)}}

      results when is_list(results) ->
        validate_callback_results(results, text, module)

      _invalid ->
        callback_result_error(module)
    end
  rescue
    _error -> {:error, {:recognizer_failed, recognizer_name(module), :exception}}
  catch
    :throw, _reason -> {:error, {:recognizer_failed, recognizer_name(module), :throw}}
    :exit, _reason -> {:error, {:recognizer_failed, recognizer_name(module), :exit}}
  end

  defp run_many_recognizers(
         recognizers,
         texts,
         %{parallel_recognizers: true} = options,
         artifacts_by_text
       ) do
    initial = List.duplicate([], length(texts))

    recognizers
    |> Task.async_stream(&run_many_recognizer(&1, texts, options, artifacts_by_text),
      max_concurrency: max(length(recognizers), 1),
      on_timeout: :kill_task,
      ordered: true,
      timeout: options.recognizer_timeout
    )
    |> Enum.reduce_while({:ok, initial}, fn
      {:ok, {:ok, results_by_text}}, {:ok, acc} ->
        {:cont, {:ok, merge_by_text(acc, results_by_text)}}

      {:ok, {:error, reason}}, {:ok, _acc} ->
        {:halt, {:error, reason}}

      {:exit, _reason}, {:ok, _acc} ->
        {:halt, {:error, {:recognizer_failed, :parallel, :exit}}}
    end)
  end

  defp run_many_recognizers(recognizers, texts, options, artifacts_by_text) do
    initial = List.duplicate([], length(texts))

    Enum.reduce_while(recognizers, {:ok, initial}, fn recognizer, {:ok, acc} ->
      case run_many_recognizer(recognizer, texts, options, artifacts_by_text) do
        {:ok, results_by_text} -> {:cont, {:ok, merge_by_text(acc, results_by_text)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_many_recognizer({module, recognizer_opts}, texts, options, artifacts_by_text)
       when is_atom(module) do
    opts = Options.to_keyword(options) |> Keyword.merge(recognizer_opts)

    cond do
      central_artifacts?(options) ->
        run_many_fallback({module, recognizer_opts}, texts, options, artifacts_by_text)

      function_exported?(module, :analyze_many, 2) ->
        normalize_many_result(module.analyze_many(texts, opts), module, texts)

      true ->
        run_many_fallback({module, recognizer_opts}, texts, options, artifacts_by_text)
    end
  rescue
    _error -> {:error, {:recognizer_failed, recognizer_name(module), :exception}}
  catch
    :throw, _reason -> {:error, {:recognizer_failed, recognizer_name(module), :throw}}
    :exit, _reason -> {:error, {:recognizer_failed, recognizer_name(module), :exit}}
  end

  defp run_many_recognizer(module, texts, options, artifacts_by_text) when is_atom(module) do
    opts = Options.to_keyword(options)

    cond do
      central_artifacts?(options) ->
        run_many_fallback(module, texts, options, artifacts_by_text)

      function_exported?(module, :analyze_many, 2) ->
        normalize_many_result(module.analyze_many(texts, opts), module, texts)

      true ->
        run_many_fallback(module, texts, options, artifacts_by_text)
    end
  rescue
    _error -> {:error, {:recognizer_failed, recognizer_name(module), :exception}}
  catch
    :throw, _reason -> {:error, {:recognizer_failed, recognizer_name(module), :throw}}
    :exit, _reason -> {:error, {:recognizer_failed, recognizer_name(module), :exit}}
  end

  defp run_many_recognizer(recognizer, texts, options, artifacts_by_text) do
    run_many_fallback(recognizer, texts, options, artifacts_by_text)
  end

  defp central_artifacts?(options) do
    not is_nil(options.nlp_engine) or is_list(options.nlp_artifacts)
  end

  defp run_many_fallback(recognizer, texts, options, artifacts_by_text) do
    texts
    |> Enum.zip(artifacts_by_text)
    |> Enum.reduce_while({:ok, []}, fn {text, artifacts}, {:ok, acc} ->
      case run_recognizer(recognizer, text, %{options | nlp_artifacts: artifacts}) do
        {:ok, results} -> {:cont, {:ok, [results | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_many_result({:ok, results}, module, texts),
    do: validate_many_callback_results(results, texts, module)

  defp normalize_many_result({:error, reason}, module, _texts),
    do: {:error, {:recognizer_failed, recognizer_name(module), safe_callback_reason(reason)}}

  defp normalize_many_result(results, module, texts) when is_list(results),
    do: validate_many_callback_results(results, texts, module)

  defp normalize_many_result(_invalid, module, _texts), do: callback_result_error(module)

  defp merge_by_text(left, right) do
    Enum.zip_with(left, right, &Kernel.++/2)
  end

  defp post_process(results, text, options) do
    filtered = filter_and_enhance(results, text, options)

    resolved =
      StageDiagnostics.measure(:conflict_resolution, fn ->
        Conflict.resolve(filtered, options.conflict_strategy)
      end)

    StageDiagnostics.measure(:final_assembly, fn ->
      resolved
      |> Enum.sort_by(&{&1.start, &1.end, &1.entity})
      |> ResultText.finalize(text, options.include_text)
    end)
  end

  defp filter_and_enhance(results, text, options) do
    if StageDiagnostics.enabled?() do
      filter_and_enhance_with_diagnostics(results, text, options)
    else
      results
      |> filter_requested_entities(options.entities)
      |> AllowList.filter(options.allow_list, text)
      |> Context.enhance(text, options)
      |> filter_accepted(options)
    end
  end

  defp filter_and_enhance_with_diagnostics(results, text, options) do
    candidates =
      StageDiagnostics.measure(:analyzer_filtering, fn ->
        results
        |> filter_requested_entities(options.entities)
        |> AllowList.filter(options.allow_list, text)
      end)

    enhanced =
      StageDiagnostics.measure(:context_enhancement, fn ->
        Context.enhance(candidates, text, options)
      end)

    StageDiagnostics.measure(:acceptance_filtering, fn ->
      filter_accepted(enhanced, options)
    end)
  end

  defp filter_accepted(results, options) do
    Enum.filter(results, &(Context.accepted?(&1) and &1.score >= options.score_threshold))
  end

  defp filter_requested_entities(results, entities) do
    Enum.filter(results, &(&1.entity in entities))
  end

  defp artifacts_for_text(text, options) do
    if dependency_light_artifacts_can_be_deferred?(options) do
      {:ok, nil}
    else
      StageDiagnostics.measure(:nlp_artifacts, fn ->
        NLPEngine.build_artifacts(text, Options.to_keyword(options))
      end)
    end
  end

  defp artifacts_for_many(texts, options) do
    if dependency_light_artifacts_can_be_deferred?(options) do
      {:ok, List.duplicate(nil, length(texts))}
    else
      NLPEngine.build_many(texts, Options.to_keyword(options))
    end
  end

  defp dependency_light_artifacts_can_be_deferred?(options) do
    options.profile == :deterministic_plus and options.recognizers == [] and
      is_nil(options.nlp_artifacts) and is_nil(options.nlp_engine)
  end

  defp telemetry_metadata(options, status, result_count) do
    %{
      profile: options.profile,
      requested_profile: options.requested_profile,
      entities: options.entities,
      result_count: result_count,
      status: status,
      input_type: :string
    }
  end

  defp elapsed_native(start), do: System.monotonic_time() - start

  defp maybe_detect_language(_text, %{detect_language: false} = options), do: {:ok, options}

  defp maybe_detect_language(text, %{language_detector: detector} = options)
       when is_atom(detector) and not is_nil(detector) do
    case detector.detect(text, Options.to_keyword(options)) do
      {:ok, language} ->
        with {:ok, language} <- Obscura.Language.normalize(language) do
          {:ok, %{options | language: language}}
        end

      {:error, reason} ->
        {:error, {:language_detection_failed, safe_callback_reason(reason)}}
    end
  end

  defp maybe_detect_language(_text, _options), do: {:error, :missing_language_detector}

  defp recognizer_name(module) when is_atom(module) do
    if function_exported?(module, :name, 0) do
      case module.name() do
        name when is_atom(name) and not is_nil(name) -> name
        _invalid -> module
      end
    else
      module
    end
  rescue
    _error -> module
  catch
    _kind, _reason -> module
  end

  defp validate_callback_results(results, text, module) when is_list(results) do
    if not List.improper?(results) and Enum.all?(results, &valid_result?(&1, text)) do
      {:ok, results}
    else
      callback_result_error(module)
    end
  end

  defp validate_callback_results(_results, _text, module), do: callback_result_error(module)

  defp validate_many_callback_results(results, texts, module)
       when is_list(results) and is_list(texts) do
    valid? =
      not List.improper?(results) and length(results) == length(texts) and
        Enum.zip(results, texts)
        |> Enum.all?(fn {row, text} ->
          match?({:ok, _results}, validate_callback_results(row, text, module))
        end)

    if valid?, do: {:ok, results}, else: callback_result_error(module)
  end

  defp validate_many_callback_results(_results, _texts, module),
    do: callback_result_error(module)

  defp valid_result?(%Result{} = result, text) do
    is_atom(result.entity) and not is_nil(result.entity) and
      is_number(result.score) and
      result.start == result.byte_start and result.end == result.byte_end and
      (is_nil(result.text) or is_binary(result.text)) and
      is_map(result.metadata) and
      Offset.validate_span(text, %{
        byte_start: result.byte_start,
        byte_end: result.byte_end,
        value: result.text
      }) == :ok
  end

  defp valid_result?(_result, _text), do: false

  defp callback_result_error(module) do
    {:error, {:recognizer_failed, recognizer_name(module), :invalid_callback_result}}
  end

  defp safe_callback_reason(reason) when is_atom(reason), do: reason

  defp safe_callback_reason({code, detail}) when is_atom(code) and is_atom(detail),
    do: {code, detail}

  defp safe_callback_reason(_reason), do: :callback_error
end
