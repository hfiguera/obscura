defmodule Mix.Tasks.Obscura.Eval do
  @moduledoc """
  Runs Obscura smoke evaluation.
  """

  use Mix.Task

  alias Obscura.CLI
  alias Obscura.Eval.EntityMapping
  alias Obscura.Eval.PresidioCompatibility
  alias Obscura.Eval.PresidioResearchLoader
  alias Obscura.Eval.Profile
  alias Obscura.Eval.Smoke
  alias Obscura.Recognizer.GLiNER.LabelMap
  alias Obscura.Recognizer.GLiNER.ModelRegistry, as: GLiNERModelRegistry
  alias Obscura.Recognizer.NER.Backend
  alias Obscura.Recognizer.NER.ModelRegistry

  @shortdoc "Runs Obscura evaluation smoke"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    case write_report(opts) do
      :ok ->
        Mix.shell().info(report_message(opts))

      {:error, reason} ->
        Mix.raise("Evaluation smoke failed: #{CLI.format_error(reason)}")
    end
  end

  defp write_report(opts) do
    if Keyword.get(opts, :compatibility, false) do
      PresidioCompatibility.write_reports(opts)
    else
      opts |> ensure_legacy_dataset!() |> Smoke.write_report()
    end
  end

  defp ensure_legacy_dataset!(opts) do
    case Keyword.get(opts, :dataset, :synth_dataset_v2) do
      nil ->
        opts

      :synth_dataset_v2 ->
        opts

      _other ->
        Mix.raise("Unsupported dataset for smoke mode. Use --compatibility.")
    end
  end

  defp report_message(opts) do
    if Keyword.get(opts, :compatibility, false),
      do: "Presidio compatibility benchmark report generated.",
      else: "Presidio-Research smoke report generated."
  end

  defp parse_args(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          dataset: :string,
          entities: :string,
          profile: :string,
          profiles: :string,
          smoke: :boolean,
          full: :boolean,
          compatibility: :boolean,
          limit: :integer,
          model: :string,
          real_model: :boolean,
          fake: :boolean,
          reason: :string,
          sample_ids: :string,
          run_suffix: :string,
          threshold_sweep: :boolean,
          label_threshold_sweep: :boolean,
          policy_sweep: :boolean,
          policy_selection_objective: :string,
          policy_fp_cap: :integer,
          policy_global_f1_floor: :float,
          cascade_trigger: :string,
          cascade_context_policy: :string,
          cascade_uncertainty_threshold: :float,
          cascade_secondary_threshold: :float,
          parallel_recognizers: :boolean,
          thresholds: :string,
          label_threshold_values: :string,
          ner_per_label_thresholds: :string,
          ner_context_required_labels: :string,
          ner_context_required_below_labels: :string,
          ner_context_words_by_label: :string,
          ner_weak_context_words_by_label: :string,
          ner_negative_context_words_by_label: :string,
          ner_negative_context_reject_labels: :string,
          ner_low_score_labels: :string,
          conflict_strategy: :string,
          ner_boundary_normalization: :string,
          ner_model_postprocessors: :string,
          ner_model_chunking: :string,
          ner_model_chunk_size: :integer,
          ner_model_chunk_overlap: :integer,
          phone_parser: :string,
          phone_regions: :string,
          gliner_model: :string,
          gliner_execution_providers: :string,
          gliner_label_profile: :string,
          gliner_threshold: :float,
          gliner_per_label_thresholds: :string,
          gliner_native: :boolean,
          privacy_filter_native: :boolean,
          privacy_filter_checkpoint: :string,
          privacy_filter_model_id: :string,
          privacy_filter_n_ctx: :integer,
          privacy_filter_pad_windows: :boolean,
          privacy_filter_decoder: :string,
          privacy_filter_min_span_logprob: :float,
          privacy_filter_sequence_length_buckets: :string,
          privacy_filter_sequence_length_bucket_threshold: :integer,
          privacy_filter_logprob_conversion: :string,
          privacy_filter_label_map_mode: :string,
          template_split: :string,
          template_train_ratio: :float,
          compile_batch_size: :integer,
          compile_sequence_length: :integer,
          backend: :string
        ]
      )

    if invalid != [] or remaining != [], do: Mix.raise("Invalid options.")

    [
      dataset: parsed |> Keyword.get(:dataset) |> to_existing_dataset(),
      entities: parsed |> Keyword.get(:entities) |> to_entities(),
      profile: parsed |> Keyword.get(:profile, "regex_only") |> to_existing_profile(),
      profiles: parsed |> Keyword.get(:profiles) |> to_existing_profiles(),
      limit: Keyword.get(parsed, :limit, 25),
      smoke: Keyword.get(parsed, :smoke, false),
      full: Keyword.get(parsed, :full, false),
      compatibility: Keyword.get(parsed, :compatibility, false),
      model: parsed |> Keyword.get(:model) |> to_existing_model(),
      real_model: Keyword.get(parsed, :real_model, false),
      fake: Keyword.get(parsed, :fake, false),
      reason: Keyword.get(parsed, :reason),
      sample_ids: parsed |> Keyword.get(:sample_ids) |> to_sample_ids(),
      run_suffix: Keyword.get(parsed, :run_suffix),
      threshold_sweep: Keyword.get(parsed, :threshold_sweep, false),
      label_threshold_sweep: Keyword.get(parsed, :label_threshold_sweep, false),
      policy_sweep: Keyword.get(parsed, :policy_sweep, false),
      policy_selection_objective:
        parsed |> Keyword.get(:policy_selection_objective) |> to_policy_selection_objective(),
      policy_fp_cap: Keyword.get(parsed, :policy_fp_cap),
      policy_global_f1_floor: Keyword.get(parsed, :policy_global_f1_floor),
      cascade_trigger: parsed |> Keyword.get(:cascade_trigger) |> to_cascade_trigger(),
      cascade_context_policy:
        parsed |> Keyword.get(:cascade_context_policy) |> to_cascade_context_policy(),
      cascade_uncertainty_threshold: Keyword.get(parsed, :cascade_uncertainty_threshold),
      cascade_secondary_threshold: Keyword.get(parsed, :cascade_secondary_threshold),
      parallel_recognizers: Keyword.get(parsed, :parallel_recognizers, false),
      thresholds: parsed |> Keyword.get(:thresholds) |> to_thresholds(),
      label_threshold_values:
        parsed |> Keyword.get(:label_threshold_values) |> to_label_threshold_values(),
      ner_per_label_thresholds:
        parsed |> Keyword.get(:ner_per_label_thresholds) |> to_label_thresholds(),
      ner_context_required_labels:
        parsed |> Keyword.get(:ner_context_required_labels) |> to_label_list(),
      ner_context_required_below_labels:
        parsed |> Keyword.get(:ner_context_required_below_labels) |> to_label_thresholds(),
      ner_context_words_by_label:
        parsed |> Keyword.get(:ner_context_words_by_label) |> to_label_word_lists(),
      ner_weak_context_words_by_label:
        parsed |> Keyword.get(:ner_weak_context_words_by_label) |> to_label_word_lists(),
      ner_negative_context_words_by_label:
        parsed |> Keyword.get(:ner_negative_context_words_by_label) |> to_label_word_lists(),
      ner_negative_context_reject_labels:
        parsed |> Keyword.get(:ner_negative_context_reject_labels) |> to_label_list(),
      ner_low_score_labels: parsed |> Keyword.get(:ner_low_score_labels) |> to_label_list(),
      conflict_strategy: parsed |> Keyword.get(:conflict_strategy) |> to_conflict_strategy(),
      ner_boundary_normalization:
        parsed |> Keyword.get(:ner_boundary_normalization) |> to_boundary_normalization(),
      ner_model_postprocessors:
        parsed |> Keyword.get(:ner_model_postprocessors) |> to_model_postprocessors(),
      ner_model_chunking: parsed |> Keyword.get(:ner_model_chunking) |> to_model_chunking(),
      ner_model_chunk_size: Keyword.get(parsed, :ner_model_chunk_size),
      ner_model_chunk_overlap: Keyword.get(parsed, :ner_model_chunk_overlap),
      phone_parser: parsed |> Keyword.get(:phone_parser) |> to_phone_parser(),
      phone_regions: parsed |> Keyword.get(:phone_regions) |> to_string_list(),
      gliner_model: parsed |> Keyword.get(:gliner_model) |> to_existing_gliner_model(),
      execution_providers:
        parsed |> Keyword.get(:gliner_execution_providers) |> to_gliner_execution_providers(),
      gliner_label_profile:
        parsed |> Keyword.get(:gliner_label_profile) |> to_gliner_label_profile(),
      gliner_threshold: Keyword.get(parsed, :gliner_threshold),
      gliner_per_label_thresholds:
        parsed |> Keyword.get(:gliner_per_label_thresholds) |> to_label_thresholds(),
      gliner_native: Keyword.get(parsed, :gliner_native, false),
      privacy_filter_native: Keyword.get(parsed, :privacy_filter_native, false),
      privacy_filter_checkpoint: Keyword.get(parsed, :privacy_filter_checkpoint),
      privacy_filter_model_id: Keyword.get(parsed, :privacy_filter_model_id),
      privacy_filter_n_ctx: Keyword.get(parsed, :privacy_filter_n_ctx),
      privacy_filter_pad_windows: Keyword.get(parsed, :privacy_filter_pad_windows, false),
      privacy_filter_decoder:
        parsed |> Keyword.get(:privacy_filter_decoder) |> to_privacy_filter_decoder(),
      privacy_filter_min_span_logprob: Keyword.get(parsed, :privacy_filter_min_span_logprob),
      privacy_filter_sequence_length_buckets:
        parsed
        |> Keyword.get(:privacy_filter_sequence_length_buckets)
        |> to_positive_integer_list(),
      privacy_filter_sequence_length_bucket_threshold:
        Keyword.get(parsed, :privacy_filter_sequence_length_bucket_threshold),
      privacy_filter_logprob_conversion:
        parsed
        |> Keyword.get(:privacy_filter_logprob_conversion)
        |> to_privacy_filter_logprob_conversion(),
      privacy_filter_label_map_mode:
        parsed
        |> Keyword.get(:privacy_filter_label_map_mode)
        |> to_privacy_filter_label_map_mode(),
      template_split: parsed |> Keyword.get(:template_split) |> to_template_split(),
      template_train_ratio: Keyword.get(parsed, :template_train_ratio),
      real_model_backend: parsed |> Keyword.get(:backend) |> to_backend(),
      compile: compile_opts(parsed)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp to_existing_profile(profile) do
    case Profile.from_string(profile) do
      {:ok, profile} -> profile
      {:error, {:unknown_profile, _other}} -> Mix.raise("Unknown profile.")
    end
  end

  defp to_existing_profiles(nil), do: nil

  defp to_existing_profiles(profiles) do
    profiles
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&to_existing_profile/1)
  end

  defp to_existing_dataset(nil), do: nil

  defp to_existing_dataset(dataset) do
    case PresidioResearchLoader.path_for(dataset) do
      {:ok, _path} ->
        String.to_existing_atom(dataset)

      {:error, {:unknown_presidio_research_dataset, _other}} ->
        Mix.raise("Unsupported dataset.")
    end
  end

  defp to_entities(nil), do: nil

  defp to_entities(entities) do
    known_entities = known_entities_by_name()

    entities
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn entity ->
      case Map.fetch(known_entities, entity) do
        {:ok, atom} -> atom
        :error -> Mix.raise("Unknown entity.")
      end
    end)
  end

  defp known_entities_by_name do
    [
      EntityMapping.phase_0_supported_entities(),
      EntityMapping.nlp_supported_entities(),
      EntityMapping.hybrid_ner_supported_entities(),
      EntityMapping.hybrid_gliner_supported_entities(),
      EntityMapping.deterministic_plus_supported_entities(),
      EntityMapping.phi_supported_entities()
    ]
    |> List.flatten()
    |> Enum.uniq()
    |> Map.new(&{Atom.to_string(&1), &1})
  end

  defp to_existing_model(nil), do: nil

  defp to_existing_model(model) do
    aliases = ModelRegistry.aliases()

    case Enum.find(aliases, &(Atom.to_string(&1) == model)) do
      nil -> Mix.raise("Unsupported model.")
      alias -> alias
    end
  end

  defp to_sample_ids(nil), do: nil

  defp to_sample_ids(sample_ids) do
    sample_ids
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn sample_id ->
      case Integer.parse(sample_id) do
        {id, ""} -> id
        _other -> sample_id
      end
    end)
  end

  defp to_thresholds(nil), do: nil

  defp to_thresholds(thresholds) do
    thresholds
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn threshold ->
      case Float.parse(threshold) do
        {value, ""} when value >= 0.0 and value <= 1.0 ->
          value

        _other ->
          Mix.raise("Invalid threshold. Thresholds must be floats from 0.0 to 1.0.")
      end
    end)
  end

  defp to_label_thresholds(nil), do: nil

  defp to_label_thresholds(thresholds) do
    thresholds
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Map.new(&parse_label_threshold!/1)
  end

  defp to_positive_integer_list(nil), do: nil
  defp to_positive_integer_list("none"), do: :disabled

  defp to_positive_integer_list(values) do
    values
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn value ->
      case Integer.parse(value) do
        {integer, ""} when integer > 0 -> integer
        _other -> Mix.raise("Expected a comma-separated list of positive integers.")
      end
    end)
  end

  defp to_privacy_filter_logprob_conversion(nil), do: nil
  defp to_privacy_filter_logprob_conversion("reference"), do: :reference
  defp to_privacy_filter_logprob_conversion("raw_logits"), do: :raw_logits

  defp to_privacy_filter_logprob_conversion(_other),
    do: Mix.raise("Unknown privacy-filter log-prob conversion. Use reference or raw_logits.")

  defp parse_label_threshold!(assignment) do
    with [label, threshold] when label != "" <- String.split(assignment, "=", parts: 2),
         {value, ""} <- Float.parse(threshold),
         true <- value >= 0.0 and value <= 1.0 do
      {label, value}
    else
      _other -> Mix.raise("Invalid label threshold. Use LABEL=0.95.")
    end
  end

  defp to_label_threshold_values(nil), do: nil

  defp to_label_threshold_values(values) do
    values
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Map.new(&parse_label_threshold_values!/1)
  end

  defp parse_label_threshold_values!(assignment) do
    with [label, values] when label != "" <- String.split(assignment, "=", parts: 2),
         parsed_values when parsed_values != [] <-
           values
           |> String.split("|", trim: true)
           |> Enum.map(&String.trim/1)
           |> Enum.map(&parse_threshold_value!/1) do
      {label, parsed_values}
    else
      _other ->
        Mix.raise("Invalid label threshold sweep values. Use LABEL=0.85|0.90.")
    end
  end

  defp parse_threshold_value!(threshold) do
    case Float.parse(threshold) do
      {value, ""} when value >= 0.0 and value <= 1.0 ->
        value

      _other ->
        Mix.raise("Invalid threshold. Thresholds must be floats from 0.0 to 1.0.")
    end
  end

  defp to_label_word_lists(nil), do: nil
  defp to_label_word_lists("none"), do: %{}

  defp to_label_word_lists(values) do
    values
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Map.new(&parse_label_words!/1)
  end

  defp parse_label_words!(assignment) do
    with [label, words] when label != "" <- String.split(assignment, "=", parts: 2),
         parsed_words when parsed_words != [] <-
           words
           |> String.split("|", trim: true)
           |> Enum.map(&String.trim/1)
           |> Enum.reject(&(&1 == "")) do
      {label, parsed_words}
    else
      _other -> Mix.raise("Invalid label word list. Use LABEL=word|phrase.")
    end
  end

  defp to_label_list(nil), do: nil
  defp to_label_list("none"), do: []

  defp to_label_list(labels) do
    labels
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp to_boundary_normalization(nil), do: nil
  defp to_boundary_normalization("none"), do: :none
  defp to_boundary_normalization("conservative"), do: :conservative

  defp to_boundary_normalization(_other),
    do: Mix.raise("Unknown NER boundary normalization. Use none or conservative.")

  defp to_conflict_strategy(nil), do: nil
  defp to_conflict_strategy("default"), do: :default
  defp to_conflict_strategy("none"), do: :none
  defp to_conflict_strategy("prefer_higher_confidence"), do: :prefer_higher_confidence
  defp to_conflict_strategy("prefer_longer"), do: :prefer_longer
  defp to_conflict_strategy("aggressive"), do: :aggressive

  defp to_conflict_strategy(_other) do
    Mix.raise(
      "Unknown conflict strategy. Use default, none, prefer_higher_confidence, prefer_longer, or aggressive."
    )
  end

  defp to_model_postprocessors(nil), do: nil
  defp to_model_postprocessors("none"), do: []

  defp to_model_postprocessors(postprocessors) do
    postprocessors
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&to_model_postprocessor/1)
  end

  defp to_model_postprocessor("organization_suffix_expansion"),
    do: :organization_suffix_expansion

  defp to_model_postprocessor("location_suffix_expansion"),
    do: :location_suffix_expansion

  defp to_model_postprocessor(_other) do
    Mix.raise(
      "Unknown NER model postprocessor. Use organization_suffix_expansion, location_suffix_expansion, or none."
    )
  end

  defp to_model_chunking(nil), do: nil
  defp to_model_chunking("none"), do: :none
  defp to_model_chunking("character"), do: :character

  defp to_model_chunking(_other),
    do: Mix.raise("Unknown NER model chunking. Use none or character.")

  defp to_policy_selection_objective(nil), do: nil

  defp to_policy_selection_objective("location_organization_recall"),
    do: :location_organization_recall

  defp to_policy_selection_objective("location_organization_f1"),
    do: :location_organization_f1

  defp to_policy_selection_objective("organization_f1"),
    do: :organization_f1

  defp to_policy_selection_objective("location_f1"),
    do: :location_f1

  defp to_policy_selection_objective("global_f1_under_fp_cap"),
    do: :global_f1_under_fp_cap

  defp to_policy_selection_objective("open_class_recall_under_global_f1_floor"),
    do: :open_class_recall_under_global_f1_floor

  defp to_policy_selection_objective(_other) do
    Mix.raise(
      "Unknown policy selection objective. Use location_organization_recall, location_organization_f1, organization_f1, location_f1, global_f1_under_fp_cap, or open_class_recall_under_global_f1_floor."
    )
  end

  defp to_cascade_trigger(nil), do: nil
  defp to_cascade_trigger("never"), do: :never
  defp to_cascade_trigger("missing"), do: :missing
  defp to_cascade_trigger("missing_or_uncertain"), do: :missing_or_uncertain
  defp to_cascade_trigger("always"), do: :always

  defp to_cascade_trigger(_other),
    do: Mix.raise("Unknown cascade trigger. Use never, missing, missing_or_uncertain, or always.")

  defp to_cascade_context_policy(nil), do: nil
  defp to_cascade_context_policy("none"), do: :none
  defp to_cascade_context_policy("strong"), do: :strong
  defp to_cascade_context_policy("strong_or_overlap"), do: :strong_or_overlap

  defp to_cascade_context_policy(_other) do
    Mix.raise("Unknown cascade context policy. Use none, strong, or strong_or_overlap.")
  end

  defp to_phone_parser(nil), do: nil
  defp to_phone_parser("ex_phone_number"), do: Obscura.Recognizer.Phone.ExPhoneNumberValidator

  defp to_phone_parser(_other),
    do: Mix.raise("Unknown phone parser. Use ex_phone_number.")

  defp to_string_list(nil), do: nil

  defp to_string_list(values) do
    values
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp to_existing_gliner_model(nil), do: nil

  defp to_existing_gliner_model(model) do
    aliases = GLiNERModelRegistry.aliases()

    case Enum.find(aliases, &(Atom.to_string(&1) == model)) do
      nil -> Mix.raise("Unsupported GLiNER model.")
      alias -> alias
    end
  end

  defp to_gliner_execution_providers(nil), do: nil

  defp to_gliner_execution_providers(providers) do
    providers
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&to_gliner_execution_provider/1)
  end

  defp to_gliner_execution_provider("cpu"), do: :cpu
  defp to_gliner_execution_provider("coreml"), do: :coreml
  defp to_gliner_execution_provider("cuda"), do: :cuda
  defp to_gliner_execution_provider("tensorrt"), do: :tensorrt
  defp to_gliner_execution_provider("acl"), do: :acl
  defp to_gliner_execution_provider("dnnl"), do: :dnnl
  defp to_gliner_execution_provider("onednn"), do: :onednn
  defp to_gliner_execution_provider("directml"), do: :directml
  defp to_gliner_execution_provider("rocm"), do: :rocm

  defp to_gliner_execution_provider(_other) do
    Mix.raise(
      "Unknown GLiNER Ortex execution provider. Use cpu, coreml, cuda, tensorrt, acl, dnnl, onednn, directml, or rocm."
    )
  end

  defp to_gliner_label_profile(nil), do: nil

  defp to_gliner_label_profile(profile) do
    case LabelMap.normalize_profile(profile) do
      {:ok, profile} ->
        profile

      {:error, {:unknown_gliner_label_profile, _other}} ->
        Mix.raise("Unknown GLiNER label profile.")
    end
  end

  defp to_template_split(nil), do: nil
  defp to_template_split("all"), do: :all
  defp to_template_split("template_train"), do: :template_train
  defp to_template_split("template_heldout"), do: :template_heldout

  defp to_template_split(_other),
    do: Mix.raise("Unknown template split. Use all, template_train, or template_heldout.")

  defp to_backend(nil), do: nil

  defp to_backend(backend) do
    case Backend.normalize(backend) do
      {:ok, backend} ->
        backend

      {:error, {:unsupported_real_model_backend, supported}} ->
        Mix.raise("Unsupported backend. Use one of: #{inspect(supported)}")
    end
  end

  defp to_privacy_filter_decoder(nil), do: nil
  defp to_privacy_filter_decoder("viterbi"), do: :viterbi
  defp to_privacy_filter_decoder("argmax"), do: :argmax

  defp to_privacy_filter_decoder(_other),
    do: Mix.raise("Unknown privacy-filter decoder. Use viterbi or argmax.")

  defp to_privacy_filter_label_map_mode(nil), do: nil
  defp to_privacy_filter_label_map_mode("default"), do: :default
  defp to_privacy_filter_label_map_mode("presidio_research"), do: :presidio_research
  defp to_privacy_filter_label_map_mode("supported"), do: :supported

  defp to_privacy_filter_label_map_mode(_other),
    do:
      Mix.raise(
        "Unknown privacy-filter label map mode. Use default, presidio_research, or supported."
      )

  defp compile_opts(parsed) do
    batch_size = Keyword.get(parsed, :compile_batch_size)
    sequence_length = Keyword.get(parsed, :compile_sequence_length)

    if is_integer(batch_size) or is_integer(sequence_length) do
      [
        batch_size: batch_size || 1,
        sequence_length: sequence_length || 128
      ]
    end
  end
end
