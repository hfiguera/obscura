defmodule Obscura.Eval.PresidioCompatibility do
  @moduledoc """
  Presidio and Presidio-Research compatibility benchmark runner.

  This runner evaluates Obscura against converted Presidio-Research gold
  datasets without importing Python modules or mutating the inspiration
  repositories.
  """

  alias Obscura.Eval.EntityMapping
  alias Obscura.Eval.Metrics
  alias Obscura.Eval.ModelOutputs
  alias Obscura.Eval.PresidioResearchLoader
  alias Obscura.Eval.Profile
  alias Obscura.Eval.Report
  alias Obscura.Fixtures.ObscuraAnalyzerAdapter
  alias Obscura.NLP.Engine.Bumblebee, as: BumblebeeEngine
  alias Obscura.PrivacyFilter.LabelMap, as: PrivacyFilterLabelMap
  alias Obscura.PrivacyFilter.OpenMedPolicy
  alias Obscura.PrivacyFilter.Serving, as: PrivacyFilterServing
  alias Obscura.Profile, as: ProductProfile
  alias Obscura.Recognizer.GLiNER
  alias Obscura.Recognizer.GLiNER.LabelMap
  alias Obscura.Recognizer.GLiNER.ModelRegistry, as: GLiNERModelRegistry
  alias Obscura.Recognizer.GLiNER.Native, as: GLiNERNative
  alias Obscura.Recognizer.GLiNER.Ortex, as: GLiNEROrtex
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.Backend
  alias Obscura.Recognizer.NER.FakeServing
  alias Obscura.Recognizer.NER.LocationGate
  alias Obscura.Recognizer.NER.ModelRegistry
  alias Obscura.Recognizer.NER.Routing
  alias Obscura.Recognizer.NER.Secondary, as: SecondaryNER
  alias Obscura.Recognizer.NER.Serving
  alias Obscura.Recognizer.PrivacyFilter.Native, as: PrivacyFilterNative

  @default_smoke_dataset :generated_small
  @default_full_dataset :synth_dataset_v2
  @default_limit 25
  @default_thresholds [0.6, 0.7, 0.8, 0.9]
  @v18_tner_label_thresholds %{
    "PERSON" => 0.68,
    "ORG" => 0.98,
    "GPE" => 0.9,
    "LOC" => 0.92,
    "FAC" => 0.97
  }
  @v18_tner_context_gates %{"ORG" => 0.99, "LOC" => 0.96, "FAC" => 0.99}
  @v18_tner_context_required_labels ["FAC"]
  @v18_tner_negative_context_words %{
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
  @v18_tner_negative_context_reject_labels ["GPE"]
  @v21_extended_gpe_negative_context [
    "account",
    "authorization",
    "case",
    "claim",
    "code",
    "confirmation",
    "id",
    "invoice",
    "member",
    "number",
    "order",
    "payment",
    "policy",
    "product",
    "reference",
    "shipment",
    "ticket",
    "tracking",
    "transaction"
  ]
  @v21_org_context_words [
    "affiliated with",
    "business",
    "company",
    "department",
    "employer",
    "hospital",
    "institution",
    "organization",
    "university",
    "work at",
    "works at"
  ]
  @v21_loc_context_words [
    "address",
    "city",
    "country",
    "county",
    "geography",
    "located",
    "location",
    "municipality",
    "province",
    "region",
    "residence",
    "state"
  ]
  @v21_fac_context_words [
    "airport",
    "branch",
    "building",
    "campus",
    "center",
    "centre",
    "clinic",
    "facility",
    "headquarters",
    "hospital",
    "office",
    "school",
    "station",
    "terminal",
    "university"
  ]
  @model_label_fp_labels ["GPE", "FAC", "LOC", "ORG", "PERSON"]
  @real_model_profiles [
    :real_ner,
    :hybrid_ner,
    :hybrid_ner_conservative,
    :hybrid_ner_balanced,
    :hybrid_ner_org,
    :hybrid_ner_org_high_recall,
    :hybrid_ner_dbmdz_conservative,
    :hybrid_ner_tner_conservative,
    :hybrid_ner_tner_high_recall,
    :hybrid_ner_tner_facebookai_org,
    :hybrid_ner_tner_jean_location,
    :hybrid_ner_tner_jean_location_gated,
    :hybrid_ner_tner_jean_location_cascade,
    :hybrid_ner_bigmed_conservative
  ]
  @gliner_ortex_profiles [:gliner_ortex, :hybrid_gliner_ortex, :hybrid_gliner_urchade]
  @gliner_native_profiles [:hybrid_gliner_urchade_native]
  @gliner_profiles @gliner_ortex_profiles ++ @gliner_native_profiles
  @privacy_filter_profiles [:privacy_filter_native, :hybrid_privacy_filter_native]
  @hybrid_gliner_open_class_thresholds %{
    "person" => 0.5,
    "organization" => 0.5,
    "location" => 0.5
  }
  @urchade_train_selected_thresholds %{
    "person" => 0.5,
    "organization" => 0.9,
    "location" => 0.5
  }

  @doc """
  Runs one compatibility benchmark report.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    with {:ok, opts} <- normalize_product_profile_opts(opts) do
      do_run(opts)
    end
  end

  defp do_run(opts) do
    profile = Keyword.get(opts, :profile, :regex_only)

    case opt_in_skip_reason(profile, opts) do
      nil ->
        run_opted_in_profile(profile, opts)

      reason ->
        {:ok, skipped_report(profile, dataset_for(opts), reason, opts)}
    end
  end

  defp run_opted_in_profile(profile, opts) do
    run_local_profile(Keyword.put(opts, :profile, profile))
  end

  defp opt_in_skip_reason(profile, opts) when profile in @gliner_native_profiles do
    if gliner_native_opt_in?(opts), do: nil, else: "Native GLiNER opt-in missing."
  end

  defp opt_in_skip_reason(profile, opts) when profile in @gliner_ortex_profiles do
    if gliner_ortex_opt_in?(opts), do: nil, else: "GLiNER Ortex opt-in missing."
  end

  defp opt_in_skip_reason(profile, opts) when profile in @privacy_filter_profiles do
    cond do
      not privacy_filter_opt_in?(opts) ->
        "Native privacy-filter opt-in missing."

      is_nil(privacy_filter_checkpoint(opts)) ->
        "Native privacy-filter checkpoint missing. Set OBSCURA_PRIVACY_FILTER_CHECKPOINT or pass :privacy_filter_checkpoint."

      true ->
        nil
    end
  end

  defp opt_in_skip_reason(profile, opts) when profile in @real_model_profiles do
    if real_model_opt_in?(opts), do: nil, else: "Real local model opt-in missing."
  end

  defp opt_in_skip_reason(_profile, _opts), do: nil

  @doc """
  Runs one compatibility benchmark and writes JSON and Markdown reports.
  """
  @spec write_report(keyword()) :: :ok | {:error, term()}
  def write_report(opts \\ []) do
    runner =
      cond do
        Keyword.get(opts, :policy_sweep, false) -> &run_policy_sweep/1
        Keyword.get(opts, :label_threshold_sweep, false) -> &run_label_threshold_sweep/1
        Keyword.get(opts, :threshold_sweep, false) -> &run_threshold_sweep/1
        true -> &run/1
      end

    case runner.(opts) do
      {:ok, report} ->
        Report.write_pair(
          report,
          "eval/reports/#{report.run_id}.json",
          "eval/reports/#{report.run_id}.md"
        )

      {:error, {:missing_presidio_research_dataset, path, reason}} ->
        write_missing_dataset_report(opts, path, reason)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Runs a threshold sweep for a real local NER compatibility profile.
  """
  @spec run_threshold_sweep(keyword()) :: {:ok, map()} | {:error, term()}
  def run_threshold_sweep(opts \\ []) do
    with {:ok, opts} <- normalize_product_profile_opts(opts) do
      do_run_threshold_sweep(opts)
    end
  end

  defp do_run_threshold_sweep(opts) do
    profile = Keyword.get(opts, :profile, :hybrid_ner_org)
    dataset = dataset_for(opts)

    cond do
      profile in @gliner_profiles ->
        if gliner_profile_opted_in?(profile, opts) do
          run_gliner_label_threshold_sweep(profile, dataset, opts)
        else
          {:ok, skipped_report(profile, dataset, "GLiNER opt-in missing.", opts)}
        end

      profile not in @real_model_profiles ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           "Threshold sweeps are currently defined for real local NER profiles only.",
           opts
         )}

      not real_model_opt_in?(opts) ->
        {:ok, skipped_report(profile, dataset, "Real local model opt-in missing.", opts)}

      true ->
        run_real_threshold_sweep(profile, dataset, opts)
    end
  end

  @doc """
  Runs a coordinate label-threshold sweep for a real local NER compatibility profile.
  """
  @spec run_label_threshold_sweep(keyword()) :: {:ok, map()} | {:error, term()}
  def run_label_threshold_sweep(opts \\ []) do
    with {:ok, opts} <- normalize_product_profile_opts(opts) do
      do_run_label_threshold_sweep(opts)
    end
  end

  defp do_run_label_threshold_sweep(opts) do
    profile = Keyword.get(opts, :profile, :hybrid_ner_tner_conservative)
    dataset = dataset_for(opts)

    cond do
      profile in @gliner_profiles ->
        if gliner_profile_opted_in?(profile, opts) do
          run_gliner_label_threshold_sweep(profile, dataset, opts)
        else
          {:ok, skipped_report(profile, dataset, "GLiNER opt-in missing.", opts)}
        end

      profile not in @real_model_profiles ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           "Label-threshold sweeps are currently defined for real local NER profiles only.",
           opts
         )}

      not real_model_opt_in?(opts) ->
        {:ok, skipped_report(profile, dataset, "Real local model opt-in missing.", opts)}

      true ->
        run_real_label_threshold_sweep(profile, dataset, opts)
    end
  end

  @doc """
  Runs a named policy sweep for a real local NER compatibility profile.
  """
  @spec run_policy_sweep(keyword()) :: {:ok, map()} | {:error, term()}
  def run_policy_sweep(opts \\ []) do
    with {:ok, opts} <- normalize_product_profile_opts(opts) do
      do_run_policy_sweep(opts)
    end
  end

  defp do_run_policy_sweep(opts) do
    profile = Keyword.get(opts, :profile, :hybrid_ner_tner_conservative)
    dataset = dataset_for(opts)

    cond do
      profile not in @real_model_profiles ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           "Policy sweeps are currently defined for real local NER profiles only.",
           opts
         )}

      not real_model_opt_in?(opts) ->
        {:ok, skipped_report(profile, dataset, "Real local model opt-in missing.", opts)}

      true ->
        run_real_policy_sweep(profile, dataset, opts)
    end
  end

  @doc """
  Runs separate reports for several profiles.
  """
  @spec write_reports(keyword()) :: :ok | {:error, term()}
  def write_reports(opts \\ []) do
    opts
    |> Keyword.get(:profiles, [Keyword.get(opts, :profile, :regex_only)])
    |> Enum.reduce_while(:ok, fn profile, :ok ->
      case write_report(Keyword.put(opts, :profile, profile)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_local_profile(opts) do
    profile = Keyword.get(opts, :profile, :regex_only)
    dataset = dataset_for(opts)

    with {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: profile,
             invalid_span: :drop_sample,
             template_split: Keyword.get(opts, :template_split, :all),
             template_train_ratio: Keyword.get(opts, :template_train_ratio, 0.7)
           ),
         samples <- samples(loaded.samples, profile, opts),
         opts <- maybe_put_privacy_filter_dataset_policy(opts, loaded, profile),
         {:ok, serving} <- serving(profile, opts),
         {:ok, results} <- run_samples(samples, profile, serving, opts),
         metrics <-
           results
           |> score_results(profile, opts)
           |> Map.put(:output_fingerprint_sha256, output_fingerprint(results)),
         report <- build_report(loaded, samples, metrics, profile, report_opts(opts, serving)) do
      {:ok, report}
    else
      {:error, reason}
      when profile in @real_model_profiles or profile in @gliner_profiles or
             profile in @privacy_filter_profiles ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           safe_compatibility_failure(profile, reason),
           opts
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp profile_group_label(profile) when profile in @privacy_filter_profiles,
    do: "Native privacy-filter"

  defp profile_group_label(profile) when profile in @gliner_ortex_profiles, do: "GLiNER Ortex"
  defp profile_group_label(profile) when profile in @gliner_native_profiles, do: "GLiNER Native"
  defp profile_group_label(_profile), do: "Real local model"

  defp report_opts(opts, serving), do: Keyword.put(opts, :runtime_serving, serving)

  defp run_real_threshold_sweep(profile, dataset, opts) do
    with {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: profile,
             invalid_span: :drop_sample,
             template_split: Keyword.get(opts, :template_split, :all),
             template_train_ratio: Keyword.get(opts, :template_train_ratio, 0.7)
           ),
         samples <- samples(loaded.samples, profile, opts),
         {:ok, serving} <- serving(profile, opts),
         {:ok, sweep_rows} <- threshold_sweep_rows(samples, profile, serving, opts),
         best <- best_threshold_row(sweep_rows),
         best_metrics <- Map.fetch!(best, :metrics),
         report <-
           build_report(
             loaded,
             samples,
             best_metrics,
             profile,
             Keyword.put(opts, :threshold_sweep_data, %{
               rows: Enum.map(sweep_rows, &Map.drop(&1, [:metrics])),
               best: Map.drop(best, [:metrics])
             })
           ) do
      {:ok, report}
    else
      {:error, _reason} ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           "Real local model threshold sweep failed during execution.",
           opts
         )}
    end
  end

  defp run_real_label_threshold_sweep(profile, dataset, opts) do
    with {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: profile,
             invalid_span: :drop_sample,
             template_split: Keyword.get(opts, :template_split, :all),
             template_train_ratio: Keyword.get(opts, :template_train_ratio, 0.7)
           ),
         samples <- samples(loaded.samples, profile, opts),
         {:ok, serving} <- serving(profile, opts),
         {:ok, sweep_rows} <- label_threshold_sweep_rows(samples, profile, serving, opts),
         best <- best_threshold_row(sweep_rows, opts),
         best_metrics <- Map.fetch!(best, :metrics),
         report <-
           build_report(
             loaded,
             samples,
             best_metrics,
             profile,
             Keyword.put(opts, :threshold_sweep_data, %{
               mode: :label_threshold,
               rows: Enum.map(sweep_rows, &Map.drop(&1, [:metrics])),
               best: Map.drop(best, [:metrics])
             })
           ) do
      {:ok, report}
    else
      {:error, _reason} ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           "Real local model label-threshold sweep failed during execution.",
           opts
         )}
    end
  end

  defp run_gliner_label_threshold_sweep(profile, dataset, opts) do
    with {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: profile,
             invalid_span: :drop_sample,
             template_split: Keyword.get(opts, :template_split, :all),
             template_train_ratio: Keyword.get(opts, :template_train_ratio, 0.7)
           ),
         samples <- samples(loaded.samples, profile, opts),
         {:ok, serving} <- serving(profile, opts),
         {:ok, sweep_rows} <- gliner_label_threshold_sweep_rows(samples, profile, serving, opts),
         best <- best_gliner_threshold_row(sweep_rows, opts),
         best_metrics <- Map.fetch!(best, :metrics),
         report <-
           build_report(
             loaded,
             samples,
             best_metrics,
             profile,
             Keyword.put(opts, :threshold_sweep_data, %{
               mode: :gliner_label_threshold,
               rows: Enum.map(sweep_rows, &Map.drop(&1, [:metrics])),
               best: Map.drop(best, [:metrics])
             })
           ) do
      {:ok, report}
    else
      {:error, _reason} ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           "GLiNER label-threshold sweep failed during execution.",
           opts
         )}
    end
  end

  defp run_real_policy_sweep(profile, dataset, opts) do
    with {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: profile,
             invalid_span: :drop_sample,
             template_split: Keyword.get(opts, :template_split, :all),
             template_train_ratio: Keyword.get(opts, :template_train_ratio, 0.7)
           ),
         samples <- samples(loaded.samples, profile, opts),
         {:ok, serving} <- serving(profile, opts),
         {:ok, sweep_rows} <- policy_sweep_rows(samples, profile, serving, opts),
         best <- select_policy_row(sweep_rows, opts),
         best_metrics <- Map.fetch!(best, :metrics),
         report <-
           build_report(
             loaded,
             samples,
             best_metrics,
             profile,
             Keyword.put(opts, :threshold_sweep_data, %{
               mode: :policy,
               selection_objective: policy_selection_objective(opts),
               selection_constraints: policy_selection_constraints(opts),
               rows: Enum.map(sweep_rows, &Map.drop(&1, [:metrics])),
               best: Map.drop(best, [:metrics])
             })
           ) do
      {:ok, report}
    else
      {:error, _reason} ->
        {:ok,
         skipped_report(
           profile,
           dataset,
           "Real local model policy sweep failed during execution.",
           opts
         )}
    end
  end

  defp threshold_sweep_rows(samples, profile, serving, opts) do
    opts
    |> thresholds()
    |> Enum.reduce_while({:ok, []}, fn threshold, {:ok, acc} ->
      per_entity_thresholds = %{
        person: threshold,
        location: threshold,
        organization: max(threshold, 0.85)
      }

      run_opts =
        opts
        |> Keyword.put(:ner_score_threshold, threshold)
        |> Keyword.put(:ner_per_entity_thresholds, per_entity_thresholds)

      case run_samples(samples, profile, serving, run_opts) do
        {:ok, results} ->
          metrics = score_results(results, profile, run_opts)

          row =
            metrics
            |> Map.take([
              :precision,
              :recall,
              :f1,
              :f2,
              :true_positives,
              :false_positives,
              :false_negatives,
              :offset_mismatches,
              :wrong_entity_type,
              :unsupported_expected_spans,
              :total_samples
            ])
            |> Map.put(:score_threshold, threshold)
            |> Map.put(:per_entity_thresholds, per_entity_thresholds)
            |> Map.put(:metrics, metrics)

          {:cont, {:ok, [row | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp label_threshold_sweep_rows(samples, profile, serving, opts) do
    opts
    |> label_threshold_candidates(profile, serving)
    |> Enum.reduce_while({:ok, []}, fn thresholds, {:ok, acc} ->
      run_opts = Keyword.put(opts, :ner_per_label_thresholds, thresholds)

      case run_samples(samples, profile, serving, run_opts) do
        {:ok, results} ->
          metrics = score_results(results, profile, run_opts)

          row =
            metrics
            |> metric_summary()
            |> Map.put(:score_threshold, Keyword.get(opts, :ner_score_threshold))
            |> Map.put(:per_label_thresholds, thresholds)
            |> Map.put(:metrics, metrics)

          {:cont, {:ok, [row | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp gliner_label_threshold_sweep_rows(samples, profile, serving, opts) do
    opts
    |> gliner_label_threshold_candidates(profile)
    |> Enum.reduce_while({:ok, []}, fn thresholds, {:ok, acc} ->
      run_opts = Keyword.put(opts, :gliner_per_label_thresholds, thresholds)

      case run_samples(samples, profile, serving, run_opts) do
        {:ok, results} ->
          metrics = score_results(results, profile, run_opts)

          row =
            metrics
            |> metric_summary()
            |> Map.put(:score_threshold, Keyword.get(opts, :gliner_threshold, 0.5))
            |> Map.put(:per_label_thresholds, thresholds)
            |> Map.put(:metrics, metrics)

          {:cont, {:ok, [row | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp policy_sweep_rows(samples, profile, serving, opts) do
    candidates = policy_candidates(opts, profile, serving)

    candidates
    |> Enum.reduce_while({:ok, []}, fn candidate, {:ok, acc} ->
      run_opts = merge_policy_candidate_opts(opts, candidate)

      case run_samples(samples, profile, serving, run_opts) do
        {:ok, results} ->
          metrics = score_results(results, profile, run_opts)

          row =
            metrics
            |> metric_summary()
            |> Map.merge(policy_candidate_summary(candidate))
            |> Map.put(:metrics, metrics)

          {:cont, {:ok, [row | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, rows |> Enum.reverse() |> policy_deltas()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp metric_summary(metrics) do
    metrics
    |> Map.take([
      :precision,
      :recall,
      :f1,
      :f2,
      :true_positives,
      :false_positives,
      :false_negatives,
      :offset_mismatches,
      :wrong_entity_type,
      :unsupported_expected_spans,
      :total_samples
    ])
    |> Map.put(:span_iou, span_iou_summary(metrics))
    |> Map.put(:latency, latency_summary(metrics))
    |> Map.put(:location, entity_summary(metrics, :location))
    |> Map.put(:organization, entity_summary(metrics, :organization))
    |> Map.put(:cascade, Map.get(metrics, :cascade))
    |> Map.put(:model_label_false_positives, model_label_false_positive_counts(metrics))
  end

  defp entity_summary(metrics, entity) do
    entity_metrics =
      metrics
      |> Map.get(:per_entity, %{})
      |> Map.get(entity, %{})

    Map.take(entity_metrics, [
      :precision,
      :recall,
      :f1,
      :f2,
      :true_positives,
      :false_positives,
      :false_negatives,
      :offset_mismatches,
      :wrong_entity_type,
      :support_count,
      :prediction_count
    ])
  end

  defp span_iou_summary(metrics) do
    metrics
    |> Map.get(:span_iou, %{})
    |> Map.take([
      :precision,
      :recall,
      :f1,
      :f2,
      :true_positives,
      :false_positives,
      :false_negatives,
      :wrong_entity_type
    ])
  end

  defp latency_summary(metrics) do
    metrics
    |> Map.get(:latency, %{})
    |> Map.take([:mean_ms, :p95_ms])
  end

  defp model_label_false_positive_counts(metrics) do
    false_positives =
      metrics
      |> Map.get(:model_label_errors, %{})
      |> Map.get(:false_positives, %{})

    Map.new(@model_label_fp_labels, fn label ->
      {label, false_positives |> Map.get(label, %{}) |> Map.get(:count, 0)}
    end)
  end

  @doc false
  def policy_deltas([]), do: []

  def policy_deltas(rows) do
    baseline = Enum.find(rows, &(&1.policy_name == :v18_train_selected)) || hd(rows)

    Enum.map(rows, fn row ->
      Map.put(row, :delta_from_baseline, policy_delta(row, baseline))
    end)
  end

  defp policy_delta(row, baseline) do
    %{
      global: %{
        precision: delta(row, baseline, :precision),
        recall: delta(row, baseline, :recall),
        f1: delta(row, baseline, :f1),
        f2: delta(row, baseline, :f2),
        true_positives: delta(row, baseline, :true_positives),
        false_positives: delta(row, baseline, :false_positives),
        false_negatives: delta(row, baseline, :false_negatives)
      },
      location: entity_delta(row, baseline, :location),
      organization: entity_delta(row, baseline, :organization),
      model_label_false_positives:
        Map.new(@model_label_fp_labels, fn label ->
          {label,
           (get_in(row, [:model_label_false_positives, label]) || 0) -
             (get_in(baseline, [:model_label_false_positives, label]) || 0)}
        end)
    }
  end

  defp entity_delta(row, baseline, entity) do
    %{
      precision: nested_delta(row, baseline, entity, :precision),
      recall: nested_delta(row, baseline, entity, :recall),
      f1: nested_delta(row, baseline, entity, :f1),
      true_positives: nested_delta(row, baseline, entity, :true_positives),
      false_positives: nested_delta(row, baseline, entity, :false_positives),
      false_negatives: nested_delta(row, baseline, entity, :false_negatives)
    }
  end

  defp delta(row, baseline, key) do
    numeric(row, key) - numeric(baseline, key)
  end

  defp nested_delta(row, baseline, parent, key) do
    numeric(Map.get(row, parent, %{}), key) - numeric(Map.get(baseline, parent, %{}), key)
  end

  defp numeric(map, key), do: Map.get(map, key) || 0

  @doc false
  def select_policy_row(rows, opts \\ []) when is_list(rows) do
    objective = policy_selection_objective(opts)
    candidates = constrained_policy_rows(rows, objective, opts)

    Enum.max_by(candidates, &policy_selection_key(&1, objective))
  end

  defp constrained_policy_rows(rows, :global_f1_under_fp_cap, opts) do
    cap = Keyword.get(opts, :policy_fp_cap) || :infinity

    filtered =
      Enum.filter(rows, fn row ->
        cap == :infinity or numeric(row, :false_positives) <= cap
      end)

    if filtered == [], do: rows, else: filtered
  end

  defp constrained_policy_rows(rows, :open_class_recall_under_global_f1_floor, opts) do
    floor = Keyword.get(opts, :policy_global_f1_floor, 0.0)

    filtered =
      Enum.filter(rows, fn row ->
        (Map.get(row, :f1) || 0.0) >= floor
      end)

    if filtered == [], do: rows, else: filtered
  end

  defp constrained_policy_rows(rows, _objective, _opts), do: rows

  defp policy_selection_key(row, :location_organization_recall) do
    {
      open_class_average_metric(row, :recall),
      open_class_count_metric(row, :true_positives),
      -open_class_count_metric(row, :false_negatives),
      -(Map.get(row, :false_positives) || 0),
      Map.get(row, :f1) || 0.0
    }
  end

  defp policy_selection_key(row, :location_organization_f1) do
    {
      open_class_average_metric(row, :f1),
      open_class_average_metric(row, :recall),
      -(Map.get(row, :false_positives) || 0),
      Map.get(row, :f1) || 0.0
    }
  end

  defp policy_selection_key(row, :organization_f1) do
    organization = Map.get(row, :organization, %{})

    {
      numeric(organization, :f1),
      numeric(organization, :recall),
      -numeric(organization, :false_positives),
      Map.get(row, :f1) || 0.0
    }
  end

  defp policy_selection_key(row, :location_f1) do
    location = Map.get(row, :location, %{})

    {
      numeric(location, :f1),
      numeric(location, :recall),
      -numeric(location, :false_positives),
      Map.get(row, :f1) || 0.0
    }
  end

  defp policy_selection_key(row, :global_f1_under_fp_cap) do
    {
      Map.get(row, :f1) || 0.0,
      Map.get(row, :recall) || 0.0,
      -(Map.get(row, :false_positives) || 0)
    }
  end

  defp policy_selection_key(row, :open_class_recall_under_global_f1_floor) do
    {
      open_class_average_metric(row, :recall),
      open_class_count_metric(row, :true_positives),
      -open_class_count_metric(row, :false_negatives),
      Map.get(row, :f1) || 0.0,
      -(Map.get(row, :false_positives) || 0)
    }
  end

  defp policy_selection_key(row, _objective),
    do: policy_selection_key(row, :global_f1_under_fp_cap)

  defp open_class_average_metric(row, key) do
    location = get_in(row, [:location, key]) || 0.0
    organization = get_in(row, [:organization, key]) || 0.0

    (location + organization) / 2
  end

  defp open_class_count_metric(row, key) do
    (get_in(row, [:location, key]) || 0) + (get_in(row, [:organization, key]) || 0)
  end

  defp policy_selection_objective(opts) do
    Keyword.get(opts, :policy_selection_objective, :global_f1_under_fp_cap)
  end

  defp policy_selection_constraints(opts) do
    %{
      fp_cap: Keyword.get(opts, :policy_fp_cap),
      global_f1_floor: Keyword.get(opts, :policy_global_f1_floor)
    }
  end

  @doc false
  def label_threshold_candidates(opts, profile, serving \\ nil) do
    base = base_label_thresholds(opts, profile, serving)
    values = Keyword.get(opts, :label_threshold_values) || default_label_threshold_values(profile)

    candidate_maps =
      [{:base, base}] ++
        Enum.flat_map(values, fn {label, label_values} ->
          Enum.map(label_values, fn value ->
            {label, Map.put(base, label, value)}
          end)
        end)

    candidate_maps
    |> Enum.map(fn {_label, thresholds} -> thresholds end)
    |> Enum.uniq()
  end

  @doc false
  def policy_candidates(opts, profile, serving \\ nil)

  def policy_candidates(opts, :hybrid_ner_tner_facebookai_org, _serving) do
    base_thresholds =
      opts
      |> base_label_thresholds(:hybrid_ner_tner_facebookai_org, nil)
      |> Map.merge(%{"PERSON" => 0.68, "GPE" => 0.9, "LOC" => 0.92, "FAC" => 0.97})

    base_policy = [
      ner_per_label_thresholds: Map.put(base_thresholds, "ORG", 0.98),
      ner_context_required_below_labels: %{"ORG" => 0.99},
      ner_context_words_by_label: %{"ORG" => @v21_org_context_words},
      ner_boundary_normalization: :none
    ]

    [
      policy_candidate(
        :facebookai_org_current,
        "Current FacebookAI organization-only policy used by the opt-in specialist profile.",
        base_policy
      ),
      policy_candidate(
        :facebookai_org_threshold_099,
        "Raise FacebookAI ORG threshold to reduce organization false positives.",
        Keyword.put(base_policy, :ner_per_label_thresholds, Map.put(base_thresholds, "ORG", 0.99))
      ),
      policy_candidate(
        :facebookai_org_threshold_0995,
        "Raise FacebookAI ORG threshold aggressively for precision-first organization detection.",
        Keyword.put(
          base_policy,
          :ner_per_label_thresholds,
          Map.put(base_thresholds, "ORG", 0.995)
        )
      ),
      policy_candidate(
        :facebookai_org_required_context_098,
        "Keep current ORG threshold but require organization context for every FacebookAI organization span.",
        Keyword.put(base_policy, :ner_context_required_labels, ["ORG"])
      ),
      policy_candidate(
        :facebookai_org_context_recall_096,
        "Lower FacebookAI ORG threshold only when organization context is required.",
        base_policy
        |> Keyword.put(:ner_per_label_thresholds, Map.put(base_thresholds, "ORG", 0.96))
        |> Keyword.put(:ner_context_required_labels, ["ORG"])
      ),
      policy_candidate(
        :facebookai_org_conflict_higher_confidence,
        "Resolve model overlaps by confidence to test whether overlapping FacebookAI organization spans should win only when they are more confident.",
        Keyword.put(base_policy, :conflict_strategy, :prefer_higher_confidence)
      ),
      policy_candidate(
        :facebookai_org_conflict_longer,
        "Resolve model overlaps by length to test whether longer TNER or FacebookAI spans reduce wrong-type overlap errors.",
        Keyword.put(base_policy, :conflict_strategy, :prefer_longer)
      )
    ]
  end

  def policy_candidates(_opts, :hybrid_ner_tner_jean_location, _serving) do
    [
      policy_candidate(
        :tner_jean_location_current,
        "TNER handles person/organization while Jean-Baptiste contributes only strict-threshold location spans.",
        []
      )
    ]
  end

  def policy_candidates(_opts, :hybrid_ner_tner_jean_location_cascade, _serving) do
    [
      policy_candidate(
        :cascade_disabled,
        "TNER-only control matching the balanced model policy.",
        cascade_trigger: :never,
        cascade_secondary_threshold: 0.995,
        cascade_context_policy: :none
      ),
      policy_candidate(
        :cascade_missing_0995,
        "Run Jean-Baptiste only when TNER returns no accepted location.",
        cascade_trigger: :missing,
        cascade_secondary_threshold: 0.995,
        cascade_context_policy: :none
      ),
      policy_candidate(
        :cascade_missing_0999,
        "Use a precision-first Jean-Baptiste threshold when TNER misses location.",
        cascade_trigger: :missing,
        cascade_secondary_threshold: 0.999,
        cascade_context_policy: :none
      ),
      policy_candidate(
        :cascade_missing_context_0995,
        "Require strong location context for Jean-Baptiste recovery spans.",
        cascade_trigger: :missing,
        cascade_secondary_threshold: 0.995,
        cascade_context_policy: :strong
      ),
      policy_candidate(
        :cascade_uncertain_context_0995,
        "Run on missing or uncertain TNER locations and retain contextual or overlapping Jean-Baptiste spans.",
        cascade_trigger: :missing_or_uncertain,
        cascade_uncertainty_threshold: 0.97,
        cascade_secondary_threshold: 0.995,
        cascade_context_policy: :strong_or_overlap
      ),
      policy_candidate(
        :cascade_always_context_0995,
        "Always compare Jean-Baptiste but retain only contextual or overlapping location spans.",
        cascade_trigger: :always,
        cascade_secondary_threshold: 0.995,
        cascade_context_policy: :strong_or_overlap
      )
    ]
  end

  def policy_candidates(opts, profile, serving) do
    base_thresholds =
      opts
      |> base_label_thresholds(profile, serving)
      |> Map.merge(@v18_tner_label_thresholds)

    base_policy = [
      ner_per_label_thresholds: base_thresholds,
      ner_context_required_below_labels: @v18_tner_context_gates,
      ner_context_required_labels: @v18_tner_context_required_labels,
      ner_negative_context_words_by_label: @v18_tner_negative_context_words,
      ner_negative_context_reject_labels: @v18_tner_negative_context_reject_labels,
      ner_boundary_normalization: :none
    ]

    [
      policy_candidate(
        :v18_train_selected,
        "V18 train-selected TNER policy used as the baseline.",
        base_policy
      ),
      policy_candidate(
        :org_context_recall,
        "Lower ORG only when context gating can reject weaker organization spans.",
        Keyword.merge(base_policy,
          ner_per_label_thresholds: Map.put(base_thresholds, "ORG", 0.96),
          ner_context_required_below_labels: Map.merge(@v18_tner_context_gates, %{"ORG" => 0.99}),
          ner_context_words_by_label: %{"ORG" => @v21_org_context_words}
        )
      ),
      policy_candidate(
        :gpe_negative_context_extended,
        "Keep GPE threshold conservative but reject more account/reference-like GPE false positives.",
        Keyword.merge(base_policy,
          ner_negative_context_words_by_label: %{
            "GPE" => @v21_extended_gpe_negative_context
          },
          ner_negative_context_reject_labels: ["GPE"]
        )
      ),
      policy_candidate(
        :loc_context_recall,
        "Lower LOC with a stronger label-specific context gate for location recall.",
        Keyword.merge(base_policy,
          ner_per_label_thresholds: Map.put(base_thresholds, "LOC", 0.88),
          ner_context_required_below_labels: Map.merge(@v18_tner_context_gates, %{"LOC" => 0.96}),
          ner_context_words_by_label: %{"LOC" => @v21_loc_context_words}
        )
      ),
      policy_candidate(
        :fac_required_context_balanced,
        "Lower FAC while continuing to require strong facility context.",
        Keyword.merge(base_policy,
          ner_per_label_thresholds: Map.put(base_thresholds, "FAC", 0.92),
          ner_context_required_labels: ["FAC"],
          ner_context_required_below_labels: Map.merge(@v18_tner_context_gates, %{"FAC" => 0.99}),
          ner_context_words_by_label: %{"FAC" => @v21_fac_context_words},
          ner_weak_context_words_by_label: %{"FAC" => ["in"]}
        )
      ),
      policy_candidate(
        :boundary_conservative,
        "Enable conservative model boundary normalization to test exact-span improvement.",
        Keyword.merge(base_policy, ner_boundary_normalization: :conservative)
      ),
      policy_candidate(
        :organization_suffix_expansion,
        "Expand model-predicted organization spans through approved organization suffix tokens.",
        Keyword.merge(base_policy,
          ner_model_postprocessors: [:organization_suffix_expansion]
        )
      ),
      policy_candidate(
        :location_suffix_expansion,
        "Expand model-predicted location/facility spans through approved location suffix tokens.",
        Keyword.merge(base_policy,
          ner_model_postprocessors: [:location_suffix_expansion]
        )
      ),
      policy_candidate(
        :open_class_suffix_expansion,
        "Expand model-predicted organization and location spans through approved suffix tokens.",
        Keyword.merge(base_policy,
          ner_model_postprocessors: [
            :organization_suffix_expansion,
            :location_suffix_expansion
          ]
        )
      ),
      policy_candidate(
        :presidio_character_chunking,
        "Run real local NER with Presidio-style character chunks and overlap, then recombine byte offsets.",
        Keyword.merge(base_policy,
          ner_model_chunking: :character,
          ner_model_chunk_size: 400,
          ner_model_chunk_overlap: 40
        )
      ),
      policy_candidate(
        :guarded_high_recall,
        "Opt-in high-recall candidate guarded by context and extended negative GPE filtering.",
        Keyword.merge(base_policy,
          ner_per_label_thresholds: %{
            "PERSON" => 0.68,
            "ORG" => 0.95,
            "GPE" => 0.86,
            "LOC" => 0.88,
            "FAC" => 0.92
          },
          ner_context_required_below_labels: %{"ORG" => 0.99, "LOC" => 0.96, "FAC" => 0.99},
          ner_context_required_labels: ["FAC"],
          ner_context_words_by_label: %{
            "ORG" => @v21_org_context_words,
            "LOC" => @v21_loc_context_words,
            "FAC" => @v21_fac_context_words
          },
          ner_weak_context_words_by_label: %{"FAC" => ["in"]},
          ner_negative_context_words_by_label: %{
            "GPE" => @v21_extended_gpe_negative_context
          },
          ner_negative_context_reject_labels: ["GPE"]
        )
      )
    ]
  end

  defp policy_candidate(name, description, opts) do
    %{name: name, description: description, opts: opts}
  end

  defp merge_policy_candidate_opts(opts, %{opts: candidate_opts}) do
    policy_candidate_opts(opts, %{opts: candidate_opts})
  end

  @doc false
  def policy_candidate_opts(opts, %{opts: candidate_opts}) do
    Keyword.merge(opts, candidate_opts)
  end

  defp policy_candidate_summary(%{name: name, description: description, opts: opts}) do
    %{
      policy_name: name,
      policy_description: description,
      per_label_thresholds: Keyword.get(opts, :ner_per_label_thresholds, %{}),
      context_required_below_labels: Keyword.get(opts, :ner_context_required_below_labels, %{}),
      context_required_labels: Keyword.get(opts, :ner_context_required_labels, []),
      context_words_by_label: Keyword.get(opts, :ner_context_words_by_label, %{}),
      weak_context_words_by_label: Keyword.get(opts, :ner_weak_context_words_by_label, %{}),
      negative_context_words_by_label:
        Keyword.get(opts, :ner_negative_context_words_by_label, %{}),
      negative_context_reject_labels: Keyword.get(opts, :ner_negative_context_reject_labels, []),
      conflict_strategy: Keyword.get(opts, :conflict_strategy, :default),
      boundary_normalization: Keyword.get(opts, :ner_boundary_normalization, :none),
      model_postprocessors: Keyword.get(opts, :ner_model_postprocessors, []),
      model_chunking: Keyword.get(opts, :ner_model_chunking, :none),
      model_chunk_size: Keyword.get(opts, :ner_model_chunk_size, 400),
      model_chunk_overlap: Keyword.get(opts, :ner_model_chunk_overlap, 40),
      cascade_trigger: Keyword.get(opts, :cascade_trigger),
      cascade_context_policy: Keyword.get(opts, :cascade_context_policy),
      cascade_uncertainty_threshold: Keyword.get(opts, :cascade_uncertainty_threshold),
      cascade_secondary_threshold: Keyword.get(opts, :cascade_secondary_threshold)
    }
  end

  defp thresholds(opts) do
    opts
    |> Keyword.get(:thresholds, @default_thresholds)
    |> Enum.map(&(&1 / 1))
  end

  defp best_threshold_row(rows) do
    Enum.max_by(rows, fn row ->
      {
        Map.get(row, :f1) || -1.0,
        Map.get(row, :recall) || -1.0,
        Map.get(row, :precision) || -1.0
      }
    end)
  end

  defp best_threshold_row(rows, opts) do
    case Keyword.get(opts, :policy_selection_objective) do
      nil -> best_threshold_row(rows)
      _objective -> select_policy_row(rows, opts)
    end
  end

  defp best_gliner_threshold_row(rows, opts) do
    case Keyword.get(opts, :policy_selection_objective) do
      nil -> best_threshold_row(rows)
      _objective -> select_policy_row(rows, opts)
    end
  end

  defp samples(all_samples, profile, opts) do
    case Keyword.get(opts, :sample_ids) do
      sample_ids when is_list(sample_ids) ->
        filter_sample_ids(all_samples, sample_ids)

      _none ->
        if Keyword.get(opts, :full, false) do
          all_samples
        else
          limit = Keyword.get(opts, :limit, @default_limit)
          PresidioResearchLoader.smoke_subset(all_samples, profile, limit)
        end
    end
  end

  defp filter_sample_ids(samples, sample_ids) do
    wanted = MapSet.new(sample_ids)

    Enum.filter(samples, fn sample ->
      sample.id in wanted or to_string(sample.id) in wanted
    end)
  end

  defp requested_entities(profile, opts) do
    supported = Profile.supported_entities(profile)

    case Keyword.get(opts, :entities) do
      nil ->
        supported

      entities when is_list(entities) ->
        Enum.filter(entities, &(&1 in supported))
    end
  end

  defp metrics_opts(profile, opts) do
    case Keyword.get(opts, :entities) do
      nil -> []
      _entities -> [supported_entities: requested_entities(profile, opts)]
    end
  end

  defp score_results(results, profile, opts) do
    results
    |> Metrics.score_results(profile, metrics_opts(profile, opts))
    |> maybe_put_cascade_metrics(results, profile)
  end

  defp maybe_put_cascade_metrics(metrics, results, :hybrid_ner_tner_jean_location_cascade) do
    events = results |> Enum.map(&Map.get(&1, :cascade_event)) |> Enum.reject(&is_nil/1)
    total = length(events)
    run_count = Enum.count(events, & &1.secondary_run)

    summary = %{
      total_samples: total,
      secondary_run_count: run_count,
      secondary_skip_count: total - run_count,
      secondary_run_rate: ratio(run_count, total),
      secondary_skip_rate: ratio(total - run_count, total),
      secondary_proposed_count: Enum.reduce(events, 0, &(&1.secondary_proposed_count + &2)),
      secondary_accepted_count: Enum.reduce(events, 0, &(&1.secondary_accepted_count + &2)),
      trigger_reasons: events |> Enum.map(& &1.trigger_reason) |> Enum.frequencies()
    }

    Map.put(metrics, :cascade, summary)
  end

  defp maybe_put_cascade_metrics(metrics, _results, _profile), do: metrics

  defp ratio(_count, 0), do: 0.0
  defp ratio(count, total), do: count / total

  defp run_samples(samples, profile, serving, opts) do
    samples
    |> Enum.reduce_while({:ok, []}, fn sample, {:ok, acc} ->
      start = System.monotonic_time()
      {run_opts, timing_ref} = privacy_filter_timing_opts(profile, opts)
      {run_opts, cascade_ref} = cascade_observer_opts(profile, run_opts)

      case ObscuraAnalyzerAdapter.analyze(
             sample.text,
             analyzer_opts(sample, profile, serving, run_opts)
           ) do
        {:ok, predictions} ->
          result = %{
            sample: sample,
            expected: Enum.map(sample.spans, &tag_span(&1, sample, :expected)),
            predicted: Enum.map(predictions, &tag_span(&1, sample, :predicted)),
            latency_ms: elapsed_ms(start),
            stage_latency_ms: receive_privacy_filter_timings(timing_ref),
            cascade_event: receive_cascade_event(cascade_ref)
          }

          {:cont, {:ok, [result | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp privacy_filter_timing_opts(profile, opts) when profile in @privacy_filter_profiles do
    ref = make_ref()

    {
      opts
      |> Keyword.put(:privacy_filter_timing_ref, ref)
      |> Keyword.put(:privacy_filter_timing_recipient, self()),
      ref
    }
  end

  defp privacy_filter_timing_opts(_profile, opts), do: {opts, nil}

  defp cascade_observer_opts(:hybrid_ner_tner_jean_location_cascade, opts) do
    ref = make_ref()
    {Keyword.put(opts, :cascade_observer, {self(), ref}), ref}
  end

  defp cascade_observer_opts(_profile, opts), do: {opts, nil}

  defp receive_privacy_filter_timings(nil), do: nil

  defp receive_privacy_filter_timings(ref) do
    receive do
      {:privacy_filter_serving_timings, ^ref, timings} -> timings
    after
      0 -> nil
    end
  end

  defp receive_cascade_event(nil), do: nil

  defp receive_cascade_event(ref) do
    receive do
      {:ner_output_aware_cascade, ^ref, event} -> event
    after
      1_000 -> nil
    end
  end

  defp tag_span(span, sample, kind) do
    metadata =
      span
      |> Map.get(:metadata, %{})
      |> Kernel.||(%{})
      |> Map.merge(%{
        sample_id: sample.id,
        template_id: sample.template_id,
        source: sample.source,
        benchmark_kind: kind
      })

    Map.put(span, :metadata, metadata)
  end

  defp analyzer_opts(_sample, :real_ner, serving, opts) do
    [
      profile: :real_ner,
      entities: requested_entities(:real_ner, opts),
      recognizers: [{NER, real_ner_opts(serving, opts)}],
      nlp_engine: {BumblebeeEngine, serving: serving},
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 60_000),
      include_text: false
    ]
  end

  defp analyzer_opts(_sample, profile, serving, opts)
       when profile in [
              :hybrid_ner,
              :hybrid_ner_conservative,
              :hybrid_ner_balanced,
              :hybrid_ner_org,
              :hybrid_ner_org_high_recall,
              :hybrid_ner_dbmdz_conservative,
              :hybrid_ner_tner_conservative,
              :hybrid_ner_tner_high_recall,
              :hybrid_ner_bigmed_conservative
            ] do
    [
      profile: profile,
      entities: requested_entities(profile, opts),
      recognizers: [
        :default,
        {NER, hybrid_ner_opts(profile, serving, opts)}
      ],
      nlp_engine: {BumblebeeEngine, serving: serving},
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 60_000),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, :hybrid_ner_tner_facebookai_org, serving, opts) do
    [
      profile: :hybrid_ner_tner_facebookai_org,
      entities: requested_entities(:hybrid_ner_tner_facebookai_org, opts),
      recognizers: [
        :default,
        {NER, tner_primary_opts(serving.primary, opts)},
        {SecondaryNER, facebookai_organization_opts(serving.organization, opts)}
      ],
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      parallel_recognizers: Keyword.get(opts, :parallel_recognizers, false),
      conflict_strategy: Keyword.get(opts, :conflict_strategy, :default),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, :hybrid_ner_tner_jean_location, serving, opts) do
    entities = requested_entities(:hybrid_ner_tner_jean_location, opts)

    [
      profile: :hybrid_ner_tner_jean_location,
      entities: entities,
      recognizers:
        Routing.tner_jean_recognizers(
          entities,
          maybe_tner_person_organization_opts(serving, opts),
          maybe_jean_baptiste_location_opts(serving, opts)
        ),
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      conflict_strategy: Keyword.get(opts, :conflict_strategy, :default),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, :hybrid_ner_tner_jean_location_gated, serving, opts) do
    entities = requested_entities(:hybrid_ner_tner_jean_location_gated, opts)

    [
      profile: :hybrid_ner_tner_jean_location_gated,
      entities: entities,
      recognizers:
        Routing.tner_jean_recognizers(
          entities,
          maybe_tner_person_organization_opts(serving, opts),
          maybe_gated_jean_baptiste_location_opts(serving, opts)
        ),
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      conflict_strategy: Keyword.get(opts, :conflict_strategy, :default),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, :hybrid_ner_tner_jean_location_cascade, serving, opts) do
    opts = Keyword.put_new(opts, :cascade_secondary_threshold, 0.999)
    entities = requested_entities(:hybrid_ner_tner_jean_location_cascade, opts)

    [
      profile: :hybrid_ner_tner_jean_location_cascade,
      entities: entities,
      recognizers:
        Routing.tner_jean_cascade_recognizers(
          entities,
          maybe_tner_cascade_primary_opts(serving, opts),
          maybe_jean_baptiste_location_opts(serving, opts),
          cascade_opts(opts)
        ),
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      conflict_strategy: Keyword.get(opts, :conflict_strategy, :default),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(sample, :nlp, _serving, _opts) do
    [
      profile: :nlp,
      entities: Profile.supported_entities(:nlp),
      recognizers: [
        :default,
        {NER, serving: FakeServing.new(%{sample.text => ModelOutputs.from_sample(sample)})}
      ]
    ]
  end

  defp analyzer_opts(_sample, :gliner_ortex, serving, opts) do
    [
      profile: :gliner_ortex,
      entities: requested_entities(:gliner_ortex, opts),
      built_ins: false,
      recognizers: [{GLiNER, gliner_opts(serving, opts)}],
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      include_text: false,
      conflict_strategy: :none
    ]
  end

  defp analyzer_opts(_sample, :hybrid_gliner_ortex, serving, opts) do
    [
      profile: :hybrid_gliner_ortex,
      entities: requested_entities(:hybrid_gliner_ortex, opts),
      recognizers: [
        :default,
        {GLiNER, hybrid_gliner_opts(serving, opts)}
      ],
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, :hybrid_gliner_urchade, serving, opts) do
    opts =
      opts
      |> Keyword.put_new(:gliner_model, :urchade_gliner_multi_pii_v1)
      |> Keyword.put_new(:gliner_label_profile, :open_class)
      |> Keyword.put_new(:gliner_per_label_thresholds, @urchade_train_selected_thresholds)

    [
      profile: :hybrid_gliner_urchade,
      entities: requested_entities(:hybrid_gliner_urchade, opts),
      recognizers: [
        :default,
        {GLiNER, hybrid_gliner_opts(serving, opts)}
      ],
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, :hybrid_gliner_urchade_native, serving, opts) do
    opts =
      opts
      |> Keyword.put_new(:gliner_model, :urchade_gliner_multi_pii_v1)
      |> Keyword.put_new(:gliner_label_profile, :open_class)
      |> Keyword.put_new(:gliner_per_label_thresholds, @urchade_train_selected_thresholds)

    [
      profile: :hybrid_gliner_urchade_native,
      entities: requested_entities(:hybrid_gliner_urchade_native, opts),
      recognizers: [
        :default,
        {GLiNER, hybrid_gliner_opts(serving, opts)}
      ],
      recognizer_timeout: Keyword.get(opts, :recognizer_timeout, 120_000),
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, :privacy_filter_native, serving, opts) do
    [
      profile: :privacy_filter_native,
      entities: requested_entities(:privacy_filter_native, opts),
      built_ins: false,
      recognizers: [{PrivacyFilterNative, privacy_filter_recognizer_opts(serving, opts)}],
      recognizer_timeout: 300_000,
      include_text: false,
      conflict_strategy: :none
    ]
  end

  defp analyzer_opts(_sample, :hybrid_privacy_filter_native, serving, opts) do
    [
      profile: :hybrid_privacy_filter_native,
      entities: requested_entities(:hybrid_privacy_filter_native, opts),
      recognizers: [
        :default,
        {PrivacyFilterNative, privacy_filter_recognizer_opts(serving, opts)}
      ],
      recognizer_timeout: 300_000,
      include_text: false
    ]
    |> Keyword.merge(phone_opts(opts))
  end

  defp analyzer_opts(_sample, profile, _serving, opts) do
    [profile: profile, entities: requested_entities(profile, opts)]
    |> Keyword.merge(phone_opts(opts))
  end

  defp serving(:hybrid_ner_tner_facebookai_org, opts) do
    with {:ok, primary} <-
           opts
           |> Keyword.put(:model, :tner_roberta_large_ontonotes5)
           |> Keyword.put_new(:compile, batch_size: 1, sequence_length: 128)
           |> Serving.build(),
         {:ok, organization} <-
           opts
           |> Keyword.put(:model, :facebook_xlm_roberta_large_conll03_english)
           |> Keyword.put_new(:compile, batch_size: 1, sequence_length: 128)
           |> Serving.build() do
      {:ok, %{primary: primary, organization: organization}}
    end
  end

  defp serving(profile, opts)
       when profile in [
              :hybrid_ner_tner_jean_location,
              :hybrid_ner_tner_jean_location_gated,
              :hybrid_ner_tner_jean_location_cascade
            ] do
    needs =
      profile
      |> requested_entities(opts)
      |> tner_jean_serving_needs(profile)

    with {:ok, primary} <- maybe_build_tner_primary_serving(needs.primary, opts),
         {:ok, location} <- maybe_build_jean_location_serving(needs.location, opts) do
      {:ok, %{primary: primary, location: location}}
    end
  end

  defp serving(profile, opts) when profile in @real_model_profiles do
    opts
    |> Keyword.put_new(:compile, batch_size: 1, sequence_length: 128)
    |> Serving.build()
  end

  defp serving(profile, opts) when profile in @gliner_ortex_profiles do
    opts
    |> gliner_serving_opts(profile)
    |> GLiNEROrtex.build()
  end

  defp serving(profile, opts) when profile in @gliner_native_profiles do
    opts
    |> gliner_serving_opts(profile)
    |> GLiNERNative.build()
  end

  defp serving(profile, opts) when profile in @privacy_filter_profiles do
    opts
    |> privacy_filter_serving_opts()
    |> PrivacyFilterServing.build()
  end

  defp serving(_profile, _opts), do: {:ok, nil}

  defp maybe_build_tner_primary_serving(false, _opts), do: {:ok, nil}

  defp maybe_build_tner_primary_serving(true, opts) do
    opts
    |> Keyword.put(:model, :tner_roberta_large_ontonotes5)
    |> Keyword.put_new(:compile, batch_size: 1, sequence_length: 128)
    |> Serving.build()
  end

  defp tner_jean_serving_needs(entities, :hybrid_ner_tner_jean_location_cascade),
    do: Routing.tner_jean_cascade_serving_needs(entities)

  defp tner_jean_serving_needs(entities, _profile),
    do: Routing.tner_jean_serving_needs(entities)

  defp maybe_build_jean_location_serving(false, _opts), do: {:ok, nil}

  defp maybe_build_jean_location_serving(true, opts) do
    opts
    |> Keyword.put(:model, :jean_baptiste_roberta_large_ner_english)
    |> Keyword.put_new(:compile, batch_size: 1, sequence_length: 128)
    |> Serving.build()
  end

  defp maybe_tner_person_organization_opts(%{primary: nil}, _opts), do: nil

  defp maybe_tner_person_organization_opts(%{primary: primary}, opts),
    do: tner_person_organization_opts(primary, opts)

  defp maybe_tner_cascade_primary_opts(%{primary: nil}, _opts), do: nil

  defp maybe_tner_cascade_primary_opts(%{primary: primary}, opts),
    do: tner_cascade_primary_opts(primary, opts)

  defp maybe_jean_baptiste_location_opts(%{location: nil}, _opts), do: nil

  defp maybe_jean_baptiste_location_opts(%{location: location}, opts),
    do: jean_baptiste_location_opts(location, opts)

  defp maybe_gated_jean_baptiste_location_opts(%{location: nil}, _opts), do: nil

  defp maybe_gated_jean_baptiste_location_opts(%{location: location}, opts),
    do: gated_jean_baptiste_location_opts(location, opts)

  defp privacy_filter_recognizer_opts(serving, opts) do
    [
      serving: serving,
      timing_ref: Keyword.get(opts, :privacy_filter_timing_ref),
      timing_recipient: Keyword.get(opts, :privacy_filter_timing_recipient)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp privacy_filter_serving_opts(opts) do
    [
      checkpoint: privacy_filter_checkpoint(opts),
      pad_windows: Keyword.get(opts, :privacy_filter_pad_windows, false),
      trim_span_whitespace: true,
      discard_overlapping_spans: true
    ]
    |> Keyword.merge(OpenMedPolicy.effective_options(opts))
    |> maybe_put_privacy_filter_n_ctx(opts)
    |> maybe_put_privacy_filter_backend(opts)
    |> maybe_put_privacy_filter_label_map(opts)
    |> maybe_put_privacy_filter_min_span_logprob(opts)
  end

  defp maybe_put_privacy_filter_dataset_policy(opts, loaded, profile)
       when profile in @privacy_filter_profiles do
    label_map_mode = privacy_filter_label_map_mode(opts)
    opts = Keyword.put(opts, :privacy_filter_label_map_mode, label_map_mode)

    case label_map_mode do
      :presidio_research ->
        Keyword.put(opts, :privacy_filter_label_map, PrivacyFilterLabelMap.presidio_research())

      :supported ->
        supported_entities = mapped_supported_entities(loaded)

        Keyword.put(
          opts,
          :privacy_filter_label_map,
          PrivacyFilterLabelMap.for_entities(
            supported_entities,
            PrivacyFilterLabelMap.presidio_research()
          )
        )

      _default ->
        opts
    end
  end

  defp maybe_put_privacy_filter_dataset_policy(opts, _loaded, _profile), do: opts

  defp mapped_supported_entities(loaded) do
    loaded
    |> Map.get(:supported_entity_counts, %{})
    |> Map.keys()
    |> Enum.flat_map(&mapped_entity/1)
    |> Enum.uniq()
  end

  defp mapped_entity(source_entity) do
    case EntityMapping.to_obscura(source_entity) do
      {:ok, entity} -> [entity]
      {:error, _reason} -> []
    end
  end

  defp maybe_put_privacy_filter_n_ctx(serving_opts, opts) do
    case Keyword.fetch(opts, :privacy_filter_n_ctx) do
      {:ok, n_ctx} -> Keyword.put(serving_opts, :n_ctx, n_ctx)
      :error -> serving_opts
    end
  end

  defp maybe_put_privacy_filter_backend(serving_opts, opts) do
    case Keyword.fetch(opts, :real_model_backend) do
      {:ok, backend} -> Keyword.put(serving_opts, :backend, backend)
      :error -> serving_opts
    end
  end

  defp maybe_put_privacy_filter_label_map(serving_opts, opts) do
    case Keyword.fetch(opts, :privacy_filter_label_map) do
      {:ok, label_map} -> Keyword.put(serving_opts, :label_map, label_map)
      :error -> serving_opts
    end
  end

  defp maybe_put_privacy_filter_min_span_logprob(serving_opts, opts) do
    case Keyword.fetch(opts, :privacy_filter_min_span_logprob) do
      {:ok, min_span_logprob} -> Keyword.put(serving_opts, :min_span_logprob, min_span_logprob)
      :error -> serving_opts
    end
  end

  defp gliner_opts(serving, opts) do
    [
      serving: serving,
      model: Keyword.get(opts, :gliner_model, :knowledgator_gliner_pii_base_v1),
      label_profile: Keyword.get(opts, :gliner_label_profile, :hybrid_core),
      threshold: Keyword.get(opts, :gliner_threshold, 0.5),
      per_label_thresholds: Keyword.get(opts, :gliner_per_label_thresholds, %{}),
      flat_ner: Keyword.get(opts, :gliner_flat_ner, true),
      multi_label: Keyword.get(opts, :gliner_multi_label, false)
    ]
  end

  defp hybrid_gliner_opts(serving, opts) do
    label_profile = Keyword.get(opts, :gliner_label_profile, :open_class)

    opts =
      opts
      |> Keyword.put_new(:gliner_label_profile, :open_class)
      |> Keyword.put_new(
        :gliner_per_label_thresholds,
        default_hybrid_gliner_thresholds(label_profile, opts)
      )

    gliner_opts(serving, opts)
  end

  defp gliner_serving_opts(opts, profile) do
    model =
      Keyword.get_lazy(opts, :gliner_model, fn ->
        if profile in [:hybrid_gliner_urchade, :hybrid_gliner_urchade_native],
          do: :urchade_gliner_multi_pii_v1,
          else: :knowledgator_gliner_pii_base_v1
      end)

    Keyword.put(opts, :model, model)
  end

  defp gliner_label_profile(profile, opts)
       when profile in [
              :hybrid_gliner_ortex,
              :hybrid_gliner_urchade,
              :hybrid_gliner_urchade_native
            ],
       do: Keyword.get(opts, :gliner_label_profile, :open_class)

  defp gliner_label_profile(_profile, opts),
    do: Keyword.get(opts, :gliner_label_profile, :hybrid_core)

  defp gliner_per_label_thresholds(profile, opts)
       when profile in [
              :hybrid_gliner_ortex,
              :hybrid_gliner_urchade,
              :hybrid_gliner_urchade_native
            ] do
    opts
    |> selected_gliner_thresholds()
    |> normalize_gliner_thresholds()
  end

  defp gliner_per_label_thresholds(_profile, opts),
    do: Keyword.get(opts, :gliner_per_label_thresholds, %{})

  defp selected_gliner_thresholds(opts) do
    case Keyword.get(opts, :threshold_sweep_data) do
      %{best: %{per_label_thresholds: thresholds}} ->
        thresholds

      _none ->
        Keyword.get(opts, :gliner_per_label_thresholds, default_gliner_thresholds(opts))
    end
  end

  defp build_report(dataset, samples, metrics, profile, opts) do
    scope = scope(opts)

    report =
      Report.build(
        run_id: run_id(dataset.name, profile, scope, opts),
        phase: "presidio_compatibility",
        adapter: adapter_name(profile),
        profile: profile,
        dataset: %{
          name: dataset.name,
          source: dataset.source,
          version: dataset.version,
          sample_count: length(samples),
          sample_ids: Enum.map(samples, & &1.id),
          full_sample_count: dataset.sample_count,
          original_sample_count: Map.get(dataset, :original_sample_count, dataset.sample_count),
          invalid_sample_count: Map.get(dataset, :invalid_sample_count, 0),
          entity_counts: Map.get(dataset, :entity_counts, %{}),
          supported_entity_counts: Map.get(dataset, :supported_entity_counts, %{}),
          unsupported_entity_counts: Map.get(dataset, :unsupported_entity_counts, %{}),
          requested_entities: requested_entities(profile, opts),
          template_split: Map.get(dataset, :template_split),
          template_summary: template_summary(samples),
          smoke: not Keyword.get(opts, :full, false),
          scope: Atom.to_string(scope)
        },
        offset_mode: %{
          input: "character",
          internal: "byte",
          scoring: "byte",
          conversion: "validated"
        },
        metrics: metrics,
        threshold_sweep: Keyword.get(opts, :threshold_sweep_data),
        limitations: limitations(profile, scope)
      )

    report
    |> put_profile_identity(profile, opts)
    |> maybe_put_model(profile, opts)
    |> maybe_put_secondary_gate(samples, profile)
  end

  defp put_profile_identity(report, profile, opts) do
    report
    |> Map.put(
      :requested_profile,
      opts |> Keyword.get(:requested_profile, profile) |> to_string()
    )
    |> Map.put(:resolved_profile, to_string(profile))
  end

  defp template_summary(samples) do
    template_ids =
      samples
      |> Enum.map(&Map.get(&1, :template_id))
      |> Enum.reject(&is_nil/1)

    %{
      template_count: template_ids |> MapSet.new() |> MapSet.size(),
      sample_count_by_template:
        template_ids
        |> Enum.frequencies()
        |> Enum.sort_by(fn {template_id, _count} -> template_id end)
        |> Enum.take(25)
        |> Map.new()
    }
  end

  defp maybe_put_model(report, profile, opts) when profile in @real_model_profiles do
    model_metadata = real_profile_model_metadata(profile, opts)

    report
    |> Map.put(:model, model_metadata)
    |> Map.put(:runtime_backend, Backend.metadata(opts))
  end

  defp maybe_put_model(report, profile, opts) when profile in @gliner_ortex_profiles do
    model = Keyword.get(opts, :gliner_model, :knowledgator_gliner_pii_base_v1)

    model_metadata =
      case GLiNERModelRegistry.metadata(model) do
        {:ok, metadata} -> metadata
        {:error, _reason} -> %{model_alias: model}
      end

    report
    |> Map.put(:model, model_metadata)
    |> Map.put(:runtime_backend, %{
      adapter: :ortex,
      execution_providers: Keyword.get(opts, :execution_providers, [:cpu]),
      opt_in_env: "OBSCURA_GLINER_ORTEX"
    })
    |> Map.put(:gliner, %{
      label_profile: gliner_label_profile(profile, opts),
      onnx_variant:
        Keyword.get(
          opts,
          :onnx_variant,
          System.get_env("OBSCURA_GLINER_ONNX_VARIANT", "full")
        ),
      threshold: Keyword.get(opts, :gliner_threshold, 0.5),
      per_label_thresholds: gliner_per_label_thresholds(profile, opts)
    })
  end

  defp maybe_put_model(report, profile, opts) when profile in @gliner_native_profiles do
    model = Keyword.get(opts, :gliner_model, :urchade_gliner_multi_pii_v1)
    serving = Keyword.get(opts, :runtime_serving)

    model_metadata =
      case GLiNERModelRegistry.metadata(model) do
        {:ok, metadata} -> metadata
        {:error, _reason} -> %{model_alias: model}
      end

    report
    |> Map.put(:model, model_metadata)
    |> Map.put(:runtime_backend, %{
      adapter: :native_nx_emily,
      device: :gpu,
      native: true,
      fallback: :raise,
      serving_metadata: if(serving, do: serving.metadata, else: %{}),
      opt_in_env: "OBSCURA_GLINER_NATIVE"
    })
    |> Map.put(:gliner, %{
      label_profile: gliner_label_profile(profile, opts),
      threshold: Keyword.get(opts, :gliner_threshold, 0.5),
      per_label_thresholds: gliner_per_label_thresholds(profile, opts)
    })
  end

  defp maybe_put_model(report, profile, opts) when profile in @privacy_filter_profiles do
    serving = Keyword.get(opts, :runtime_serving)

    report
    |> Map.put(:model, %{
      model_id: privacy_filter_model_id(opts),
      architecture: "OpenAIPrivacyFilterForTokenClassification",
      checkpoint: privacy_filter_checkpoint(opts),
      profile: profile,
      n_ctx: privacy_filter_report_n_ctx(opts),
      pad_windows: Keyword.get(opts, :privacy_filter_pad_windows, false),
      decoder: Keyword.get(opts, :privacy_filter_decoder, :viterbi),
      backend: Keyword.get(opts, :real_model_backend, :default),
      label_map_mode: privacy_filter_label_map_mode(opts),
      min_span_logprob: Keyword.get(opts, :privacy_filter_min_span_logprob),
      optimization_policy: privacy_filter_optimization_policy(serving)
    })
    |> Map.put(:recognizer_execution, privacy_filter_recognizer_execution(profile))
    |> Map.put(:runtime_backend, %{
      adapter: :native_privacy_filter,
      serving_backend: privacy_filter_serving_backend(serving),
      serving_backend_metadata: privacy_filter_serving_backend_metadata(serving),
      opt_in_env: "OBSCURA_EVAL_PRIVACY_FILTER_NATIVE",
      checkpoint_env: "OBSCURA_PRIVACY_FILTER_CHECKPOINT",
      model_id_env: "OBSCURA_PRIVACY_FILTER_MODEL_ID"
    })
  end

  defp maybe_put_model(report, _profile, _opts), do: report

  defp privacy_filter_label_map_mode(opts),
    do: Keyword.get(opts, :privacy_filter_label_map_mode, :presidio_research)

  defp privacy_filter_recognizer_execution(:privacy_filter_native) do
    %{
      built_ins: false,
      recognizers: ["Obscura.Recognizer.PrivacyFilter.Native"],
      mode: :custom_recognizers_only
    }
  end

  defp privacy_filter_recognizer_execution(:hybrid_privacy_filter_native) do
    %{
      built_ins: true,
      recognizers: [":default", "Obscura.Recognizer.PrivacyFilter.Native"],
      mode: :built_ins_plus_privacy_filter_native
    }
  end

  defp privacy_filter_serving_backend(%PrivacyFilterServing{} = serving), do: serving.backend
  defp privacy_filter_serving_backend(_serving), do: nil

  defp privacy_filter_serving_backend_metadata(%PrivacyFilterServing{} = serving),
    do: serving.backend_metadata

  defp privacy_filter_serving_backend_metadata(_serving), do: %{}

  defp privacy_filter_optimization_policy(%PrivacyFilterServing{} = serving),
    do: OpenMedPolicy.metadata(serving)

  defp privacy_filter_optimization_policy(_serving), do: OpenMedPolicy.default_metadata()

  @doc false
  @spec output_fingerprint([map()]) :: String.t()
  def output_fingerprint(results) do
    results
    |> Enum.flat_map(fn result ->
      Enum.map(result.predicted, fn prediction ->
        metadata = Map.get(prediction, :metadata) || %{}

        {
          result.sample.id,
          prediction.entity,
          prediction.byte_start,
          prediction.byte_end,
          prediction.score,
          Map.get(metadata, :model_label),
          Map.get(metadata, :recognizer)
        }
      end)
    end)
    |> Enum.sort()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp maybe_put_secondary_gate(report, samples, :hybrid_ner_tner_jean_location_gated) do
    texts = Enum.map(samples, & &1.text)

    Map.put(report, :secondary_gate, LocationGate.summary(texts))
  end

  defp maybe_put_secondary_gate(report, _samples, _profile), do: report

  defp real_profile_model_metadata(:hybrid_ner_tner_facebookai_org, _opts) do
    %{
      profile: :hybrid_ner_tner_facebookai_org,
      models: %{
        primary: model_metadata(:tner_roberta_large_ontonotes5),
        organization: model_metadata(:facebook_xlm_roberta_large_conll03_english)
      }
    }
  end

  defp real_profile_model_metadata(:hybrid_ner_tner_jean_location, opts) do
    entities = requested_entities(:hybrid_ner_tner_jean_location, opts)
    serving_needs = Routing.tner_jean_serving_needs(entities)

    %{
      profile: :hybrid_ner_tner_jean_location,
      models: %{
        primary: model_metadata(:tner_roberta_large_ontonotes5),
        location: model_metadata(:jean_baptiste_roberta_large_ner_english)
      },
      execution: %{
        active_models: active_tner_jean_models(serving_needs),
        parallel_recognizers: Keyword.get(opts, :parallel_recognizers, false),
        requested_entities: entities,
        scoped_routing: Keyword.has_key?(opts, :entities)
      },
      policy: %{
        primary_entities: [:person, :organization],
        location_entities: [:location],
        location_thresholds: %{"LOC" => 0.995}
      }
    }
  end

  defp real_profile_model_metadata(:hybrid_ner_tner_jean_location_gated, opts) do
    entities = requested_entities(:hybrid_ner_tner_jean_location_gated, opts)
    serving_needs = Routing.tner_jean_serving_needs(entities)

    %{
      profile: :hybrid_ner_tner_jean_location_gated,
      models: %{
        primary: model_metadata(:tner_roberta_large_ontonotes5),
        location: model_metadata(:jean_baptiste_roberta_large_ner_english)
      },
      execution: %{
        active_models: active_tner_jean_models(serving_needs),
        secondary_gate: :location_context,
        parallel_recognizers: Keyword.get(opts, :parallel_recognizers, false),
        requested_entities: entities,
        scoped_routing: Keyword.has_key?(opts, :entities)
      },
      policy: %{
        primary_entities: [:person, :organization],
        location_entities: [:location],
        location_thresholds: %{"LOC" => 0.995}
      }
    }
  end

  defp real_profile_model_metadata(:hybrid_ner_tner_jean_location_cascade, opts) do
    entities = requested_entities(:hybrid_ner_tner_jean_location_cascade, opts)
    serving_needs = Routing.tner_jean_cascade_serving_needs(entities)

    %{
      profile: :hybrid_ner_tner_jean_location_cascade,
      models: %{
        primary: model_metadata(:tner_roberta_large_ontonotes5),
        location: model_metadata(:jean_baptiste_roberta_large_ner_english)
      },
      execution: %{
        active_models: active_tner_jean_models(serving_needs),
        secondary_gate: :primary_output,
        requested_entities: entities,
        scoped_routing: Keyword.has_key?(opts, :entities)
      },
      policy: %{
        primary_entities: [:person, :organization, :location],
        secondary_entities: [:location],
        trigger: Keyword.get(opts, :cascade_trigger, :missing),
        uncertainty_threshold: Keyword.get(opts, :cascade_uncertainty_threshold, 0.97),
        context_policy: Keyword.get(opts, :cascade_context_policy, :none),
        secondary_threshold: Keyword.get(opts, :cascade_secondary_threshold, 0.999)
      }
    }
  end

  defp real_profile_model_metadata(_profile, opts) do
    opts
    |> Keyword.get(:model, :dslim_bert_base_ner)
    |> model_metadata()
  end

  defp active_tner_jean_models(%{primary: primary?, location: location?}) do
    []
    |> maybe_add_active_model(primary?, :primary)
    |> maybe_add_active_model(location?, :location)
  end

  defp maybe_add_active_model(models, true, model), do: models ++ [model]
  defp maybe_add_active_model(models, false, _model), do: models

  defp model_metadata(model) do
    case ModelRegistry.metadata(model) do
      {:ok, metadata} -> metadata
      {:error, _reason} -> %{model_alias: model}
    end
  end

  defp privacy_filter_report_n_ctx(opts) do
    case Keyword.fetch(opts, :privacy_filter_n_ctx) do
      {:ok, n_ctx} -> n_ctx
      :error -> "auto"
    end
  end

  defp skipped_report(profile, dataset, reason, opts) do
    dataset_name = dataset |> to_string() |> String.replace("-", "_")

    report =
      Report.build(
        run_id: run_id(dataset_name, profile, :skipped, opts),
        phase: "presidio_compatibility",
        adapter: adapter_name(profile),
        profile: profile,
        dataset: %{
          name: dataset_name,
          source: "eval/datasets/presidio_research",
          version: "presidio-research-snapshot",
          sample_count: 0,
          smoke: true,
          scope: "skipped",
          status: "skipped"
        },
        offset_mode: %{
          input: "character",
          internal: "byte",
          scoring: "byte",
          conversion: "not_run"
        },
        metrics: Metrics.score([], [], profile, total_samples: 0, latency_ms: []),
        skip_reason: skip_reason(profile, reason),
        limitations: [
          "Compatibility profile #{profile} was skipped: #{reason}",
          "No source text, detected values, model assets, credentials, or provider payloads were written."
        ]
      )

    report
    |> put_profile_identity(profile, opts)
    |> maybe_put_model(profile, opts)
  end

  defp write_missing_dataset_report(opts, path, _reason) do
    profile = Keyword.get(opts, :profile, :regex_only)
    dataset = dataset_for(opts)

    report =
      Report.build(
        run_id: run_id(to_string(dataset), profile, :missing),
        phase: "presidio_compatibility",
        adapter: adapter_name(profile),
        profile: profile,
        dataset: %{
          name: to_string(dataset),
          source: path,
          version: "presidio-research-snapshot",
          sample_count: 0,
          smoke: true,
          scope: "missing",
          status: "missing"
        },
        offset_mode: %{
          input: "character",
          internal: "byte",
          scoring: "byte",
          conversion: "not_run"
        },
        metrics: Metrics.score([], [], profile, total_samples: 0, latency_ms: []),
        limitations: [
          "Presidio-Research dataset was not available for compatibility scoring.",
          "Restore the committed benchmark snapshots or choose another dataset alias."
        ]
      )

    Report.write_pair(
      report,
      "eval/reports/#{report.run_id}.json",
      "eval/reports/#{report.run_id}.md"
    )
  end

  defp skip_reason(profile, reason) do
    message = to_string(reason)

    %{
      profile: Atom.to_string(profile),
      category: skip_reason_category(message),
      message: message
    }
  end

  defp skip_reason_category(message) do
    cond do
      String.contains?(message, "opt-in missing") -> "opt_in_missing"
      String.contains?(message, "incomplete_safetensors_file") -> "checkpoint_incomplete"
      String.contains?(message, "checkpoint missing") -> "checkpoint_missing"
      String.contains?(message, "compatibility run failed") -> "run_failed"
      String.contains?(message, "not automatic") -> "manual_provider_required"
      String.contains?(message, "currently defined") -> "unsupported_profile"
      true -> "skipped"
    end
  end

  defp safe_compatibility_failure(profile, reason) do
    code =
      cond do
        reason_has_code?(reason, :incomplete_safetensors_file) ->
          :incomplete_safetensors_file

        reason_has_code?(reason, :checkpoint_dir_not_found) ->
          :checkpoint_dir_not_found

        true ->
          :run_failed
      end

    "#{profile_group_label(profile)} compatibility run failed (#{code})."
  end

  defp reason_has_code?(code, code), do: true

  defp reason_has_code?(reason, code) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.any?(&reason_has_code?(&1, code))
  end

  defp reason_has_code?(reason, code) when is_list(reason) do
    Enum.any?(reason, &reason_has_code?(&1, code))
  end

  defp reason_has_code?(_reason, _code), do: false

  defp dataset_for(opts) do
    Keyword.get(opts, :dataset) ||
      if Keyword.get(opts, :full, false), do: @default_full_dataset, else: @default_smoke_dataset
  end

  defp normalize_product_profile_opts(opts) do
    requested = Keyword.get(opts, :profile, :regex_only)

    with {:ok, normalized} <- ProductProfile.normalize(requested) do
      {:ok,
       opts
       |> apply_product_profile_defaults(normalized.requested)
       |> Keyword.put(:requested_profile, normalized.requested)
       |> Keyword.put(:profile, normalized.implementation)}
    end
  end

  defp apply_product_profile_defaults(opts, :balanced) do
    Keyword.put(opts, :model, :tner_roberta_large_ontonotes5)
  end

  defp apply_product_profile_defaults(opts, :openmed_pii) do
    Keyword.put(opts, :privacy_filter_model_id, "OpenMed/privacy-filter-nemotron-v2")
  end

  defp apply_product_profile_defaults(opts, _profile), do: opts

  defp scope(opts) do
    base_scope = if Keyword.get(opts, :full, false), do: :full, else: :smoke

    case Keyword.get(opts, :template_split, :all) do
      :all -> base_scope
      split -> :"#{split}_#{base_scope}"
    end
  end

  defp run_id(dataset, profile, scope, opts \\ []) do
    base = "presidio_compatibility_#{dataset}_#{profile}_#{scope}"

    case Keyword.get(opts, :run_suffix) do
      nil -> base
      "" -> base
      suffix -> "#{base}_#{safe_suffix(suffix)}"
    end
  end

  defp safe_suffix(suffix) do
    suffix
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> String.trim("_")
  end

  defp adapter_name(:nlp), do: "Obscura.Fixtures.ObscuraAnalyzerAdapter+FakeNERIntegration"

  defp adapter_name(:deterministic_plus),
    do: "Obscura.Fixtures.ObscuraAnalyzerAdapter+DeterministicPlus"

  defp adapter_name(:real_ner), do: "Obscura.Recognizer.NER.Serving"
  defp adapter_name(:hybrid_ner), do: "Obscura.Deterministic+Obscura.Recognizer.NER.Serving"
  defp adapter_name(:hybrid_ner_conservative), do: adapter_name(:hybrid_ner)

  defp adapter_name(:hybrid_ner_balanced),
    do: "Obscura.Deterministic+Obscura.Recognizer.NER.Serving+BalancedORG"

  defp adapter_name(:hybrid_ner_org),
    do: "Obscura.Deterministic+Obscura.Recognizer.NER.Serving+ORG"

  defp adapter_name(:hybrid_ner_org_high_recall), do: adapter_name(:hybrid_ner_org)
  defp adapter_name(:hybrid_ner_dbmdz_conservative), do: adapter_name(:hybrid_ner)
  defp adapter_name(:hybrid_ner_tner_conservative), do: adapter_name(:hybrid_ner)
  defp adapter_name(:hybrid_ner_tner_high_recall), do: adapter_name(:hybrid_ner)

  defp adapter_name(:hybrid_ner_tner_facebookai_org),
    do: "Obscura.Deterministic+TNER.PersonLocation+FacebookAI.Organization"

  defp adapter_name(:hybrid_ner_tner_jean_location),
    do: "Obscura.Deterministic+TNER.PersonOrganization+JeanBaptiste.Location"

  defp adapter_name(:hybrid_ner_tner_jean_location_gated),
    do: "Obscura.Deterministic+TNER.PersonOrganization+GatedJeanBaptiste.Location"

  defp adapter_name(:hybrid_ner_tner_jean_location_cascade),
    do: "Obscura.Deterministic+TNER.Primary+OutputAwareJeanBaptiste.Location"

  defp adapter_name(:hybrid_ner_bigmed_conservative), do: adapter_name(:hybrid_ner)
  defp adapter_name(:gliner_ortex), do: "Obscura.Recognizer.GLiNER.Ortex"

  defp adapter_name(:hybrid_gliner_ortex),
    do: "Obscura.Deterministic+Obscura.Recognizer.GLiNER.Ortex"

  defp adapter_name(:hybrid_gliner_urchade),
    do: "Obscura.Deterministic+Obscura.Recognizer.GLiNER.Ortex.Urchade"

  defp adapter_name(:hybrid_gliner_urchade_native),
    do: "Obscura.Deterministic+Obscura.Recognizer.GLiNER.Native.Urchade"

  defp adapter_name(:privacy_filter_native), do: "Obscura.Recognizer.PrivacyFilter.Native"

  defp adapter_name(:hybrid_privacy_filter_native),
    do: "Obscura.Deterministic+Obscura.Recognizer.PrivacyFilter.Native"

  defp adapter_name(_profile), do: "Obscura.Fixtures.ObscuraAnalyzerAdapter"

  defp limitations(:nlp, scope) do
    [
      "Presidio-Research #{scope} compatibility report.",
      "The nlp profile uses deterministic fake NER outputs derived from gold spans; it is integration evidence only and must be excluded from accuracy comparison tables.",
      "Unsupported entities remain separate from analyzer failures."
    ]
  end

  defp limitations(:real_ner, scope) do
    [
      "Presidio-Research #{scope} compatibility report using an explicitly opted-in real local model.",
      "Exact-span scoring is strict and may penalize tokenizer boundary differences.",
      "Only entities supported by the selected real model profile are scored as supported."
    ]
  end

  defp limitations(:hybrid_ner, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic structured PII recognizers plus an explicitly opted-in real local NER model.",
      "Organization support is model-backed and thresholded because broad organization extraction is prone to false positives.",
      "Exact-span scoring is strict and IoU metrics should be reviewed for tokenizer boundary differences."
    ]
  end

  defp limitations(:hybrid_ner_conservative, scope), do: limitations(:hybrid_ner, scope)

  defp limitations(:hybrid_ner_balanced, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic structured PII recognizers plus an explicitly opted-in real local NER model.",
      "Organization support is enabled with a stricter threshold and context gating to balance recall against false positives.",
      "Exact-span scoring is strict and IoU metrics should be reviewed for tokenizer boundary differences."
    ]
  end

  defp limitations(:hybrid_ner_org, scope) do
    [
      "Presidio-Research #{scope} compatibility report for Obscura hybrid deterministic plus real local NER with organization enabled.",
      "This profile is an explicit benchmark variant. The conservative :hybrid_ner profile still ignores organization labels by default because Presidio's default spaCy config treats ORG/ORGANIZATION as false-positive prone.",
      "Organization support is model-backed and thresholded because broad organization extraction is prone to false positives.",
      "Only entities supported by the selected real model profile are scored as supported."
    ]
  end

  defp limitations(:hybrid_ner_org_high_recall, scope), do: limitations(:hybrid_ner_org, scope)

  defp limitations(:hybrid_ner_dbmdz_conservative, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers plus dbmdz BERT-large with model-specific policy.",
      "Organization is allowed only behind higher threshold and context gating.",
      "The profile is intended to compare against V10 dbmdz without changing the library default."
    ]
  end

  defp limitations(:hybrid_ner_tner_conservative, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers plus tner/roberta-large-ontonotes5 with conservative model-specific policy.",
      "The TNER model card reports strong OntoNotes5 results but warns that plain Transformers usage is not recommended because the CRF layer is unsupported; Bumblebee/Nx output must therefore be treated as experimental until measured.",
      "DATE/TIME and noisy non-PII OntoNotes labels are ignored by default; organization is allowed only behind higher threshold and context gating."
    ]
  end

  defp limitations(:hybrid_ner_tner_high_recall, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers plus tner/roberta-large-ontonotes5 with an opt-in high-recall model policy.",
      "This profile deliberately lowers GPE/FAC/ORG thresholds only for benchmark tuning; conservative behavior is unchanged.",
      "Organization support remains model-backed and thresholded. No broad deterministic organization regex is enabled."
    ]
  end

  defp limitations(:hybrid_ner_tner_facebookai_org, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers plus two explicitly opted-in local NER models.",
      "TNER handles person/location; FacebookAI XLM-R contributes organization spans only.",
      "This is an experimental multi-model contender profile and is not default behavior.",
      "The profile tests whether FacebookAI's organization recall gain can be preserved without its location false-positive cost."
    ]
  end

  defp limitations(:hybrid_ner_tner_jean_location, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers plus two explicitly opted-in local NER models.",
      "TNER handles person/organization; Jean-Baptiste contributes location spans only with the strict LOC=0.995 train-selected policy.",
      "This is an experimental multi-model contender profile and is not default behavior.",
      "The profile tests whether each model's strongest entity can be combined without accepting Jean-Baptiste person/organization regressions."
    ]
  end

  defp limitations(:hybrid_ner_tner_jean_location_gated, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers plus two explicitly opted-in local NER models.",
      "TNER handles person/organization; Jean-Baptiste contributes location spans only when a cheap location-context gate passes.",
      "This is an experimental latency profile and is not default behavior.",
      "The profile tests whether skipping the location-specialist model on low-signal texts reduces latency without losing the TNER plus Jean-Baptiste accuracy benefit."
    ]
  end

  defp limitations(:hybrid_ner_tner_jean_location_cascade, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers and an output-aware two-model local NER cascade.",
      "TNER remains primary for person, organization, and location; Jean-Baptiste contributes only policy-selected location recovery spans.",
      "The cascade policy must be selected only on template_train and evaluated unchanged on heldout datasets.",
      "This profile is experimental and cannot replace :balanced unless fresh accuracy, latency, and reproducibility gates pass."
    ]
  end

  defp limitations(:hybrid_ner_bigmed_conservative, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic recognizers plus BigMed/OpenMed with conservative model-specific policy.",
      "Noisy clinical/address/date source labels are ignored and structured model predictions are parser-validated before scoring.",
      "The profile tests whether BigMed's recall can be used without accepting the V11 false-positive rate."
    ]
  end

  defp limitations(:gliner_ortex, scope) do
    [
      "Presidio-Research #{scope} compatibility report for the optional Obscura GLiNER Ortex adapter.",
      "This profile is GLiNER-only so it can be compared directly against the Python GLiNER hybrid_core reference report.",
      "The Elixir Tokenizers wrapper does not expose Python's is_split_into_words option; this adapter reconstructs the GLiNER words_mask from tokenizer byte offsets and reports that tokenization mode in metadata.",
      "The profile is opt-in and experimental. It is not a default recognizer path."
    ]
  end

  defp limitations(:hybrid_gliner_ortex, scope) do
    [
      "Presidio-Research #{scope} compatibility report for deterministic structured PII plus optional GLiNER Ortex open-class recognition.",
      "GLiNER is restricted to person, location, and organization labels. Structured labels such as phone, credit card, IP address, domain, email, SSN, IBAN, and URL remain deterministic/parser-owned.",
      "The profile is opt-in and experimental. It does not change Obscura's conservative default behavior.",
      "Exact-span scoring is strict and IoU metrics should be reviewed for model boundary differences."
    ]
  end

  defp limitations(:hybrid_gliner_urchade, scope) do
    [
      "Presidio-Research #{scope} compatibility report for deterministic structured PII plus the locally exported urchade/gliner_multi_pii-v1 model.",
      "GLiNER is restricted to person, location, and organization labels. Structured PII remains deterministic/parser-owned.",
      "The model repository does not publish ONNX or complete tokenizer assets; the pinned Obscura export procedure is required.",
      "This profile is opt-in and experimental until provenance, parity, accuracy, and operational promotion gates pass."
    ]
  end

  defp limitations(:hybrid_gliner_urchade_native, scope) do
    [
      "Presidio-Research #{scope} compatibility report for deterministic structured PII plus the native Nx/Emily urchade/gliner_multi_pii-v1 model.",
      "GLiNER is restricted to person, location, and organization labels. Structured PII remains deterministic/parser-owned.",
      "The adapter requires the pinned local Safetensors and tokenizer export and forces both Emily fallback paths to raise.",
      "This profile is opt-in and experimental until parity, accuracy, latency, sustained-load, and memory gates pass."
    ]
  end

  defp limitations(:deterministic_plus, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic local recognizers.",
      "Person and location recognizers are context-limited and are not broad NER replacements.",
      "Address recognition is limited to explicit generated Presidio-Research address contexts.",
      "Unsupported entities remain separate from analyzer failures."
    ]
  end

  defp limitations(:privacy_filter_native, scope) do
    [
      "Presidio-Research #{scope} compatibility report for the optional native privacy-filter adapter.",
      "This profile uses privacy-filter alone so it can be compared directly against a Python privacy-filter reference run.",
      "The profile is opt-in and experimental. It is not a default recognizer path."
    ]
  end

  defp limitations(:hybrid_privacy_filter_native, scope) do
    [
      "Presidio-Research #{scope} compatibility report for deterministic structured PII plus optional native privacy-filter recognition.",
      "This profile is intended to measure whether native privacy-filter improves broad PII recall without replacing deterministic structured recognizers.",
      "The profile is opt-in and experimental. Promotion requires heldout precision, recall, F1, F2, and latency evidence."
    ]
  end

  defp limitations(_profile, scope) do
    [
      "Presidio-Research #{scope} compatibility report using deterministic Obscura recognizers.",
      "Presidio analyzer and anonymizer Python test cases are represented by converted fixtures, not executed in Python.",
      "Invalid gold samples from local Presidio-Research test data are dropped and counted in dataset.invalid_sample_count.",
      "Unsupported entities remain separate from analyzer false negatives."
    ]
  end

  defp real_model_opt_in?(opts) do
    Keyword.get(opts, :real_model, false) or System.get_env("OBSCURA_EVAL_REAL_MODEL") == "1"
  end

  defp gliner_ortex_opt_in?(opts) do
    Keyword.get(opts, :gliner_ortex, false) or
      System.get_env("OBSCURA_GLINER_ORTEX") == "1" or
      System.get_env("OBSCURA_EVAL_GLINER_ORTEX") == "1"
  end

  defp gliner_native_opt_in?(opts) do
    Keyword.get(opts, :gliner_native, false) or
      System.get_env("OBSCURA_GLINER_NATIVE") == "1" or
      System.get_env("OBSCURA_EVAL_GLINER_NATIVE") == "1"
  end

  defp gliner_profile_opted_in?(profile, opts) when profile in @gliner_native_profiles,
    do: gliner_native_opt_in?(opts)

  defp gliner_profile_opted_in?(_profile, opts), do: gliner_ortex_opt_in?(opts)

  defp privacy_filter_opt_in?(opts) do
    Keyword.get(opts, :privacy_filter_native, false) or
      System.get_env("OBSCURA_EVAL_PRIVACY_FILTER_NATIVE") == "1" or
      not is_nil(privacy_filter_checkpoint(opts))
  end

  defp privacy_filter_checkpoint(opts) do
    Keyword.get(opts, :privacy_filter_checkpoint) ||
      System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
  end

  defp privacy_filter_model_id(opts) do
    Keyword.get(opts, :privacy_filter_model_id) ||
      System.get_env("OBSCURA_PRIVACY_FILTER_MODEL_ID") ||
      "openai/privacy-filter"
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end

  defp hybrid_ner_opts(profile, serving, opts) do
    serving.model_spec.policy
    |> Keyword.put(:label_map, serving.model_spec.label_map)
    |> Keyword.put_new(:aggregation_strategy, serving.model_spec.aggregation)
    |> Keyword.put_new(:alignment_mode, :expand)
    |> Keyword.put_new(:score_threshold, 0.7)
    |> maybe_put_profile_ner_policy(profile)
    |> maybe_put_score_threshold(opts)
    |> maybe_put_per_entity_thresholds(opts)
    |> maybe_put_per_label_thresholds(opts)
    |> maybe_put_context_required_labels(opts)
    |> maybe_put_context_required_below_labels(opts)
    |> maybe_put_context_words_by_label(opts)
    |> maybe_put_weak_context_words_by_label(opts)
    |> maybe_put_negative_context_words_by_label(opts)
    |> maybe_put_negative_context_reject_labels(opts)
    |> maybe_put_low_score_labels(opts)
    |> maybe_put_boundary_normalization(opts)
    |> maybe_put_model_postprocessors(opts)
    |> maybe_put_model_chunking(opts)
    |> maybe_enable_organization(profile)
  end

  defp tner_primary_opts(serving, opts) do
    :hybrid_ner_tner_conservative
    |> hybrid_ner_opts(serving, opts)
    |> Keyword.put(:serving, serving)
    |> Keyword.put(:entities, [:person, :location])
  end

  defp tner_person_organization_opts(serving, opts) do
    :hybrid_ner_tner_conservative
    |> hybrid_ner_opts(serving, opts)
    |> Keyword.put(:serving, serving)
    |> Keyword.put(:entities, [:person, :organization])
  end

  defp tner_cascade_primary_opts(serving, opts) do
    :hybrid_ner_tner_conservative
    |> hybrid_ner_opts(serving, opts)
    |> Keyword.put(:serving, serving)
    |> Keyword.put(:entities, [:person, :organization, :location])
  end

  defp jean_baptiste_location_opts(serving, opts) do
    serving.model_spec.policy
    |> Keyword.put(:serving, serving)
    |> Keyword.put(:label_map, serving.model_spec.label_map)
    |> Keyword.put_new(:aggregation_strategy, serving.model_spec.aggregation)
    |> Keyword.put_new(:alignment_mode, :expand)
    |> Keyword.put_new(:score_threshold, 0.7)
    |> Keyword.put(:entities, [:location])
    |> Keyword.put(:per_label_thresholds, %{"LOC" => jean_baptiste_location_threshold(opts)})
    |> Keyword.put(:boundary_normalization, Keyword.get(opts, :ner_boundary_normalization, :none))
    |> maybe_put_context_required_labels(opts)
    |> maybe_put_context_required_below_labels(opts)
    |> maybe_put_context_words_by_label(opts)
    |> maybe_put_weak_context_words_by_label(opts)
    |> maybe_put_negative_context_words_by_label(opts)
    |> maybe_put_negative_context_reject_labels(opts)
    |> maybe_put_model_postprocessors(opts)
    |> maybe_put_model_chunking(opts)
  end

  defp gated_jean_baptiste_location_opts(serving, opts) do
    serving
    |> jean_baptiste_location_opts(opts)
    |> Keyword.put(:secondary_gate, {LocationGate, :run?})
  end

  defp jean_baptiste_location_threshold(opts) do
    thresholds = Keyword.get(opts, :ner_per_label_thresholds, %{})

    Keyword.get(
      opts,
      :cascade_secondary_threshold,
      Map.get(thresholds, "JEAN_LOC", Map.get(thresholds, "LOC", 0.995))
    )
  end

  defp cascade_opts(opts) do
    [
      cascade_trigger: Keyword.get(opts, :cascade_trigger, :missing),
      cascade_context_policy: Keyword.get(opts, :cascade_context_policy, :none),
      cascade_uncertainty_threshold: Keyword.get(opts, :cascade_uncertainty_threshold, 0.97),
      cascade_observer: Keyword.get(opts, :cascade_observer)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp facebookai_organization_opts(serving, opts) do
    serving.model_spec.policy
    |> Keyword.put(:serving, serving)
    |> Keyword.put(:label_map, serving.model_spec.label_map)
    |> Keyword.put_new(:aggregation_strategy, serving.model_spec.aggregation)
    |> Keyword.put_new(:alignment_mode, :expand)
    |> Keyword.put_new(:score_threshold, 0.7)
    |> Keyword.put(:entities, [:organization])
    |> Keyword.put(:per_label_thresholds, %{"ORG" => facebookai_org_threshold(opts)})
    |> Keyword.put(:context_required_below_labels, %{"ORG" => 0.99})
    |> Keyword.put(:context_words_by_label, %{"ORG" => @v21_org_context_words})
    |> Keyword.put(:boundary_normalization, Keyword.get(opts, :ner_boundary_normalization, :none))
    |> maybe_put_per_label_thresholds(opts)
    |> maybe_put_context_required_labels(opts)
    |> maybe_put_context_required_below_labels(opts)
    |> maybe_put_context_words_by_label(opts)
    |> maybe_put_weak_context_words_by_label(opts)
    |> maybe_put_negative_context_words_by_label(opts)
    |> maybe_put_negative_context_reject_labels(opts)
    |> maybe_put_model_postprocessors(opts)
    |> maybe_put_model_chunking(opts)
  end

  defp facebookai_org_threshold(opts) do
    thresholds = Keyword.get(opts, :ner_per_label_thresholds, %{})

    Map.get(thresholds, "FACEBOOKAI_ORG", Map.get(thresholds, "ORG", 0.98))
  end

  defp real_ner_opts(serving, opts) do
    serving.model_spec.policy
    |> Keyword.put(:label_map, serving.model_spec.label_map)
    |> Keyword.put_new(:aggregation_strategy, serving.model_spec.aggregation)
    |> Keyword.put_new(:alignment_mode, :expand)
    |> Keyword.put_new(:score_threshold, 0.7)
    |> maybe_put_score_threshold(opts)
    |> maybe_put_per_entity_thresholds(opts)
    |> maybe_put_per_label_thresholds(opts)
    |> maybe_put_context_required_labels(opts)
    |> maybe_put_context_required_below_labels(opts)
    |> maybe_put_context_words_by_label(opts)
    |> maybe_put_weak_context_words_by_label(opts)
    |> maybe_put_negative_context_words_by_label(opts)
    |> maybe_put_negative_context_reject_labels(opts)
    |> maybe_put_low_score_labels(opts)
    |> maybe_put_boundary_normalization(opts)
    |> maybe_put_model_postprocessors(opts)
    |> maybe_put_model_chunking(opts)
  end

  defp maybe_put_profile_ner_policy(ner_opts, :hybrid_ner_tner_high_recall) do
    ner_opts
    |> Keyword.put(:per_label_thresholds, %{
      "PERSON" => 0.7,
      "ORG" => 0.95,
      "GPE" => 0.84,
      "LOC" => 0.88,
      "FAC" => 0.92
    })
    |> Keyword.put(:context_required_labels, [])
    |> Keyword.put(:context_required_below_labels, %{
      "ORG" => 0.98,
      "LOC" => 0.94,
      "FAC" => 0.97
    })
  end

  defp maybe_put_profile_ner_policy(ner_opts, _profile), do: ner_opts

  defp maybe_put_score_threshold(ner_opts, opts) do
    case Keyword.fetch(opts, :ner_score_threshold) do
      {:ok, threshold} -> Keyword.put(ner_opts, :score_threshold, threshold)
      :error -> ner_opts
    end
  end

  defp maybe_put_per_entity_thresholds(ner_opts, opts) do
    case Keyword.get(opts, :ner_per_entity_thresholds) do
      thresholds when is_map(thresholds) or is_list(thresholds) ->
        Keyword.put(ner_opts, :per_entity_thresholds, thresholds)

      _none ->
        ner_opts
    end
  end

  defp maybe_put_per_label_thresholds(ner_opts, opts) do
    case Keyword.get(opts, :ner_per_label_thresholds) do
      thresholds when is_map(thresholds) or is_list(thresholds) ->
        Keyword.put(ner_opts, :per_label_thresholds, thresholds)

      _none ->
        ner_opts
    end
  end

  defp maybe_put_context_required_below_labels(ner_opts, opts) do
    case Keyword.get(opts, :ner_context_required_below_labels) do
      thresholds when is_map(thresholds) or is_list(thresholds) ->
        Keyword.put(ner_opts, :context_required_below_labels, thresholds)

      _none ->
        ner_opts
    end
  end

  defp maybe_put_context_required_labels(ner_opts, opts) do
    case Keyword.get(opts, :ner_context_required_labels) do
      labels when is_list(labels) -> Keyword.put(ner_opts, :context_required_labels, labels)
      _none -> ner_opts
    end
  end

  defp maybe_put_context_words_by_label(ner_opts, opts) do
    case Keyword.get(opts, :ner_context_words_by_label) do
      words when is_map(words) -> Keyword.put(ner_opts, :context_words_by_label, words)
      _none -> ner_opts
    end
  end

  defp maybe_put_weak_context_words_by_label(ner_opts, opts) do
    case Keyword.get(opts, :ner_weak_context_words_by_label) do
      words when is_map(words) -> Keyword.put(ner_opts, :weak_context_words_by_label, words)
      _none -> ner_opts
    end
  end

  defp maybe_put_negative_context_words_by_label(ner_opts, opts) do
    case Keyword.get(opts, :ner_negative_context_words_by_label) do
      words when is_map(words) -> Keyword.put(ner_opts, :negative_context_words_by_label, words)
      _none -> ner_opts
    end
  end

  defp maybe_put_negative_context_reject_labels(ner_opts, opts) do
    case Keyword.get(opts, :ner_negative_context_reject_labels) do
      labels when is_list(labels) ->
        Keyword.put(ner_opts, :negative_context_reject_labels, labels)

      _none ->
        ner_opts
    end
  end

  defp maybe_put_low_score_labels(ner_opts, opts) do
    case Keyword.get(opts, :ner_low_score_labels) do
      labels when is_list(labels) -> Keyword.put(ner_opts, :low_score_labels, labels)
      _none -> ner_opts
    end
  end

  defp maybe_put_boundary_normalization(ner_opts, opts) do
    case Keyword.get(opts, :ner_boundary_normalization) do
      mode when mode in [:none, :conservative] ->
        Keyword.put(ner_opts, :boundary_normalization, mode)

      _none ->
        ner_opts
    end
  end

  defp maybe_put_model_postprocessors(ner_opts, opts) do
    case Keyword.get(opts, :ner_model_postprocessors) do
      postprocessors when is_list(postprocessors) ->
        Keyword.put(ner_opts, :model_postprocessors, postprocessors)

      _none ->
        ner_opts
    end
  end

  defp maybe_put_model_chunking(ner_opts, opts) do
    ner_opts
    |> maybe_put_model_chunking_mode(opts)
    |> maybe_put_model_chunk_number(opts, :ner_model_chunk_size, :model_chunk_size)
    |> maybe_put_model_chunk_number(opts, :ner_model_chunk_overlap, :model_chunk_overlap)
  end

  defp maybe_put_model_chunking_mode(ner_opts, opts) do
    case Keyword.get(opts, :ner_model_chunking) do
      mode when mode in [:none, :character] -> Keyword.put(ner_opts, :model_chunking, mode)
      _none -> ner_opts
    end
  end

  defp maybe_put_model_chunk_number(ner_opts, opts, opt_key, ner_key) do
    case Keyword.get(opts, opt_key) do
      value when is_integer(value) -> Keyword.put(ner_opts, ner_key, value)
      _none -> ner_opts
    end
  end

  defp maybe_enable_organization(opts, profile)
       when profile in [
              :hybrid_ner_balanced,
              :hybrid_ner_org,
              :hybrid_ner_org_high_recall,
              :hybrid_ner_tner_high_recall
            ],
       do: Keyword.put(opts, :labels_to_ignore, [])

  defp maybe_enable_organization(opts, _profile), do: opts

  defp phone_opts(opts) do
    []
    |> maybe_put_phone_opt(opts, :phone_parser)
    |> maybe_put_phone_opt(opts, :phone_validator)
    |> maybe_put_phone_opt(opts, :phone_regions)
  end

  defp maybe_put_phone_opt(acc, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Keyword.put(acc, key, value)
      :error -> acc
    end
  end

  defp base_label_thresholds(opts, profile, serving) do
    Keyword.get(opts, :ner_per_label_thresholds) ||
      model_label_thresholds(serving) ||
      case profile do
        :hybrid_ner_tner_high_recall ->
          %{"PERSON" => 0.7, "ORG" => 0.95, "GPE" => 0.84, "LOC" => 0.88, "FAC" => 0.92}

        _profile ->
          %{"PERSON" => 0.72, "ORG" => 0.98, "GPE" => 0.9, "LOC" => 0.92, "FAC" => 0.97}
      end
  end

  defp model_label_thresholds(%{model_spec: %{policy: policy}}) when is_list(policy) do
    Keyword.get(policy, :per_label_thresholds)
  end

  defp model_label_thresholds(_serving), do: nil

  defp default_label_threshold_values(:hybrid_ner_tner_high_recall) do
    %{
      "PERSON" => [0.68, 0.7, 0.72],
      "ORG" => [0.92, 0.95, 0.98],
      "GPE" => [0.8, 0.84, 0.88],
      "LOC" => [0.84, 0.88, 0.92],
      "FAC" => [0.88, 0.92, 0.97]
    }
  end

  defp default_label_threshold_values(_profile) do
    %{
      "PERSON" => [0.68, 0.72, 0.76],
      "ORG" => [0.95, 0.98],
      "GPE" => [0.84, 0.9],
      "LOC" => [0.88, 0.92],
      "FAC" => [0.92, 0.97]
    }
  end

  @doc false
  def gliner_label_threshold_candidates(opts, _profile) do
    base =
      opts
      |> Keyword.get(:gliner_per_label_thresholds, default_gliner_thresholds(opts))
      |> normalize_gliner_thresholds()

    values =
      opts
      |> Keyword.get(:label_threshold_values)
      |> case do
        nil ->
          %{
            "person" => [0.45, 0.5, 0.55],
            "organization" => [0.45, 0.5, 0.55, 0.6],
            "location" => [0.4, 0.45, 0.5, 0.55]
          }

        values ->
          normalize_gliner_threshold_values(values)
      end

    ([base] ++
       Enum.flat_map(values, fn {label, label_values} ->
         Enum.map(label_values, fn value -> Map.put(base, label, value) end)
       end))
    |> Enum.uniq()
  end

  defp normalize_gliner_thresholds(thresholds) when is_map(thresholds) or is_list(thresholds) do
    Map.new(thresholds, fn {label, threshold} ->
      {label |> to_string() |> String.downcase(), threshold}
    end)
  end

  defp normalize_gliner_threshold_values(values) when is_map(values) or is_list(values) do
    Map.new(values, fn {label, thresholds} ->
      {label |> to_string() |> String.downcase(), thresholds}
    end)
  end

  defp default_hybrid_gliner_thresholds(:open_class, _opts),
    do: @hybrid_gliner_open_class_thresholds

  defp default_hybrid_gliner_thresholds(_profile, _opts), do: %{}

  defp default_gliner_thresholds(opts) do
    threshold = Keyword.get(opts, :gliner_threshold, 0.5)
    profile = Keyword.get(opts, :gliner_label_profile, :open_class)

    case LabelMap.labels(profile) do
      {:ok, labels} -> Map.new(labels, &{&1, threshold})
      {:error, _reason} -> %{}
    end
  end
end
