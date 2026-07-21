defmodule Obscura do
  @moduledoc """
  Obscura is a library-first privacy toolkit for Elixir.

  Public APIs return explicit success or error tuples.
  """

  alias Obscura.Analyzer
  alias Obscura.Anonymizer
  alias Obscura.Rehydrator
  alias Obscura.Structured

  @doc """
  Analyzes a string for supported PII entities.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, [Obscura.Analyzer.Result.t()]} | {:error, term()}
  def analyze(text, opts \\ [])

  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    Analyzer.analyze(text, opts)
  end

  def analyze(_text, _opts), do: {:error, :invalid_analyze_arguments}

  @doc """
  Analyzes multiple strings while preserving input order.
  """
  @spec analyze_many([String.t()], keyword()) ::
          {:ok, [[Obscura.Analyzer.Result.t()]]} | {:error, term()}
  def analyze_many(texts, opts \\ [])

  def analyze_many(texts, opts) when is_list(texts) and is_list(opts) do
    Analyzer.analyze_many(texts, opts)
  end

  def analyze_many(_texts, _opts), do: {:error, :invalid_analyze_many_arguments}

  @doc """
  Applies anonymization operators to analyzer results or fixture-compatible spans.
  """
  @spec anonymize(String.t(), [map() | struct()], keyword()) ::
          {:ok, Obscura.Anonymizer.Result.t()} | {:error, term()}
  def anonymize(text, analyzer_results, opts \\ [])

  def anonymize(text, analyzer_results, opts)
      when is_binary(text) and is_list(analyzer_results) and is_list(opts) do
    Anonymizer.anonymize(text, analyzer_results, opts)
  end

  def anonymize(_text, _analyzer_results, _opts), do: {:error, :invalid_anonymize_arguments}

  @doc """
  Analyzes and anonymizes a string in one call.
  """
  @spec redact(String.t(), keyword()) :: {:ok, Obscura.Anonymizer.Result.t()} | {:error, term()}
  def redact(input, opts \\ [])

  def redact(input, opts) when is_binary(input) and is_list(opts) do
    analyze_opts =
      Keyword.take(opts, [
        :entities,
        :profile,
        :profile_runtime,
        :language,
        :score_threshold,
        :explain,
        :include_text,
        :conflict_strategy,
        :recognizers,
        :built_ins,
        :deny_lists,
        :allow_list,
        :context,
        :context_window,
        :context_prefix_count,
        :context_suffix_count,
        :context_boost,
        :context_min_score,
        :context_match,
        :detect_language,
        :language_detector,
        :ner,
        :serving,
        :servings,
        :primary_serving,
        :location_serving,
        :privacy_filter_serving,
        :batch_size,
        :recognizer_timeout,
        :parallel_recognizers,
        :phone_parser,
        :phone_validator,
        :phone_regions,
        :nlp_artifacts,
        :nlp_engine,
        :nlp_engine_opts,
        :telemetry
      ])

    anonymize_opts =
      Keyword.drop(opts, [
        :entities,
        :profile,
        :profile_runtime,
        :language,
        :score_threshold,
        :explain,
        :include_text,
        :recognizers,
        :built_ins,
        :deny_lists,
        :allow_list,
        :context,
        :context_window,
        :context_prefix_count,
        :context_suffix_count,
        :context_boost,
        :context_min_score,
        :context_match,
        :detect_language,
        :language_detector,
        :ner,
        :serving,
        :servings,
        :primary_serving,
        :location_serving,
        :privacy_filter_serving,
        :batch_size,
        :recognizer_timeout,
        :parallel_recognizers,
        :phone_parser,
        :phone_validator,
        :phone_regions,
        :nlp_artifacts,
        :nlp_engine,
        :nlp_engine_opts,
        :telemetry
      ])

    with {:ok, results} <- analyze(input, analyze_opts) do
      anonymize(input, results, anonymize_opts)
    end
  end

  def redact(input, opts) when is_list(opts) do
    Structured.redact(input, opts)
  end

  def redact(_input, _opts), do: {:error, :invalid_redact_arguments}

  @doc """
  Rehydrates vault-backed pseudonym tokens in strings or supported structured data.
  """
  @spec rehydrate(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def rehydrate(input, opts \\ [])

  def rehydrate(input, opts) when is_binary(input) and is_list(opts) do
    Rehydrator.rehydrate(input, opts)
  end

  def rehydrate(input, opts) when is_list(opts) do
    Obscura.Rehydrator.Structured.rehydrate(input, opts)
  end

  def rehydrate(_input, _opts), do: {:error, :invalid_rehydrate_arguments}
end
