defmodule Obscura.Recognizer.NER.Config do
  @moduledoc """
  Normalizes NER recognizer options.
  """

  alias Obscura.Recognizer.NER.LabelMap
  alias Obscura.Recognizer.NER.Policy

  @default_score_threshold 0.0
  @default_low_confidence_score_multiplier 0.4

  @doc """
  Merges analyzer and recognizer tuple options.
  """
  @spec new(keyword(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def new(analyzer_opts, recognizer_opts \\ []) do
    ner_opts = Keyword.get(analyzer_opts, :ner, [])

    opts =
      analyzer_opts
      |> Keyword.merge(ner_opts)
      |> Keyword.merge(recognizer_opts)
      |> Keyword.put_new(:label_map, LabelMap.default())
      |> Keyword.put_new(:score_threshold, @default_score_threshold)
      |> Keyword.put_new(:labels_to_ignore, default_labels_to_ignore(analyzer_opts))
      |> Keyword.put_new(:per_entity_thresholds, default_entity_thresholds(analyzer_opts))
      |> Keyword.put_new(:per_label_thresholds, default_label_thresholds(analyzer_opts))
      |> Keyword.put_new(:low_score_entity_names, [])
      |> Keyword.put_new(:low_score_labels, default_low_score_labels(analyzer_opts))
      |> Keyword.put_new(:context_required_labels, default_context_required_labels(analyzer_opts))
      |> Keyword.put_new(:context_required_below_thresholds, default_context_gates(analyzer_opts))
      |> Keyword.put_new(
        :context_required_below_labels,
        default_label_context_gates(analyzer_opts)
      )
      |> Keyword.put_new(:context_words_by_entity, default_context_words(analyzer_opts))
      |> Keyword.put_new(:context_words_by_label, default_label_context_words(analyzer_opts))
      |> Keyword.put_new(
        :weak_context_words_by_label,
        default_weak_label_context_words(analyzer_opts)
      )
      |> Keyword.put_new(
        :negative_context_words_by_label,
        default_negative_label_context_words(analyzer_opts)
      )
      |> Keyword.put_new(
        :negative_context_reject_labels,
        default_negative_context_reject_labels(analyzer_opts)
      )
      |> Keyword.put_new(
        :low_confidence_score_multiplier,
        @default_low_confidence_score_multiplier
      )
      |> Keyword.put_new(:aggregation_strategy, Keyword.get(analyzer_opts, :aggregation, :same))
      |> Keyword.put_new(:alignment_mode, :expand)
      |> Keyword.put_new(:boundary_normalization, :none)
      |> Keyword.put_new(:model_postprocessors, [])
      |> Keyword.put_new(:model_chunking, :none)
      |> Keyword.put_new(:model_chunk_size, 400)
      |> Keyword.put_new(:model_chunk_overlap, 40)
      |> Keyword.put_new(:validate_structured_model_entities, false)

    with {:ok, label_map} <- LabelMap.normalize_label_map(Keyword.fetch!(opts, :label_map)),
         {:ok, labels_to_ignore} <- normalize_labels(Keyword.fetch!(opts, :labels_to_ignore)),
         {:ok, per_entity_thresholds} <-
           normalize_per_entity_thresholds(Keyword.fetch!(opts, :per_entity_thresholds)),
         {:ok, per_label_thresholds} <-
           normalize_per_label_thresholds(Keyword.fetch!(opts, :per_label_thresholds)),
         {:ok, low_score_entity_names} <-
           normalize_entities(Keyword.fetch!(opts, :low_score_entity_names)),
         {:ok, low_score_labels} <-
           normalize_labels(Keyword.fetch!(opts, :low_score_labels), :invalid_low_score_labels),
         {:ok, context_required_labels} <-
           normalize_labels(
             Keyword.fetch!(opts, :context_required_labels),
             :invalid_context_required_labels
           ),
         {:ok, context_required_below_thresholds} <-
           normalize_per_entity_thresholds(
             Keyword.fetch!(opts, :context_required_below_thresholds)
           ),
         {:ok, context_required_below_labels} <-
           normalize_per_label_thresholds(Keyword.fetch!(opts, :context_required_below_labels)),
         {:ok, context_words_by_entity} <-
           normalize_context_words(Keyword.fetch!(opts, :context_words_by_entity)),
         {:ok, context_words_by_label} <-
           normalize_label_context_words(Keyword.fetch!(opts, :context_words_by_label)),
         {:ok, weak_context_words_by_label} <-
           normalize_label_context_words(Keyword.fetch!(opts, :weak_context_words_by_label)),
         {:ok, negative_context_words_by_label} <-
           normalize_label_context_words(Keyword.fetch!(opts, :negative_context_words_by_label)),
         {:ok, negative_context_reject_labels} <-
           normalize_labels(
             Keyword.fetch!(opts, :negative_context_reject_labels),
             :invalid_negative_context_reject_labels
           ),
         :ok <- validate_multiplier(Keyword.fetch!(opts, :low_confidence_score_multiplier)),
         :ok <- validate_aggregation_strategy(Keyword.fetch!(opts, :aggregation_strategy)),
         :ok <- validate_alignment_mode(Keyword.fetch!(opts, :alignment_mode)),
         :ok <- validate_boundary_normalization(Keyword.fetch!(opts, :boundary_normalization)),
         {:ok, model_postprocessors} <-
           normalize_model_postprocessors(Keyword.fetch!(opts, :model_postprocessors)),
         :ok <- validate_model_chunking(Keyword.fetch!(opts, :model_chunking)),
         :ok <- validate_model_chunk_size(Keyword.fetch!(opts, :model_chunk_size)),
         :ok <-
           validate_model_chunk_overlap(
             Keyword.fetch!(opts, :model_chunk_overlap),
             Keyword.fetch!(opts, :model_chunk_size)
           ),
         :ok <-
           validate_boolean(
             Keyword.fetch!(opts, :validate_structured_model_entities),
             :invalid_validate_structured_model_entities
           ) do
      {:ok,
       opts
       |> Keyword.put(:label_map, label_map)
       |> Keyword.put(:labels_to_ignore, labels_to_ignore)
       |> Keyword.put(:per_entity_thresholds, per_entity_thresholds)
       |> Keyword.put(:per_label_thresholds, per_label_thresholds)
       |> Keyword.put(:low_score_entity_names, low_score_entity_names)
       |> Keyword.put(:low_score_labels, low_score_labels)
       |> Keyword.put(:context_required_labels, context_required_labels)
       |> Keyword.put(:context_required_below_thresholds, context_required_below_thresholds)
       |> Keyword.put(:context_required_below_labels, context_required_below_labels)
       |> Keyword.put(:context_words_by_entity, context_words_by_entity)
       |> Keyword.put(:context_words_by_label, context_words_by_label)
       |> Keyword.put(:weak_context_words_by_label, weak_context_words_by_label)
       |> Keyword.put(:negative_context_words_by_label, negative_context_words_by_label)
       |> Keyword.put(:negative_context_reject_labels, negative_context_reject_labels)
       |> Keyword.put(:model_postprocessors, model_postprocessors)}
    end
  end

  defp default_entity_thresholds(opts) do
    case Keyword.get(opts, :profile) do
      profile
      when profile in [
             :hybrid_ner,
             :hybrid_ner_conservative,
             :hybrid_ner_org,
             :hybrid_ner_org_high_recall
           ] ->
        %{organization: 0.85}

      profile when profile in [:hybrid_ner_balanced, :hybrid_ner_dbmdz_conservative] ->
        %{organization: 0.9}

      profile when profile in [:hybrid_ner_tner_conservative, :hybrid_ner_tner_high_recall] ->
        %{organization: 0.95, location: 0.8}

      :hybrid_ner_bigmed_conservative ->
        Policy.bigmed_conservative_thresholds()

      _profile ->
        %{}
    end
  end

  defp default_label_thresholds(opts) do
    case Keyword.get(opts, :profile) do
      :hybrid_ner_tner_conservative ->
        %{
          "PERSON" => 0.72,
          "ORG" => 0.98,
          "GPE" => 0.9,
          "LOC" => 0.92,
          "FAC" => 0.97
        }

      :hybrid_ner_tner_high_recall ->
        %{
          "PERSON" => 0.7,
          "ORG" => 0.95,
          "GPE" => 0.84,
          "LOC" => 0.88,
          "FAC" => 0.92
        }

      _profile ->
        %{}
    end
  end

  defp default_labels_to_ignore(opts) do
    case Keyword.get(opts, :profile) do
      profile when profile in [:hybrid_ner, :hybrid_ner_conservative] ->
        ["ORG", "ORGANIZATION", "B-ORG", "I-ORG"]

      :hybrid_ner_dbmdz_conservative ->
        ["MISC"]

      profile when profile in [:hybrid_ner_tner_conservative, :hybrid_ner_tner_high_recall] ->
        tner_conservative_labels_to_ignore()

      :hybrid_ner_bigmed_conservative ->
        bigmed_conservative_labels_to_ignore()

      _profile ->
        []
    end
  end

  defp default_context_gates(opts) do
    case Keyword.get(opts, :profile) do
      :hybrid_ner_balanced ->
        %{organization: 0.95}

      :hybrid_ner_org ->
        %{organization: 0.95}

      :hybrid_ner_org_high_recall ->
        %{organization: 0.95}

      :hybrid_ner_dbmdz_conservative ->
        %{organization: 0.95}

      profile when profile in [:hybrid_ner_tner_conservative, :hybrid_ner_tner_high_recall] ->
        %{organization: 0.98}

      _profile ->
        %{}
    end
  end

  defp default_label_context_gates(opts) do
    case Keyword.get(opts, :profile) do
      :hybrid_ner_tner_conservative ->
        %{
          "ORG" => 0.99,
          "LOC" => 0.96,
          "FAC" => 0.99
        }

      :hybrid_ner_tner_high_recall ->
        %{
          "ORG" => 0.98,
          "LOC" => 0.94,
          "FAC" => 0.97
        }

      _profile ->
        %{}
    end
  end

  defp default_low_score_labels(_opts), do: []

  defp default_context_required_labels(opts) do
    case Keyword.get(opts, :profile) do
      :hybrid_ner_tner_conservative -> ["FAC"]
      _profile -> []
    end
  end

  defp default_context_words(opts) do
    case Keyword.get(opts, :profile) do
      profile
      when profile in [
             :hybrid_ner_balanced,
             :hybrid_ner_org,
             :hybrid_ner_org_high_recall,
             :hybrid_ner_dbmdz_conservative
           ] ->
        %{
          organization: [
            "company",
            "employer",
            "organization",
            "works at",
            "work at",
            "affiliated with"
          ]
        }

      profile when profile in [:hybrid_ner_tner_conservative, :hybrid_ner_tner_high_recall] ->
        %{
          organization: [
            "company",
            "employer",
            "organization",
            "works at",
            "work at",
            "affiliated with"
          ],
          location: [
            "address",
            "city",
            "country",
            "facility",
            "headquartered",
            "hospital",
            "in",
            "located",
            "location",
            "office",
            "state"
          ]
        }

      _profile ->
        %{}
    end
  end

  defp default_label_context_words(opts) do
    case Keyword.get(opts, :profile) do
      profile when profile in [:hybrid_ner_tner_conservative, :hybrid_ner_tner_high_recall] ->
        Policy.ontonotes_context_words_by_label()

      _profile ->
        %{}
    end
  end

  defp default_weak_label_context_words(opts) do
    case Keyword.get(opts, :profile) do
      profile when profile in [:hybrid_ner_tner_conservative, :hybrid_ner_tner_high_recall] ->
        %{"FAC" => ["in"]}

      _profile ->
        %{}
    end
  end

  defp default_negative_label_context_words(opts) do
    case Keyword.get(opts, :profile) do
      :hybrid_ner_tner_conservative ->
        %{
          "GPE" => [
            "account",
            "case",
            "code",
            "invoice",
            "order",
            "payment",
            "product",
            "reference",
            "ticket"
          ]
        }

      _profile ->
        %{}
    end
  end

  defp default_negative_context_reject_labels(opts) do
    case Keyword.get(opts, :profile) do
      :hybrid_ner_tner_conservative -> ["GPE"]
      _profile -> []
    end
  end

  defp normalize_labels(labels), do: normalize_labels(labels, :invalid_labels_to_ignore)

  defp normalize_labels(labels, error) when is_list(labels) do
    if Enum.all?(labels, &is_binary/1),
      do: {:ok, labels},
      else: {:error, error}
  end

  defp normalize_labels(_labels, error), do: {:error, error}

  defp normalize_per_entity_thresholds(thresholds)
       when is_map(thresholds) or is_list(thresholds) do
    thresholds
    |> Enum.reduce_while({:ok, %{}}, fn {entity, threshold}, {:ok, acc} ->
      cond do
        not is_atom(entity) ->
          {:halt, {:error, :invalid_per_entity_thresholds}}

        not is_number(threshold) or threshold < 0.0 or threshold > 1.0 ->
          {:halt, {:error, :invalid_per_entity_thresholds}}

        true ->
          {:cont, {:ok, Map.put(acc, entity, threshold / 1)}}
      end
    end)
  end

  defp normalize_per_entity_thresholds(_thresholds), do: {:error, :invalid_per_entity_thresholds}

  defp normalize_per_label_thresholds(thresholds)
       when is_map(thresholds) or is_list(thresholds) do
    thresholds
    |> Enum.reduce_while({:ok, %{}}, fn {label, threshold}, {:ok, acc} ->
      cond do
        not is_binary(label) ->
          {:halt, {:error, :invalid_per_label_thresholds}}

        not is_number(threshold) or threshold < 0.0 or threshold > 1.0 ->
          {:halt, {:error, :invalid_per_label_thresholds}}

        true ->
          {:cont, {:ok, Map.put(acc, label, threshold / 1)}}
      end
    end)
  end

  defp normalize_per_label_thresholds(_thresholds), do: {:error, :invalid_per_label_thresholds}

  defp normalize_entities(entities) when is_list(entities) do
    if Enum.all?(entities, &is_atom/1),
      do: {:ok, entities},
      else: {:error, :invalid_low_score_entity_names}
  end

  defp normalize_entities(_entities), do: {:error, :invalid_low_score_entity_names}

  defp normalize_context_words(words_by_entity) when is_map(words_by_entity) do
    words_by_entity
    |> Enum.reduce_while({:ok, %{}}, fn {entity, words}, {:ok, acc} ->
      cond do
        not is_atom(entity) ->
          {:halt, {:error, :invalid_context_words_by_entity}}

        not is_list(words) ->
          {:halt, {:error, :invalid_context_words_by_entity}}

        not Enum.all?(words, &is_binary/1) ->
          {:halt, {:error, :invalid_context_words_by_entity}}

        true ->
          {:cont, {:ok, Map.put(acc, entity, Enum.uniq(words))}}
      end
    end)
  end

  defp normalize_context_words(words_by_entity) when is_list(words_by_entity) do
    words_by_entity
    |> Map.new()
    |> normalize_context_words()
  rescue
    _error -> {:error, :invalid_context_words_by_entity}
  end

  defp normalize_context_words(_words_by_entity), do: {:error, :invalid_context_words_by_entity}

  defp normalize_label_context_words(words_by_label) when is_map(words_by_label) do
    words_by_label
    |> Enum.reduce_while({:ok, %{}}, fn {label, words}, {:ok, acc} ->
      cond do
        not is_binary(label) ->
          {:halt, {:error, :invalid_context_words_by_label}}

        not is_list(words) ->
          {:halt, {:error, :invalid_context_words_by_label}}

        not Enum.all?(words, &is_binary/1) ->
          {:halt, {:error, :invalid_context_words_by_label}}

        true ->
          {:cont, {:ok, Map.put(acc, label, Enum.uniq(words))}}
      end
    end)
  end

  defp normalize_label_context_words(words_by_label) when is_list(words_by_label) do
    words_by_label
    |> Map.new()
    |> normalize_label_context_words()
  rescue
    _error -> {:error, :invalid_context_words_by_label}
  end

  defp normalize_label_context_words(_words_by_label),
    do: {:error, :invalid_context_words_by_label}

  defp validate_multiplier({:ok, multiplier}), do: validate_multiplier(multiplier)

  defp validate_multiplier(multiplier) when is_number(multiplier) and multiplier >= 0.0,
    do: :ok

  defp validate_multiplier(_multiplier), do: {:error, :invalid_low_confidence_score_multiplier}

  defp validate_aggregation_strategy({:ok, strategy}), do: validate_aggregation_strategy(strategy)

  defp validate_aggregation_strategy(strategy)
       when strategy in [:same, :simple, :first, :average, :max],
       do: :ok

  defp validate_aggregation_strategy(_strategy), do: {:error, :invalid_aggregation_strategy}

  defp validate_alignment_mode({:ok, mode}), do: validate_alignment_mode(mode)

  defp validate_alignment_mode(mode) when mode in [:strict, :contract, :expand], do: :ok
  defp validate_alignment_mode(_mode), do: {:error, :invalid_alignment_mode}

  defp validate_boundary_normalization({:ok, mode}), do: validate_boundary_normalization(mode)

  defp validate_boundary_normalization(mode) when mode in [:none, :conservative], do: :ok

  defp validate_boundary_normalization(_mode),
    do: {:error, :invalid_boundary_normalization}

  defp normalize_model_postprocessors({:ok, postprocessors}),
    do: normalize_model_postprocessors(postprocessors)

  defp normalize_model_postprocessors(postprocessors) when is_list(postprocessors) do
    valid = [:organization_suffix_expansion, :location_suffix_expansion]

    if Enum.all?(postprocessors, &(&1 in valid)) do
      {:ok, Enum.uniq(postprocessors)}
    else
      {:error, :invalid_model_postprocessors}
    end
  end

  defp normalize_model_postprocessors(_postprocessors),
    do: {:error, :invalid_model_postprocessors}

  defp validate_model_chunking({:ok, mode}), do: validate_model_chunking(mode)
  defp validate_model_chunking(mode) when mode in [:none, :character], do: :ok
  defp validate_model_chunking(_mode), do: {:error, :invalid_model_chunking}

  defp validate_model_chunk_size({:ok, size}), do: validate_model_chunk_size(size)
  defp validate_model_chunk_size(size) when is_integer(size) and size > 0, do: :ok
  defp validate_model_chunk_size(_size), do: {:error, :invalid_model_chunk_size}

  defp validate_model_chunk_overlap({:ok, overlap}, {:ok, size}),
    do: validate_model_chunk_overlap(overlap, size)

  defp validate_model_chunk_overlap(overlap, size)
       when is_integer(overlap) and is_integer(size) and overlap >= 0 and overlap < size,
       do: :ok

  defp validate_model_chunk_overlap(_overlap, _size),
    do: {:error, :invalid_model_chunk_overlap}

  defp validate_boolean({:ok, value}, error), do: validate_boolean(value, error)
  defp validate_boolean(value, _error) when is_boolean(value), do: :ok
  defp validate_boolean(_value, error), do: {:error, error}

  defp bigmed_conservative_labels_to_ignore do
    [
      "age",
      "coordinate",
      "county",
      "date",
      "date_of_birth",
      "date_time",
      "fax_number",
      "gender",
      "health_plan_beneficiary_number",
      "medical_record_number",
      "postcode",
      "private_address",
      "private_date",
      "state",
      "street_address",
      "time"
    ]
  end

  defp tner_conservative_labels_to_ignore do
    [
      "B-CARDINAL",
      "I-CARDINAL",
      "B-DATE",
      "I-DATE",
      "B-EVENT",
      "I-EVENT",
      "B-LANGUAGE",
      "I-LANGUAGE",
      "B-LAW",
      "I-LAW",
      "B-MONEY",
      "I-MONEY",
      "B-NORP",
      "I-NORP",
      "B-ORDINAL",
      "I-ORDINAL",
      "B-PERCENT",
      "I-PERCENT",
      "B-PRODUCT",
      "I-PRODUCT",
      "B-QUANTITY",
      "I-QUANTITY",
      "B-TIME",
      "I-TIME",
      "B-WORK_OF_ART",
      "I-WORK_OF_ART"
    ]
  end
end
