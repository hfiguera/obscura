defmodule Obscura.Eval.AuthoritativeManifest do
  @moduledoc """
  Promotion and integrity validation for authoritative benchmark reports.

  Generated reports remain under `eval/reports`. Promotion copies a validated
  JSON/Markdown pair into `eval/authoritative/reports` and records reproducible
  metadata plus SHA-256 hashes in the authoritative manifest.
  """

  alias Obscura.Eval.RuntimeMetadata
  alias Obscura.Profile

  @schema_version 1
  @required_entry_fields ~w(id status stable_profile resolved_profile source_commit dirty_worktree generated_at source_report_timestamp command dataset entity_policy runtime models asset_hashes dependencies environment metrics repetitions limitations files)
  @required_external_entry_fields ~w(id status entry_type system adapter source_commit dirty_worktree generated_at source_report_timestamp command dataset entity_policy protocol runtime models asset_hashes dependencies environment metrics repetitions limitations files)
  @sensitive_value_keys ~w(text value raw_text source_text)
  @authoritative_report_fields ~w(adapter comparison_protocol dataset dependencies entity_mapping examples external_baseline git_sha gold_derived latency limitations model offset_mode phase profile recognizer_execution requested_profile resolved_profile run_id runtime_backend skip_reason source stage_latency status threshold_sweep timestamp)
  @authoritative_metric_fields ~w(precision recall f1 f2 true_positives false_positives false_negatives wrong_entity_type offset_mismatches unsupported_expected_spans output_fingerprint_sha256 span_iou)

  @doc """
  Returns the default project manifest path.
  """
  @spec path() :: Path.t()
  def path, do: Path.expand("eval/authoritative/manifest.json")

  @doc """
  Loads and validates an authoritative manifest.
  """
  @spec load(Path.t()) :: {:ok, map()} | {:error, term()}
  def load(manifest_path \\ path()) do
    with {:ok, body} <- File.read(manifest_path),
         {:ok, manifest} <- Jason.decode(body),
         :ok <- validate(manifest) do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, {:invalid_authoritative_manifest, manifest_path, reason}}
    end
  end

  @doc """
  Validates manifest schema and entry uniqueness.
  """
  @spec validate(map()) :: :ok | {:error, term()}
  def validate(%{"schema_version" => @schema_version, "reports" => reports})
      when is_list(reports) do
    with :ok <- validate_unique_ids(reports) do
      validate_entries(reports)
    end
  end

  def validate(_manifest), do: {:error, :invalid_authoritative_manifest_schema}

  @doc """
  Promotes a generated JSON/Markdown report pair.

  Required options are `:stable_profile`, `:command`, `:model_revisions`, and
  `:asset_hashes` for model-backed profiles. Tests may override
  `:manifest_path` and `:reports_dir`.
  """
  @spec promote(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def promote(report_path, opts) when is_binary(report_path) and is_list(opts) do
    manifest_path = Keyword.get(opts, :manifest_path, path())
    reports_dir = Keyword.get(opts, :reports_dir, Path.expand("eval/authoritative/reports"))

    with {:ok, descriptor} <- fetch_stable_profile(opts),
         {:ok, report, markdown_path} <- load_report_pair(report_path),
         :ok <- validate_report(report, report_path, markdown_path, descriptor, opts),
         {:ok, repetitions} <- load_repetitions(report_path, report, descriptor, opts),
         {:ok, manifest} <- load(manifest_path),
         {:ok, entry, destinations} <-
           build_entry(
             report,
             report_path,
             markdown_path,
             descriptor,
             reports_dir,
             repetitions,
             opts
           ),
         :ok <- copy_reports(markdown_path, destinations, opts) do
      put_entry(manifest, entry, manifest_path)
    end
  end

  @doc """
  Promotes a fingerprinted external baseline report.

  External baselines are intentionally separate from stable Obscura profiles.
  At least two measured reports are required.
  """
  @spec promote_external(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def promote_external(report_path, opts) when is_binary(report_path) and is_list(opts) do
    manifest_path = Keyword.get(opts, :manifest_path, path())
    reports_dir = Keyword.get(opts, :reports_dir, Path.expand("eval/authoritative/reports"))

    with {:ok, report, markdown_path} <- load_report_pair(report_path),
         :ok <- validate_external_report(report, report_path, markdown_path),
         {:ok, repetitions} <- load_external_repetitions(report_path, report, opts),
         :ok <- require_external_repetitions(repetitions),
         {:ok, manifest} <- load(manifest_path),
         {:ok, entry, destinations} <-
           build_external_entry(
             report,
             report_path,
             markdown_path,
             reports_dir,
             repetitions,
             opts
           ),
         :ok <- copy_external_reports(markdown_path, destinations, opts) do
      put_entry(manifest, entry, manifest_path)
    end
  end

  @doc """
  Verifies all promoted report hashes and manifest structure.
  """
  @spec verify(Path.t()) :: :ok | {:error, term()}
  def verify(manifest_path \\ path()) do
    with {:ok, manifest} <- load(manifest_path) do
      verify_entries(manifest["reports"], manifest_path)
    end
  end

  defp fetch_stable_profile(opts) do
    case Keyword.fetch(opts, :stable_profile) do
      {:ok, profile} -> Profile.fetch(profile)
      :error -> {:error, :missing_stable_profile}
    end
  end

  defp load_report_pair(report_path) do
    markdown_path = Path.rootname(report_path) <> ".md"

    with {:ok, body} <- File.read(report_path),
         {:ok, report} <- Jason.decode(body),
         true <- File.regular?(markdown_path) do
      {:ok, report, markdown_path}
    else
      false -> {:error, {:missing_markdown_report, markdown_path}}
      {:error, reason} -> {:error, {:invalid_report_pair, report_path, reason}}
    end
  end

  defp validate_report(report, report_path, markdown_path, descriptor, opts) do
    with :ok <- validate_not_skipped(report),
         :ok <- validate_not_fake(report),
         :ok <- validate_profile(report, descriptor),
         :ok <- validate_metrics(report),
         :ok <- validate_markdown_metrics(report, markdown_path),
         :ok <- validate_dataset(report, report_path),
         :ok <- validate_portable_command(%{"command" => Keyword.fetch!(opts, :command)}),
         :ok <- validate_model_evidence(descriptor, report, opts),
         :ok <- validate_output_fingerprint(descriptor, report),
         :ok <- validate_source_evidence(descriptor, report) do
      validate_no_raw_values(report)
    end
  end

  defp validate_external_report(report, report_path, markdown_path) do
    with :ok <- validate_not_skipped(report),
         :ok <- validate_not_fake(report),
         :ok <- validate_external_identity(report),
         :ok <- validate_metrics(report),
         :ok <- validate_markdown_metrics(report, markdown_path),
         :ok <- validate_dataset(report, report_path),
         :ok <- validate_portable_command(report),
         :ok <- validate_external_protocol(report),
         :ok <- validate_external_dependencies(report),
         :ok <- validate_external_environment(report) do
      validate_no_raw_values(report)
    end
  end

  defp validate_external_identity(%{
         "status" => "complete",
         "external_baseline" => true,
         "gold_derived" => false,
         "adapter" => adapter,
         "profile" => "presidio_spacy_en_core_web_lg"
       })
       when is_binary(adapter) and adapter != "",
       do: :ok

  defp validate_external_identity(_report), do: {:error, :invalid_external_baseline_identity}

  defp validate_portable_command(%{"command" => command}) when is_binary(command) do
    unix_absolute? = Regex.match?(~r/(?:^|\s|=)\//, command)
    windows_absolute? = Regex.match?(~r/(?:^|\s|=)[A-Za-z]:[\\\/]/, command)

    if unix_absolute? or windows_absolute?,
      do: {:error, :report_command_contains_absolute_path},
      else: :ok
  end

  defp validate_portable_command(_report), do: {:error, :missing_report_command}

  defp validate_external_protocol(%{
         "comparison_protocol" => %{
           "id" => id,
           "selection_sha256" => selection,
           "protocol_sha256" => protocol,
           "sample_ids_sha256" => sample_ids,
           "entity_policy_sha256" => entity_policy,
           "scoring_sha256" => scoring
         }
       }) do
    hashes = [selection, protocol, sample_ids, entity_policy, scoring]

    if is_binary(id) and id != "" and Enum.all?(hashes, &sha256?/1),
      do: :ok,
      else: {:error, :incomplete_external_protocol_evidence}
  end

  defp validate_external_protocol(_report),
    do: {:error, :incomplete_external_protocol_evidence}

  defp validate_external_dependencies(%{
         "dependencies" => %{
           "python" => python,
           "lock_sha256" => lock_sha,
           "packages" => packages
         }
       })
       when is_binary(python) and is_map(packages) do
    required = ~w(presidio-analyzer presidio-evaluator spacy en_core_web_lg)

    if sha256?(lock_sha) and
         Enum.all?(required, &(is_binary(packages[&1]) and packages[&1] != "not-installed")),
       do: :ok,
       else: {:error, :incomplete_external_dependency_evidence}
  end

  defp validate_external_dependencies(_report),
    do: {:error, :incomplete_external_dependency_evidence}

  defp validate_external_environment(%{
         "environment" => environment,
         "runtime_backend" => runtime
       })
       when is_map(environment) and is_map(runtime) do
    required = ~w(hardware_label os architecture cpu memory_bytes accelerator)

    if Enum.all?(required, &present?(environment[&1])) and runtime_backend_recorded?(runtime),
      do: :ok,
      else: {:error, :incomplete_external_environment_evidence}
  end

  defp validate_external_environment(_report),
    do: {:error, :incomplete_external_environment_evidence}

  defp validate_not_skipped(%{"skip_reason" => reason}) when not is_nil(reason),
    do: {:error, {:skipped_report_not_authoritative, reason}}

  defp validate_not_skipped(%{"dataset" => %{"status" => "skipped"}}),
    do: {:error, :skipped_report_not_authoritative}

  defp validate_not_skipped(_report), do: :ok

  defp validate_not_fake(report) do
    adapter = report |> Map.get("adapter", "") |> String.downcase()
    profile = report |> Map.get("profile", "") |> String.downcase()

    if String.contains?(adapter, "fake") or profile == "nlp" do
      {:error, :fake_or_gold_derived_report_not_authoritative}
    else
      :ok
    end
  end

  defp validate_profile(report, descriptor) do
    if report["profile"] == Atom.to_string(descriptor.implementation_profile) do
      :ok
    else
      {:error,
       {:profile_mismatch, Atom.to_string(descriptor.implementation_profile), report["profile"]}}
    end
  end

  defp validate_metrics(%{"metrics" => metrics, "latency" => latency})
       when is_map(metrics) and is_map(latency) do
    required =
      ~w(precision recall f1 f2 true_positives false_positives false_negatives wrong_entity_type offset_mismatches)

    missing = Enum.reject(required, &is_number(metrics[&1]))

    cond do
      missing != [] -> {:error, {:missing_report_metrics, missing}}
      not is_number(latency["mean_ms"]) -> {:error, :missing_mean_latency}
      not is_number(latency["p95_ms"]) -> {:error, :missing_p95_latency}
      true -> :ok
    end
  end

  defp validate_metrics(_report), do: {:error, :missing_report_metrics}

  defp validate_markdown_metrics(report, markdown_path) do
    with {:ok, markdown} <- File.read(markdown_path) do
      f1 = report["metrics"]["f1"] |> :erlang.float_to_binary(decimals: 4)

      if String.contains?(markdown, "| F1 | #{f1} |") do
        :ok
      else
        {:error, {:markdown_metric_mismatch, :f1, f1}}
      end
    end
  end

  defp validate_dataset(%{"dataset" => %{"source" => source}}, _report_path)
       when is_binary(source) do
    if File.regular?(source), do: :ok, else: {:error, {:dataset_source_missing, source}}
  end

  defp validate_dataset(_report, report_path),
    do: {:error, {:missing_dataset_source, report_path}}

  defp validate_model_evidence(%Profile{required_assets: []}, _report, _opts), do: :ok

  defp validate_model_evidence(_descriptor, report, opts) do
    revisions = Keyword.get(opts, :model_revisions, %{})
    hashes = Keyword.get(opts, :asset_hashes, %{})

    cond do
      not non_empty_map?(report["model"]) ->
        {:error, :missing_report_model_metadata}

      not runtime_backend_recorded?(report["runtime_backend"]) ->
        {:error, :missing_actual_backend_metadata}

      not non_empty_string_map?(revisions) ->
        {:error, :missing_immutable_model_revisions}

      not non_empty_string_map?(hashes) ->
        {:error, :missing_model_asset_hashes}

      true ->
        :ok
    end
  end

  defp validate_output_fingerprint(
         %Profile{name: :openmed_pii},
         %{"metrics" => %{"output_fingerprint_sha256" => fingerprint}}
       )
       when is_binary(fingerprint) and byte_size(fingerprint) == 64,
       do: :ok

  defp validate_output_fingerprint(%Profile{name: :openmed_pii}, _report),
    do: {:error, :missing_accuracy_output_fingerprint}

  defp validate_output_fingerprint(_descriptor, _report), do: :ok

  defp validate_source_evidence(
         %Profile{name: :openmed_pii},
         %{
           "git_sha" => source_commit,
           "source" => %{
             "source_commit" => source_commit,
             "dirty_worktree" => false
           }
         }
       )
       when is_binary(source_commit) and source_commit != "",
       do: :ok

  defp validate_source_evidence(%Profile{name: :openmed_pii}, _report),
    do: {:error, :missing_clean_source_evidence}

  defp validate_source_evidence(_descriptor, _report), do: :ok

  defp load_repetitions(primary_path, primary_report, descriptor, opts) do
    paths = [primary_path | Keyword.get(opts, :repetition_reports, [])] |> Enum.uniq()

    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, runs} ->
      with {:ok, report, markdown_path} <- load_report_pair(path),
           :ok <- validate_report(report, path, markdown_path, descriptor, opts),
           :ok <- validate_repetition_contract(primary_report, report) do
        run = repetition_summary(report, path, markdown_path)
        {:cont, {:ok, runs ++ [run]}}
      else
        {:error, reason} -> {:halt, {:error, {:invalid_repetition_report, path, reason}}}
      end
    end)
  end

  defp load_external_repetitions(primary_path, primary_report, opts) do
    paths = [primary_path | Keyword.get(opts, :repetition_reports, [])] |> Enum.uniq()

    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, runs} ->
      with {:ok, report, markdown_path} <- load_report_pair(path),
           :ok <- validate_external_report(report, path, markdown_path),
           :ok <- validate_external_repetition_contract(primary_report, report) do
        {:cont, {:ok, runs ++ [external_repetition_summary(report, path, markdown_path)]}}
      else
        {:error, reason} -> {:halt, {:error, {:invalid_repetition_report, path, reason}}}
      end
    end)
  end

  defp require_external_repetitions([_, _ | _]), do: :ok
  defp require_external_repetitions(_runs), do: {:error, :insufficient_external_repetitions}

  defp validate_external_repetition_contract(primary, candidate) do
    contract = fn report ->
      %{
        adapter: report["adapter"],
        profile: report["profile"],
        dataset: Map.take(report["dataset"], ["name", "sha256", "sample_count"]),
        protocol: report["comparison_protocol"],
        metrics:
          Map.take(report["metrics"], [
            "precision",
            "recall",
            "f1",
            "f2",
            "true_positives",
            "false_positives",
            "false_negatives",
            "wrong_entity_type",
            "offset_mismatches",
            "unsupported_expected_spans",
            "output_fingerprint_sha256",
            "span_iou"
          ])
      }
    end

    if contract.(primary) == contract.(candidate),
      do: :ok,
      else: {:error, :external_repetition_contract_mismatch}
  end

  defp external_repetition_summary(report, report_path, markdown_path) do
    repetition_summary(report, report_path, markdown_path)
    |> Map.put("protocol", report["comparison_protocol"])
    |> Map.put("environment", report["environment"])
  end

  defp validate_repetition_contract(primary, candidate) do
    contract = fn report ->
      %{
        profile: report["profile"],
        requested_profile: report["requested_profile"],
        dataset: get_in(report, ["dataset", "name"]),
        template_split: get_in(report, ["dataset", "template_split", "name"]),
        metrics:
          Map.take(report["metrics"], [
            "precision",
            "recall",
            "f1",
            "f2",
            "true_positives",
            "false_positives",
            "false_negatives",
            "wrong_entity_type",
            "offset_mismatches",
            "unsupported_expected_spans",
            "output_fingerprint_sha256",
            "span_iou"
          ]),
        comparison_protocol: report["comparison_protocol"]
      }
    end

    if contract.(primary) == contract.(candidate),
      do: :ok,
      else: {:error, :repetition_contract_mismatch}
  end

  defp repetition_summary(report, report_path, markdown_path) do
    %{
      "generated_at" => file_timestamp(report_path),
      "source_report_timestamp" => report["timestamp"],
      "source_commit" => report["git_sha"],
      "json_sha256" => sha256(report_path),
      "markdown_sha256" => sha256(markdown_path),
      "metrics" => repetition_metrics(report["metrics"]),
      "latency" => report["latency"]
    }
  end

  defp repetition_metrics(metrics) do
    metrics
    |> Map.take([
      "precision",
      "recall",
      "f1",
      "f2",
      "true_positives",
      "false_positives",
      "false_negatives",
      "wrong_entity_type",
      "offset_mismatches",
      "unsupported_expected_spans",
      "output_fingerprint_sha256",
      "span_iou"
    ])
    |> Map.update("span_iou", %{}, &Map.drop(&1, ["examples"]))
  end

  defp validate_no_raw_values(report) do
    if safe_values?(report), do: :ok, else: {:error, :report_contains_raw_values}
  end

  defp safe_values?(value) when is_list(value), do: Enum.all?(value, &safe_values?/1)

  defp safe_values?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} ->
      if key in @sensitive_value_keys do
        nested in [nil, "[omitted]", "[redacted]"]
      else
        safe_values?(nested)
      end
    end)
  end

  defp safe_values?(_value), do: true

  defp build_entry(
         report,
         report_path,
         markdown_path,
         descriptor,
         reports_dir,
         repetitions,
         opts
       ) do
    dataset = report["dataset"]
    split = get_in(dataset, ["template_split", "name"]) || "all"
    basename = "#{descriptor.name}__#{dataset["name"]}__#{split}"
    json_destination = Path.join(reports_dir, basename <> ".json")
    markdown_destination = Path.join(reports_dir, basename <> ".md")
    json_body = authoritative_report_json(report)

    entry =
      %{
        "id" => "#{descriptor.name}:#{dataset["name"]}:#{split}",
        "status" => "authoritative",
        "stable_profile" => Atom.to_string(descriptor.name),
        "resolved_profile" => Atom.to_string(descriptor.implementation_profile),
        "source_commit" => get_in(report, ["source", "source_commit"]) || report["git_sha"],
        "dirty_worktree" => source_dirty_worktree(report),
        "generated_at" => file_timestamp(report_path),
        "source_report_timestamp" => report["timestamp"],
        "command" => Keyword.fetch!(opts, :command),
        "dataset" => dataset_metadata(dataset),
        "entity_policy" => entity_policy(report),
        "runtime" => runtime_metadata(report, opts),
        "models" => %{
          "report" => report["model"] || %{},
          "immutable_revisions" => stringify_map(Keyword.get(opts, :model_revisions, %{}))
        },
        "asset_hashes" => stringify_map(Keyword.get(opts, :asset_hashes, %{})),
        "dependencies" => report["dependencies"] || RuntimeMetadata.dependency_versions(),
        "environment" => environment_metadata(opts),
        "metrics" => selected_metrics(report),
        "repetitions" => %{
          "warmup" => Keyword.get(opts, :warmup, 0),
          "measured_runs" => length(repetitions),
          "concurrency" => Keyword.get(opts, :concurrency, 1),
          "runs" => repetitions
        },
        "limitations" => List.wrap(report["limitations"]) ++ Keyword.get(opts, :limitations, []),
        "files" => %{
          "json" =>
            relative_to_manifest(json_destination, Keyword.get(opts, :manifest_path, path())),
          "markdown" =>
            relative_to_manifest(markdown_destination, Keyword.get(opts, :manifest_path, path())),
          "json_sha256" => sha256_binary(json_body),
          "markdown_sha256" => markdown_path |> normalized_markdown() |> sha256_binary()
        }
      }
      |> maybe_put_protocol(report)

    {:ok, entry, %{json: json_destination, json_body: json_body, markdown: markdown_destination}}
  end

  defp maybe_put_protocol(entry, %{"comparison_protocol" => protocol})
       when is_map(protocol),
       do: Map.put(entry, "protocol", protocol)

  defp maybe_put_protocol(entry, _report), do: entry

  defp source_dirty_worktree(report) do
    case get_in(report, ["source", "dirty_worktree"]) do
      value when is_boolean(value) -> value
      _missing -> dirty_worktree?()
    end
  end

  defp build_external_entry(
         report,
         report_path,
         markdown_path,
         reports_dir,
         repetitions,
         opts
       ) do
    dataset = report["dataset"]
    split = get_in(dataset, ["template_split", "name"]) || "all"
    baseline_id = Keyword.get(opts, :baseline_id, "presidio_spacy_en_core_web_lg")
    protocol_id = get_in(report, ["comparison_protocol", "id"])
    basename = "external__#{baseline_id}__#{protocol_id}__#{dataset["name"]}__#{split}"
    json_destination = Path.join(reports_dir, basename <> ".json")
    markdown_destination = Path.join(reports_dir, basename <> ".md")
    json_body = external_report_json(report)

    entry = %{
      "id" => "external:#{baseline_id}:#{protocol_id}:#{dataset["name"]}:#{split}",
      "status" => "authoritative",
      "entry_type" => "external_baseline",
      "system" => "presidio",
      "adapter" => report["adapter"],
      "source_commit" => report["git_sha"] || git_sha(),
      "dirty_worktree" => dirty_worktree?(),
      "generated_at" => file_timestamp(report_path),
      "source_report_timestamp" => report["timestamp"],
      "command" => Keyword.get(opts, :command, report["command"]),
      "dataset" => external_dataset_metadata(dataset),
      "entity_policy" => report["entity_mapping"],
      "protocol" => report["comparison_protocol"],
      "runtime" => %{"backend" => report["runtime_backend"]},
      "models" => %{"report" => report["model"]},
      "asset_hashes" => report["artifacts"] || %{},
      "dependencies" => report["dependencies"],
      "environment" => report["environment"],
      "metrics" => external_selected_metrics(report),
      "repetitions" => %{
        "warmup" => Keyword.get(opts, :warmup, 1),
        "measured_runs" => length(repetitions),
        "concurrency" => Keyword.get(opts, :concurrency, 1),
        "runs" => repetitions
      },
      "limitations" => List.wrap(report["limitations"]) ++ Keyword.get(opts, :limitations, []),
      "files" => %{
        "json" =>
          relative_to_manifest(json_destination, Keyword.get(opts, :manifest_path, path())),
        "markdown" =>
          relative_to_manifest(markdown_destination, Keyword.get(opts, :manifest_path, path())),
        "json_sha256" => sha256_binary(json_body),
        "markdown_sha256" => markdown_path |> normalized_markdown() |> sha256_binary()
      }
    }

    {:ok, entry, %{json: json_destination, json_body: json_body, markdown: markdown_destination}}
  end

  defp external_dataset_metadata(dataset) do
    Map.take(dataset, [
      "name",
      "version",
      "sample_count",
      "source",
      "sha256",
      "sample_ids_sha256",
      "template_split",
      "requested_entities"
    ])
  end

  defp external_selected_metrics(report) do
    selected_metrics(report)
  end

  defp dataset_metadata(dataset) do
    source = dataset["source"]

    %{
      "name" => dataset["name"],
      "version" => dataset["version"],
      "sample_count" => dataset["sample_count"],
      "source" => source,
      "sha256" => sha256(source),
      "template_split" => dataset["template_split"],
      "requested_entities" => dataset["requested_entities"]
    }
  end

  defp selected_metrics(report) do
    metrics = report["metrics"]

    Map.take(metrics, [
      "precision",
      "recall",
      "f1",
      "f2",
      "true_positives",
      "false_positives",
      "false_negatives",
      "wrong_entity_type",
      "offset_mismatches",
      "unsupported_expected_spans",
      "output_fingerprint_sha256",
      "span_iou"
    ])
    |> Map.update("span_iou", %{}, &Map.drop(&1, ["examples"]))
    |> Map.put("latency", report["latency"])
    |> Map.put("per_entity", report["per_entity"] || %{})
  end

  defp entity_policy(report) do
    %{
      "mapping" => report["entity_mapping"] || %{},
      "requested_entities" => get_in(report, ["dataset", "requested_entities"]) || [],
      "unsupported_entity_counts" =>
        get_in(report, ["dataset", "unsupported_entity_counts"]) || %{}
    }
  end

  defp runtime_metadata(report, opts) do
    %{
      "backend" => report["runtime_backend"] || %{},
      "stage_latency" => report["stage_latency"] || %{},
      "compile" => %{
        "batch_size" => Keyword.get(opts, :compile_batch_size),
        "sequence_length" => Keyword.get(opts, :compile_sequence_length)
      }
    }
  end

  defp environment_metadata(opts) do
    %{
      "elixir" => System.version(),
      "otp" => to_string(:erlang.system_info(:otp_release)),
      "os" => inspect(:os.type()),
      "architecture" => to_string(:erlang.system_info(:system_architecture)),
      "schedulers" => :erlang.system_info(:schedulers_online),
      "hardware_label" => Keyword.get(opts, :hardware_label, "unspecified"),
      "os_version" => Keyword.get(opts, :os_version, "unspecified"),
      "cpu" => Keyword.get(opts, :cpu, "unspecified"),
      "memory_bytes" => Keyword.get(opts, :memory_bytes, "unspecified"),
      "accelerator" => Keyword.get(opts, :accelerator, "unspecified")
    }
  end

  defp copy_reports(markdown_source, destinations, opts) do
    force? = Keyword.get(opts, :force, false)

    with :ok <- File.mkdir_p(Path.dirname(destinations.json)),
         :ok <- ensure_destination_available(destinations.json, force?),
         :ok <- ensure_destination_available(destinations.markdown, force?),
         :ok <- File.write(destinations.json, destinations.json_body) do
      File.write(destinations.markdown, normalized_markdown(markdown_source))
    end
  end

  defp copy_external_reports(markdown_source, destinations, opts) do
    copy_reports(markdown_source, destinations, opts)
  end

  defp authoritative_report_json(report) do
    report
    |> Map.take(@authoritative_report_fields)
    |> Map.put("metrics", authoritative_metrics(report["metrics"] || %{}))
    |> Map.put("per_entity", report["per_entity"] || %{})
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp external_report_json(report) do
    report
    |> Map.take([
      "run_id",
      "phase",
      "status",
      "timestamp",
      "git_sha",
      "adapter",
      "profile",
      "external_baseline",
      "gold_derived",
      "model",
      "dependencies",
      "environment",
      "runtime_backend",
      "command",
      "dataset",
      "comparison_protocol",
      "entity_mapping",
      "offset_mode",
      "metrics",
      "per_entity",
      "latency",
      "limitations",
      "artifacts"
    ])
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp authoritative_metrics(metrics) do
    metrics
    |> Map.take(@authoritative_metric_fields)
    |> Map.update("span_iou", %{}, &Map.drop(&1, ["examples"]))
  end

  defp ensure_destination_available(path, false) do
    if File.exists?(path), do: {:error, {:authoritative_report_exists, path}}, else: :ok
  end

  defp ensure_destination_available(_path, true), do: :ok

  defp put_entry(manifest, entry, manifest_path) do
    reports = [entry | Enum.reject(manifest["reports"], &(&1["id"] == entry["id"]))]
    updated = Map.put(manifest, "reports", Enum.sort_by(reports, & &1["id"]))

    with :ok <- File.write(manifest_path, Jason.encode!(updated, pretty: true) <> "\n") do
      {:ok, entry}
    end
  end

  defp verify_entry_files(entry, manifest_path) do
    files = entry["files"]
    root = Path.dirname(manifest_path)
    json = Path.expand(files["json"], root)
    markdown = Path.expand(files["markdown"], root)

    cond do
      not File.regular?(json) -> {:error, {:missing_authoritative_report, json}}
      not File.regular?(markdown) -> {:error, {:missing_authoritative_report, markdown}}
      sha256(json) != files["json_sha256"] -> {:error, {:report_hash_mismatch, json}}
      sha256(markdown) != files["markdown_sha256"] -> {:error, {:report_hash_mismatch, markdown}}
      true -> :ok
    end
  end

  defp verify_entries(reports, manifest_path) do
    Enum.reduce_while(reports, :ok, &verify_entry(&1, &2, manifest_path))
  end

  defp verify_entry(entry, :ok, manifest_path) do
    case verify_entry_files(entry, manifest_path) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp validate_unique_ids(reports) do
    ids = Enum.map(reports, & &1["id"])
    if ids == Enum.uniq(ids), do: :ok, else: {:error, :duplicate_authoritative_report_ids}
  end

  defp validate_entries(reports) do
    Enum.find_value(reports, :ok, fn entry ->
      required =
        if entry["entry_type"] == "external_baseline",
          do: @required_external_entry_fields,
          else: @required_entry_fields

      case Enum.reject(required, &Map.has_key?(entry, &1)) do
        [] -> false
        missing -> {:error, {:missing_authoritative_entry_fields, entry["id"], missing}}
      end
    end)
  end

  defp non_empty_string_map?(map) when is_map(map) and map_size(map) > 0 do
    Enum.all?(map, fn {key, value} ->
      (is_atom(key) or is_binary(key)) and is_binary(value) and value != ""
    end)
  end

  defp non_empty_string_map?(_map), do: false

  defp non_empty_map?(map), do: is_map(map) and map_size(map) > 0

  defp present?(value), do: is_binary(value) and value not in ["", "unknown", "unspecified"]

  defp sha256?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp runtime_backend_recorded?(runtime) when is_map(runtime) do
    runtime
    |> nested_keys()
    |> Enum.any?(&(&1 in ["serving_backend", "actual_backend"]))
  end

  defp runtime_backend_recorded?(_runtime), do: false

  defp nested_keys(value) when is_map(value) do
    Enum.flat_map(value, fn {key, nested_value} ->
      [to_string(key) | nested_keys(nested_value)]
    end)
  end

  defp nested_keys(value) when is_list(value), do: Enum.flat_map(value, &nested_keys/1)
  defp nested_keys(_value), do: []

  defp stringify_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp relative_to_manifest(path, manifest_path) do
    Path.relative_to(path, Path.dirname(manifest_path))
  end

  defp sha256(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp sha256_binary(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end

  defp normalized_markdown(path) do
    path
    |> File.read!()
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  defp file_timestamp(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} ->
        stat.mtime
        |> DateTime.from_unix!()
        |> DateTime.to_iso8601()

      _error ->
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
    end
  end

  defp git_sha do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _other -> "unknown"
    end
  end

  defp dirty_worktree? do
    case System.cmd("git", ["status", "--porcelain", "--untracked-files=no"],
           stderr_to_stdout: true
         ) do
      {"", 0} -> false
      {_output, 0} -> true
      _other -> true
    end
  end
end
