defmodule Obscura.Eval.PresidioResearchLoader do
  @moduledoc """
  Loads the committed Presidio-Research benchmark snapshots into neutral Obscura samples.
  """

  alias Obscura.Eval.EntityMapping
  alias Obscura.Eval.Offset
  alias Obscura.Eval.Profile

  @default_dataset :synth_dataset_v2
  @dataset_root "eval/datasets/presidio_research"
  @snapshot_version "presidio-research@2e9741154a3857712307b776cc2cd5f13c95c34b"
  @default_path Path.join(@dataset_root, "synth_dataset_v2.json")
  @datasets %{
    synth_dataset_v2: %{
      name: "synth_dataset_v2",
      path: @default_path,
      version: @snapshot_version,
      sha256: "ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012",
      source_id: "presidio-research:synth_dataset_v2"
    },
    generated_small: %{
      name: "generated_small",
      path: Path.join(@dataset_root, "generated_small.json"),
      version: @snapshot_version,
      sha256: "b40cfe75e5f0799b1c8054d91cbaafd92a7a34b425c1416cdf70ad5ff961fb5d",
      source_id: "presidio-research:tests/data/generated_small"
    },
    generated_large: %{
      name: "generated_large",
      path: Path.join(@dataset_root, "generated_large.json"),
      version: @snapshot_version,
      sha256: "b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26",
      source_id: "presidio-research:tests/data/generated_large"
    },
    mock_input_samples: %{
      name: "mock_input_samples",
      path: Path.join(@dataset_root, "mock_input_samples.json"),
      version: @snapshot_version,
      sha256: "3b039c471ce9ec6c5372ba27108dde21af33cab88e8d9ce70bc957dbaa4e5ac6",
      source_id: "presidio-research:tests/data/mock_input_samples"
    },
    nemotron_pii_test_subset: %{
      name: "nemotron_pii_test_subset",
      path: ".cache/obscura-research/datasets/nvidia-Nemotron-PII/nemotron_pii_test_subset.json",
      version: "nvidia-nemotron-pii-test-subset",
      source_id: "huggingface:nvidia/Nemotron-PII:test"
    }
  }
  @expected_entity_counts %{
    "PERSON" => 857,
    "STREET_ADDRESS" => 598,
    "GPE" => 411,
    "ORGANIZATION" => 250,
    "CREDIT_CARD" => 136,
    "DATE_TIME" => 119,
    "TITLE" => 92,
    "PHONE_NUMBER" => 92,
    "AGE" => 74,
    "NRP" => 55,
    "EMAIL_ADDRESS" => 49,
    "ZIP_CODE" => 37,
    "DOMAIN_NAME" => 37,
    "IBAN_CODE" => 21,
    "US_SSN" => 16,
    "IP_ADDRESS" => 14,
    "US_DRIVER_LICENSE" => 5
  }

  @doc """
  Returns the default committed dataset path.
  """
  @spec default_path() :: Path.t()
  def default_path, do: @default_path

  @doc """
  Returns known Presidio-Research datasets that can be loaded without Python.
  """
  @spec known_datasets() :: [atom()]
  def known_datasets do
    @datasets
    |> Enum.map(fn {name, _config} -> name end)
    |> Enum.sort()
  end

  @doc """
  Returns the path for a known Presidio-Research dataset.
  """
  @spec path_for(atom() | String.t()) :: {:ok, Path.t()} | {:error, term()}
  def path_for(dataset) do
    with {:ok, metadata} <- dataset_metadata(dataset) do
      {:ok, metadata.path}
    end
  end

  @doc """
  Returns expected entity counts for `synth_dataset_v2.json`.
  """
  @spec expected_entity_counts() :: map()
  def expected_entity_counts, do: @expected_entity_counts

  @doc """
  Loads a benchmark dataset and verifies committed snapshots by default.
  """
  @spec load(keyword()) :: {:ok, map()} | {:error, term()}
  def load(opts \\ []) do
    dataset = Keyword.get(opts, :dataset, @default_dataset)
    profile = Keyword.get(opts, :profile, :regex_only)
    invalid_span = Keyword.get(opts, :invalid_span, :error)
    template_split = Keyword.get(opts, :template_split, :all)
    train_ratio = Keyword.get(opts, :template_train_ratio, 0.7)

    with {:ok, metadata} <- dataset_metadata(dataset),
         path <- Keyword.get(opts, :path, metadata.path),
         {:ok, binary} <- read_dataset(path),
         sha256 <- sha256(binary),
         :ok <- verify_snapshot(path, binary, metadata, opts),
         {:ok, decoded} <- Jason.decode(binary),
         {:ok, decoded_samples} <- parse_samples(decoded),
         samples <- normalize_samples(decoded_samples, metadata.source_id),
         {:ok, samples, invalid_samples} <- validate_samples(samples, invalid_span),
         {:ok, split_metadata} <- template_split(samples, template_split, train_ratio),
         samples <- split_metadata.samples,
         counts <- entity_counts(samples),
         support <- support_summary(samples, profile) do
      {:ok,
       %{
         name: metadata.name,
         source: path,
         version: metadata.version,
         sha256: sha256,
         sample_count: length(samples),
         original_sample_count: length(decoded_samples),
         invalid_sample_count: length(invalid_samples),
         invalid_samples: invalid_samples,
         samples: samples,
         entity_counts: counts,
         supported_entity_counts: support.supported_counts,
         unsupported_entity_counts: support.unsupported_counts,
         template_split: Map.delete(split_metadata, :samples)
       }}
    end
  end

  @doc """
  Builds a deterministic smoke subset.
  """
  @spec smoke_subset([map()], atom(), non_neg_integer()) :: [map()]
  def smoke_subset(samples, profile, limit \\ 25) do
    samples
    |> Enum.filter(fn sample ->
      sample.spans
      |> Profile.split_spans(profile)
      |> Map.fetch!(:supported)
      |> Enum.any?()
    end)
    |> Enum.sort_by(& &1.id)
    |> Enum.take(limit)
  end

  defp read_dataset(path) do
    case File.read(path) do
      {:ok, binary} ->
        {:ok, binary}

      {:error, reason} ->
        {:error, {:missing_presidio_research_dataset, path, reason}}
    end
  end

  defp verify_snapshot(path, binary, metadata, opts) do
    verify? = Keyword.get(opts, :verify_checksum, path == metadata.path)

    if verify? and Map.has_key?(metadata, :sha256) do
      actual = sha256(binary)

      if actual == metadata.sha256 do
        :ok
      else
        {:error, {:presidio_research_checksum_mismatch, path, metadata.sha256, actual}}
      end
    else
      :ok
    end
  end

  defp sha256(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end

  defp parse_samples(decoded) when is_list(decoded), do: {:ok, decoded}
  defp parse_samples(%{"samples" => samples}) when is_list(samples), do: {:ok, samples}
  defp parse_samples(%{"data" => samples}) when is_list(samples), do: {:ok, samples}
  defp parse_samples(other), do: {:error, {:unsupported_dataset_shape, shape(other)}}

  defp dataset_metadata(dataset) when is_binary(dataset) do
    dataset
    |> String.to_existing_atom()
    |> dataset_metadata()
  rescue
    ArgumentError -> {:error, {:unknown_presidio_research_dataset, dataset}}
  end

  defp dataset_metadata(dataset) when is_atom(dataset) do
    case Map.fetch(@datasets, dataset) do
      {:ok, metadata} -> {:ok, metadata}
      :error -> {:error, {:unknown_presidio_research_dataset, dataset}}
    end
  end

  defp normalize_samples(samples, source_id) do
    samples
    |> Enum.with_index()
    |> Enum.map(fn {sample, index} -> normalize_sample(sample, index, source_id) end)
  end

  defp validate_samples(samples, :error) do
    Enum.reduce_while(samples, :ok, fn sample, :ok ->
      case validate_sample_spans(sample) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:invalid_presidio_research_sample, sample.id, reason}}}
      end
    end)
    |> case do
      :ok -> {:ok, samples, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_samples(samples, :drop_sample) do
    samples
    |> Enum.reduce({[], []}, fn sample, {valid, invalid} ->
      case validate_sample_spans(sample) do
        :ok -> {[sample | valid], invalid}
        {:error, reason} -> {valid, [%{id: sample.id, reason: reason} | invalid]}
      end
    end)
    |> then(fn {valid, invalid} ->
      {:ok, Enum.reverse(valid), Enum.reverse(invalid)}
    end)
  end

  defp validate_samples(_samples, policy), do: {:error, {:unknown_invalid_span_policy, policy}}

  defp validate_sample_spans(sample) do
    Enum.reduce_while(sample.spans, :ok, fn span, :ok ->
      case Offset.validate_span(sample.text, span) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_sample(sample, index, source_id) when is_map(sample) do
    text = first_present(sample, ["full_text", "text", "sentence", "content"], "")
    spans = first_present(sample, ["spans", "entities", "tags"], [])
    id = first_present(sample, ["id", "sample_id"], index)

    %{
      id: id,
      text: text,
      source: source_id,
      template_id: first_present(sample, ["template_id"], nil),
      metadata: first_present(sample, ["metadata"], %{}) || %{},
      spans: Enum.map(spans, &normalize_span(text, &1))
    }
  end

  defp normalize_span(text, span) when is_map(span) do
    source_entity = first_present(span, ["entity_type", "entity", "label"], nil)
    value = first_present(span, ["entity_value", "value", "text"], nil)
    char_start = first_present(span, ["start_position", "start", "char_start"], nil)
    char_end = first_present(span, ["end_position", "end", "char_end"], nil)
    {byte_start, byte_end} = byte_offsets_from_chars(text, char_start, char_end)

    %{
      entity: obscura_entity(source_entity),
      byte_start: byte_start,
      byte_end: byte_end,
      char_start: char_start,
      char_end: char_end,
      value: value,
      source_entity: source_entity,
      metadata: %{}
    }
  end

  defp template_split(samples, :all, _train_ratio) do
    {:ok,
     %{
       name: :all,
       strategy: :all,
       train_ratio: nil,
       template_count: template_count(samples),
       selected_template_count: template_count(samples),
       heldout_template_count: 0,
       selected_template_ids: template_ids(samples),
       train_template_ids: [],
       heldout_template_ids: [],
       samples: samples
     }}
  end

  defp template_split(samples, split, train_ratio)
       when split in [:template_train, :template_heldout] do
    with :ok <- validate_train_ratio(train_ratio),
         template_ids <- template_ids(samples),
         {train_template_ids, heldout_template_ids} <-
           split_template_ids(template_ids, train_ratio),
         selected_template_ids <-
           if(split == :template_train, do: train_template_ids, else: heldout_template_ids),
         selected_template_set <- MapSet.new(selected_template_ids),
         selected_samples <-
           Enum.filter(samples, &MapSet.member?(selected_template_set, &1.template_id)) do
      {:ok,
       %{
         name: split,
         strategy: :template_id,
         train_ratio: train_ratio,
         template_count: length(template_ids),
         selected_template_count: length(selected_template_ids),
         heldout_template_count: length(heldout_template_ids),
         selected_template_ids: selected_template_ids,
         train_template_ids: train_template_ids,
         heldout_template_ids: heldout_template_ids,
         samples: selected_samples
       }}
    end
  end

  defp template_split(_samples, split, _train_ratio),
    do: {:error, {:unknown_template_split, split}}

  defp validate_train_ratio(train_ratio)
       when is_number(train_ratio) and train_ratio > 0.0 and train_ratio < 1.0,
       do: :ok

  defp validate_train_ratio(train_ratio),
    do: {:error, {:invalid_template_train_ratio, train_ratio}}

  defp split_template_ids(template_ids, train_ratio) do
    train_count =
      template_ids
      |> length()
      |> Kernel.*(train_ratio)
      |> Float.floor()
      |> trunc()
      |> max(1)
      |> min(max(length(template_ids) - 1, 1))

    Enum.split(template_ids, train_count)
  end

  defp template_ids(samples) do
    samples
    |> Enum.map(& &1.template_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp template_count(samples), do: samples |> template_ids() |> length()

  defp first_present(map, keys, default) do
    Enum.find_value(keys, default, &Map.get(map, &1))
  end

  defp obscura_entity(source_entity) do
    case EntityMapping.to_obscura(source_entity) do
      {:ok, obscura_entity} -> obscura_entity
      {:error, _reason} -> :unknown
    end
  end

  defp byte_offsets_from_chars(text, char_start, char_end)
       when is_integer(char_start) and is_integer(char_end) do
    with {:ok, byte_start} <- Offset.char_to_byte(text, char_start),
         {:ok, byte_end} <- Offset.char_to_byte(text, char_end) do
      {byte_start, byte_end}
    else
      {:error, _reason} -> {0, 0}
    end
  end

  defp byte_offsets_from_chars(_text, _char_start, _char_end), do: {0, 0}

  defp entity_counts(samples) do
    samples
    |> Enum.flat_map(& &1.spans)
    |> Enum.map(& &1.source_entity)
    |> Enum.frequencies()
  end

  defp support_summary(samples, profile) do
    spans = Enum.flat_map(samples, & &1.spans)
    split = Profile.split_spans(spans, profile)

    %{
      supported_counts: Enum.frequencies_by(split.supported, & &1.source_entity),
      unsupported_counts: Enum.frequencies_by(split.unsupported, & &1.source_entity)
    }
  end

  defp shape(value) when is_map(value), do: {:map, Map.keys(value)}
  defp shape(value), do: value
end
