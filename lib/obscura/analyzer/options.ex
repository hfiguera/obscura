defmodule Obscura.Analyzer.Options do
  @moduledoc """
  Internal normalized analyzer options.
  """

  alias Obscura.Eval.EntityMapping
  alias Obscura.Profile

  @enforce_keys [
    :entities,
    :requested_profile,
    :profile,
    :language,
    :score_threshold,
    :explain,
    :include_text,
    :conflict_strategy,
    :built_ins,
    :recognizers,
    :deny_lists,
    :allow_list,
    :context,
    :context_window,
    :context_prefix_count,
    :context_suffix_count,
    :context_boost,
    :context_min_score,
    :context_match,
    :context_policies,
    :detect_language,
    :language_detector,
    :ner,
    :serving,
    :batch_size,
    :recognizer_timeout,
    :parallel_recognizers,
    :phone_parser,
    :phone_validator,
    :phone_regions,
    :telemetry,
    :nlp_artifacts,
    :nlp_engine,
    :nlp_engine_opts
  ]
  # The flat shape is the backward-compatible normalized analyzer contract.
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :entities,
    :requested_profile,
    :profile,
    :language,
    :score_threshold,
    :explain,
    :include_text,
    :conflict_strategy,
    :built_ins,
    :recognizers,
    :deny_lists,
    :allow_list,
    :context,
    :context_window,
    :context_prefix_count,
    :context_suffix_count,
    :context_boost,
    :context_min_score,
    :context_match,
    :context_policies,
    :detect_language,
    :language_detector,
    :ner,
    :serving,
    :batch_size,
    :recognizer_timeout,
    :parallel_recognizers,
    :phone_parser,
    :phone_validator,
    :phone_regions,
    :telemetry,
    :nlp_artifacts,
    :nlp_engine,
    :nlp_engine_opts
  ]

  @type t :: %__MODULE__{
          entities: [atom()],
          requested_profile: atom(),
          profile: atom(),
          language: atom(),
          score_threshold: number(),
          explain: boolean(),
          include_text: boolean(),
          conflict_strategy: atom(),
          built_ins: boolean(),
          recognizers: [module() | struct()],
          deny_lists: [map()],
          allow_list: list() | nil,
          context: [String.t()],
          context_window: non_neg_integer(),
          context_prefix_count: non_neg_integer(),
          context_suffix_count: non_neg_integer(),
          context_boost: float(),
          context_min_score: float(),
          context_match: atom(),
          context_policies: map() | keyword(),
          detect_language: boolean(),
          language_detector: module() | nil,
          ner: keyword(),
          serving: term(),
          batch_size: pos_integer(),
          recognizer_timeout: timeout(),
          parallel_recognizers: boolean(),
          phone_parser: module() | nil,
          phone_validator: function() | nil,
          phone_regions: [String.t()],
          telemetry: boolean(),
          nlp_artifacts: Obscura.NLP.Artifacts.t() | nil,
          nlp_engine: module() | {module(), keyword()} | nil,
          nlp_engine_opts: keyword()
        }

  @doc """
  Normalizes analyzer keyword options.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    requested_profile = Keyword.get(opts, :profile, :regex_only)

    with {:ok, normalized_profile} <- Profile.normalize(requested_profile) do
      build(opts, normalized_profile.requested, normalized_profile.implementation)
    end
  end

  def new(_opts), do: {:error, :invalid_analyzer_options}

  defp build(opts, requested_profile, profile) do
    options = %__MODULE__{
      entities: Keyword.get(opts, :entities, default_entities(profile)),
      requested_profile: requested_profile,
      profile: profile,
      language: Keyword.get(opts, :language, :en),
      score_threshold: Keyword.get(opts, :score_threshold, 0.0),
      explain: Keyword.get(opts, :explain, false),
      include_text: Keyword.get(opts, :include_text, true),
      conflict_strategy: Keyword.get(opts, :conflict_strategy, :default),
      built_ins: Keyword.get(opts, :built_ins, true),
      recognizers: List.wrap(Keyword.get(opts, :recognizers, [])),
      deny_lists: List.wrap(Keyword.get(opts, :deny_lists, [])),
      allow_list: Keyword.get(opts, :allow_list),
      context: context(opts),
      context_window: Keyword.get(opts, :context_window, 30),
      context_prefix_count: Keyword.get(opts, :context_prefix_count, 5),
      context_suffix_count: Keyword.get(opts, :context_suffix_count, 5),
      context_boost: Keyword.get(opts, :context_boost, 0.15),
      context_min_score: Keyword.get(opts, :context_min_score, 0.4),
      context_match: Keyword.get(opts, :context_match, :whole_word),
      context_policies: Keyword.get(opts, :context_policies, %{}),
      detect_language: Keyword.get(opts, :detect_language, false),
      language_detector: Keyword.get(opts, :language_detector),
      ner: Keyword.get(opts, :ner, []),
      serving: Keyword.get(opts, :serving),
      batch_size: Keyword.get(opts, :batch_size, 8),
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 5_000),
      parallel_recognizers: Keyword.get(opts, :parallel_recognizers, false),
      phone_parser: Keyword.get(opts, :phone_parser),
      phone_validator: Keyword.get(opts, :phone_validator),
      phone_regions: Keyword.get(opts, :phone_regions, []),
      telemetry: Keyword.get(opts, :telemetry, true),
      nlp_artifacts: Keyword.get(opts, :nlp_artifacts),
      nlp_engine: Keyword.get(opts, :nlp_engine),
      nlp_engine_opts: Keyword.get(opts, :nlp_engine_opts, [])
    }

    with :ok <- validate_entities(options.entities),
         {:ok, language} <- Obscura.Language.normalize(options.language),
         :ok <- validate_score_threshold(options.score_threshold),
         :ok <- validate_context(options.context),
         :ok <- validate_window(options.context_window),
         :ok <- validate_window(options.context_prefix_count),
         :ok <- validate_window(options.context_suffix_count),
         :ok <- validate_boost(options.context_boost),
         :ok <- validate_boost(options.context_min_score),
         :ok <- validate_context_match(options.context_match),
         :ok <- validate_context_policies(options.context_policies),
         :ok <- validate_boolean(options.built_ins, :built_ins),
         :ok <- validate_boolean(options.detect_language, :detect_language),
         :ok <- validate_batch_size(options.batch_size),
         :ok <- validate_timeout(options.recognizer_timeout),
         :ok <- validate_boolean(options.parallel_recognizers, :parallel_recognizers),
         :ok <- validate_phone_parser(options.phone_parser),
         :ok <- validate_phone_validator(options.phone_validator),
         :ok <- validate_phone_regions(options.phone_regions),
         :ok <- validate_nlp_engine(options.nlp_engine),
         :ok <- validate_keyword(options.nlp_engine_opts, :nlp_engine_opts) do
      {:ok, %{options | language: language}}
    end
  end

  @doc """
  Converts normalized options back to a keyword list for recognizer calls.
  """
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = options) do
    [
      entities: options.entities,
      requested_profile: options.requested_profile,
      profile: options.profile,
      language: options.language,
      score_threshold: options.score_threshold,
      explain: options.explain,
      include_text: options.include_text,
      conflict_strategy: options.conflict_strategy,
      built_ins: options.built_ins,
      recognizers: options.recognizers,
      deny_lists: options.deny_lists,
      allow_list: options.allow_list,
      context: options.context,
      context_window: options.context_window,
      context_prefix_count: options.context_prefix_count,
      context_suffix_count: options.context_suffix_count,
      context_boost: options.context_boost,
      context_min_score: options.context_min_score,
      context_match: options.context_match,
      context_policies: options.context_policies,
      detect_language: options.detect_language,
      language_detector: options.language_detector,
      ner: options.ner,
      serving: options.serving,
      batch_size: options.batch_size,
      recognizer_timeout: options.recognizer_timeout,
      parallel_recognizers: options.parallel_recognizers,
      phone_parser: options.phone_parser,
      phone_validator: options.phone_validator,
      phone_regions: options.phone_regions,
      telemetry: options.telemetry,
      nlp_artifacts: options.nlp_artifacts,
      nlp_engine: options.nlp_engine,
      nlp_engine_opts: options.nlp_engine_opts
    ]
  end

  defp default_entities(:nlp), do: EntityMapping.nlp_supported_entities()
  defp default_entities(:hybrid_ner), do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_balanced), do: EntityMapping.hybrid_ner_supported_entities()
  defp default_entities(:hybrid_ner_org), do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_org_high_recall),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_dbmdz_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_tner_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_tner_high_recall),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_tner_facebookai_org),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_tner_jean_location),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_tner_jean_location_gated),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_tner_jean_location_cascade),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_bigmed_conservative),
    do: EntityMapping.hybrid_ner_supported_entities()

  defp default_entities(:hybrid_ner_ortex_openmed_superclinical_small),
    do: EntityMapping.hybrid_ner_ortex_openmed_superclinical_supported_entities()

  defp default_entities(:ner_ortex_piiranha_v1),
    do: EntityMapping.ner_ortex_piiranha_supported_entities()

  defp default_entities(:hybrid_ner_ortex_piiranha_v1),
    do: EntityMapping.hybrid_ner_ortex_piiranha_supported_entities()

  defp default_entities(:hybrid_gliner_ortex),
    do: EntityMapping.hybrid_gliner_supported_entities()

  defp default_entities(:hybrid_gliner_urchade),
    do: EntityMapping.hybrid_gliner_supported_entities()

  defp default_entities(:hybrid_gliner_urchade_native),
    do: EntityMapping.hybrid_gliner_supported_entities()

  defp default_entities(:deterministic_plus),
    do: EntityMapping.deterministic_plus_supported_entities()

  defp default_entities(:phi), do: EntityMapping.phi_supported_entities()
  defp default_entities(_profile), do: EntityMapping.phase_0_supported_entities()

  defp context(opts) do
    opts
    |> Keyword.get(:context, [])
    |> List.wrap()
  end

  defp validate_entities(entities) when is_list(entities) do
    Enum.reduce_while(entities, :ok, fn
      entity, :ok when is_atom(entity) -> {:cont, :ok}
      _entity, :ok -> {:halt, {:error, :invalid_entities}}
    end)
  end

  defp validate_entities(_entities), do: {:error, :invalid_entities}

  defp validate_score_threshold(threshold) when is_number(threshold) and threshold >= 0.0,
    do: :ok

  defp validate_score_threshold(_threshold), do: {:error, :invalid_score_threshold}

  defp validate_context(context) when is_list(context) do
    if Enum.all?(context, &is_binary/1), do: :ok, else: {:error, :invalid_context}
  end

  defp validate_window(window) when is_integer(window) and window >= 0, do: :ok
  defp validate_window(_window), do: {:error, :invalid_context_window}

  defp validate_boost(boost) when is_number(boost) and boost >= 0.0, do: :ok
  defp validate_boost(_boost), do: {:error, :invalid_context_boost}

  defp validate_context_match(match) when match in [:whole_word, :substring], do: :ok
  defp validate_context_match(_match), do: {:error, :invalid_context_match}

  defp validate_context_policies(policies) when is_map(policies) or is_list(policies), do: :ok
  defp validate_context_policies(_policies), do: {:error, :invalid_context_policies}

  defp validate_boolean(value, _key) when is_boolean(value), do: :ok
  defp validate_boolean(_value, key), do: {:error, {:invalid_boolean, key}}

  defp validate_batch_size(batch_size) when is_integer(batch_size) and batch_size > 0,
    do: :ok

  defp validate_batch_size(_batch_size), do: {:error, :invalid_batch_size}

  defp validate_timeout(:infinity), do: :ok

  defp validate_timeout(timeout) when is_integer(timeout) and timeout >= 0, do: :ok

  defp validate_timeout(_timeout), do: {:error, :invalid_recognizer_timeout}

  defp validate_phone_parser(nil), do: :ok
  defp validate_phone_parser(parser) when is_atom(parser), do: :ok
  defp validate_phone_parser(parser) when is_function(parser), do: :ok
  defp validate_phone_parser(_parser), do: {:error, :invalid_phone_parser}

  defp validate_phone_validator(nil), do: :ok
  defp validate_phone_validator(validator) when is_atom(validator), do: :ok
  defp validate_phone_validator(validator) when is_function(validator), do: :ok
  defp validate_phone_validator(_validator), do: {:error, :invalid_phone_validator}

  defp validate_phone_regions(regions) when is_list(regions) do
    if Enum.all?(regions, &(is_binary(&1) or is_atom(&1))),
      do: :ok,
      else: {:error, :invalid_phone_regions}
  end

  defp validate_phone_regions(_regions), do: {:error, :invalid_phone_regions}

  defp validate_nlp_engine(nil), do: :ok
  defp validate_nlp_engine(module) when is_atom(module), do: :ok
  defp validate_nlp_engine({module, opts}) when is_atom(module) and is_list(opts), do: :ok
  defp validate_nlp_engine(_engine), do: {:error, :invalid_nlp_engine}

  defp validate_keyword(value, _key) when is_list(value), do: :ok
  defp validate_keyword(_value, key), do: {:error, {:invalid_keyword, key}}
end
