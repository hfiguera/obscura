defmodule Obscura.Recognizer.NER.OutputAwareCascade do
  @moduledoc """
  Output-aware TNER and Jean-Baptiste location cascade.

  The primary recognizer always runs for requested open-class entities. The
  secondary location recognizer runs only when the primary location output
  satisfies the configured trigger policy. This module is intentionally an
  experimental recognizer used to measure whether selective location recovery
  improves on the single-model TNER profile.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Batch
  alias Obscura.Recognizer.NER

  @open_class_entities [:person, :organization, :location]
  @triggers [:never, :missing, :missing_or_uncertain, :always]
  @context_policies [:none, :strong, :strong_or_overlap]
  @strong_location_context ~r/\b(address(?:es)?|city|state|country|county|province|region|zip|postal|street|avenue|road|boulevard|lane|drive|apartment|suite|located|location|lives\s+in|based\s+in|works\s+in|town|near)\b/i
  @comma_location ~r/\b[A-Z][\w'-]+(?:\s+[A-Z][\w'-]+){0,2},\s+[A-Z][\w'-]+/
  @street_address ~r/\b\d{1,6}\s+[A-Z][\w'-]+/

  @impl true
  def name, do: :ner_output_aware_cascade

  @impl true
  def supported_entities, do: @open_class_entities

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    with {:ok, config} <- validate_opts(opts),
         {:ok, primary_results} <- NER.analyze(text, config.primary_opts),
         decision <- decision(primary_results, config),
         {:ok, secondary_results} <- maybe_run_secondary(text, decision, config),
         accepted_secondary <- accept_secondary(text, primary_results, secondary_results, config),
         results <- merge_results(primary_results, accepted_secondary, decision),
         :ok <- notify(config.observer, event(decision, secondary_results, accepted_secondary)) do
      {:ok, results}
    end
  end

  @impl true
  def analyze_many(texts, opts) when is_list(texts) and is_list(opts) do
    Batch.run_many(texts, &analyze(&1, opts))
  end

  defp validate_opts(opts) do
    with {:ok, primary_opts} <- required_keyword(opts, :primary_opts),
         {:ok, secondary_opts} <- required_keyword(opts, :secondary_opts),
         {:ok, trigger} <- member(opts, :cascade_trigger, :missing, @triggers),
         {:ok, context_policy} <-
           member(opts, :cascade_context_policy, :none, @context_policies),
         {:ok, uncertainty_threshold} <-
           probability(opts, :cascade_uncertainty_threshold, 0.97),
         {:ok, observer} <- observer(opts) do
      {:ok,
       %{
         primary_opts: primary_opts,
         secondary_opts: secondary_opts,
         trigger: trigger,
         context_policy: context_policy,
         uncertainty_threshold: uncertainty_threshold,
         observer: observer
       }}
    end
  end

  defp required_keyword(opts, key) do
    case Keyword.get(opts, key) do
      value when is_list(value) -> {:ok, value}
      _other -> {:error, {:invalid_cascade_option, key}}
    end
  end

  defp member(opts, key, default, allowed) do
    value = Keyword.get(opts, key, default)
    if value in allowed, do: {:ok, value}, else: {:error, {:invalid_cascade_option, key}}
  end

  defp probability(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_number(value) and value >= 0 and value <= 1 -> {:ok, value / 1}
      _other -> {:error, {:invalid_cascade_option, key}}
    end
  end

  defp observer(opts) do
    case Keyword.get(opts, :cascade_observer) do
      nil -> {:ok, nil}
      {pid, ref} = observer when is_pid(pid) and is_reference(ref) -> {:ok, observer}
      _other -> {:error, {:invalid_cascade_option, :cascade_observer}}
    end
  end

  defp decision(primary_results, %{trigger: trigger, uncertainty_threshold: threshold}) do
    locations = Enum.filter(primary_results, &(&1.entity == :location))
    max_score = locations |> Enum.map(& &1.score) |> Enum.max(fn -> nil end)

    {run?, reason} =
      case trigger do
        :never -> {false, :disabled}
        :missing -> {locations == [], if(locations == [], do: :missing, else: :primary_location)}
        :missing_or_uncertain when locations == [] -> {true, :missing}
        :missing_or_uncertain when max_score < threshold -> {true, :uncertainty}
        :missing_or_uncertain -> {false, :primary_confident}
        :always -> {true, :always}
      end

    %{run?: run?, reason: reason, primary_location_count: length(locations), max_score: max_score}
  end

  defp maybe_run_secondary(_text, %{run?: false}, _config), do: {:ok, []}

  defp maybe_run_secondary(text, %{run?: true}, config),
    do: NER.analyze(text, config.secondary_opts)

  defp accept_secondary(_text, _primary, [], _config), do: []

  defp accept_secondary(text, primary, secondary, %{context_policy: policy}) do
    Enum.filter(secondary, fn candidate ->
      case policy do
        :none ->
          true

        :strong ->
          strong_location_context?(text)

        :strong_or_overlap ->
          strong_location_context?(text) or overlaps_primary?(candidate, primary)
      end
    end)
  end

  defp strong_location_context?(text) do
    Regex.match?(@strong_location_context, text) or
      Regex.match?(@comma_location, text) or
      Regex.match?(@street_address, text)
  end

  defp overlaps_primary?(candidate, primary) do
    Enum.any?(primary, fn result ->
      result.entity == :location and
        candidate.byte_start < result.byte_end and result.byte_start < candidate.byte_end
    end)
  end

  defp merge_results(primary, secondary, decision) do
    (tag(primary, :primary, decision) ++ tag(secondary, :secondary, decision))
    |> Enum.group_by(&{&1.entity, &1.byte_start, &1.byte_end})
    |> Enum.map(fn {_key, results} -> Enum.max_by(results, & &1.score) end)
    |> Enum.sort_by(&{&1.byte_start, &1.byte_end, &1.entity})
  end

  defp tag(results, role, decision) do
    Enum.map(results, fn result ->
      metadata =
        Map.merge(result.metadata || %{}, %{
          cascade_role: role,
          cascade_secondary_run: decision.run?,
          cascade_trigger_reason: decision.reason
        })

      %{result | metadata: metadata}
    end)
  end

  defp event(decision, proposed, accepted) do
    %{
      secondary_run: decision.run?,
      trigger_reason: decision.reason,
      primary_location_count: decision.primary_location_count,
      primary_location_max_score: decision.max_score,
      secondary_proposed_count: length(proposed),
      secondary_accepted_count: length(accepted)
    }
  end

  defp notify(nil, _event), do: :ok

  defp notify({pid, ref}, event) do
    send(pid, {:ner_output_aware_cascade, ref, event})
    :ok
  end
end
