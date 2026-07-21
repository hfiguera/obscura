defmodule Obscura.Eval.PresidioResearchLoaderTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.PresidioResearchLoader

  test "reports a deterministic missing-file error" do
    path = "eval/datasets/presidio_research/does_not_exist.json"

    assert {:error, {:missing_presidio_research_dataset, ^path, :enoent}} =
             PresidioResearchLoader.load(path: path)
  end

  test "rejects a checksum mismatch when snapshot verification is requested" do
    path =
      Path.join(System.tmp_dir!(), "obscura-modified-#{System.unique_integer([:positive])}.json")

    File.write!(path, "[]\n")
    on_exit(fn -> File.rm(path) end)

    expected = "ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012"

    assert {:error, {:presidio_research_checksum_mismatch, ^path, ^expected, actual}} =
             PresidioResearchLoader.load(path: path, verify_checksum: true)

    refute actual == expected
  end

  test "committed snapshot files match their pinned fingerprints" do
    fingerprints = %{
      synth_dataset_v2: "ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012",
      generated_small: "b40cfe75e5f0799b1c8054d91cbaafd92a7a34b425c1416cdf70ad5ff961fb5d",
      generated_large: "b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26",
      mock_input_samples: "3b039c471ce9ec6c5372ba27108dde21af33cab88e8d9ce70bc957dbaa4e5ac6"
    }

    Enum.each(fingerprints, fn {dataset, expected} ->
      assert {:ok, path} = PresidioResearchLoader.path_for(dataset)
      assert {:ok, binary} = File.read(path)

      actual =
        :crypto.hash(:sha256, binary)
        |> Base.encode16(case: :lower)

      assert actual == expected
    end)
  end

  test "loads and verifies the committed synth_dataset_v2 snapshot" do
    path = PresidioResearchLoader.default_path()

    assert {:ok, dataset} = PresidioResearchLoader.load(path: path, profile: :regex_only)
    assert dataset.name == "synth_dataset_v2"
    assert dataset.sample_count == 1500
    assert dataset.sha256 == "ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012"
    assert dataset.entity_counts == PresidioResearchLoader.expected_entity_counts()
    assert Enum.any?(dataset.samples)

    subset = PresidioResearchLoader.smoke_subset(dataset.samples, :regex_only, 5)
    assert match?([_, _, _, _, _], subset)
    assert Enum.all?(subset, fn sample -> Enum.any?(sample.spans) end)
  end

  test "loads and verifies the committed generated_small snapshot" do
    assert :generated_small in PresidioResearchLoader.known_datasets()
    assert {:ok, path} = PresidioResearchLoader.path_for(:generated_small)

    assert {:error, {:invalid_presidio_research_sample, _id, _reason}} =
             PresidioResearchLoader.load(dataset: :generated_small, profile: :regex_only)

    assert {:ok, dataset} =
             PresidioResearchLoader.load(
               dataset: :generated_small,
               profile: :regex_only,
               invalid_span: :drop_sample
             )

    assert dataset.name == "generated_small"
    assert dataset.original_sample_count == 100
    assert dataset.sample_count < dataset.original_sample_count
    assert dataset.invalid_sample_count > 0
    assert dataset.source == path
    assert dataset.sha256 == "b40cfe75e5f0799b1c8054d91cbaafd92a7a34b425c1416cdf70ad5ff961fb5d"
    assert dataset.entity_counts["PERSON"] >= 1

    sample = hd(dataset.samples)
    assert sample.source == "presidio-research:tests/data/generated_small"
    assert is_integer(sample.template_id)
    assert is_map(sample.metadata)
    assert Enum.all?(sample.spans, &is_integer(&1.byte_start))
  end

  test "loads converted Nemotron-PII test subset when present" do
    assert :nemotron_pii_test_subset in PresidioResearchLoader.known_datasets()
    assert {:ok, path} = PresidioResearchLoader.path_for(:nemotron_pii_test_subset)

    if File.exists?(path) do
      assert {:ok, dataset} =
               PresidioResearchLoader.load(
                 dataset: :nemotron_pii_test_subset,
                 profile: :deterministic_plus
               )

      assert dataset.name == "nemotron_pii_test_subset"
      assert dataset.sample_count == 500
      assert dataset.source == path
      assert dataset.version == "nvidia-nemotron-pii-test-subset"
      assert dataset.entity_counts["first_name"] >= 1
      assert dataset.entity_counts["street_address"] >= 1
      assert dataset.supported_entity_counts["first_name"] >= 1
      assert dataset.unsupported_entity_counts["company_name"] >= 1

      sample = hd(dataset.samples)
      assert sample.source == "huggingface:nvidia/Nemotron-PII:test"
      assert is_binary(sample.id)
      assert is_binary(sample.template_id)
      assert sample.metadata["domain"]
      assert Enum.all?(sample.spans, &is_integer(&1.byte_start))
    else
      assert {:error, {:missing_presidio_research_dataset, ^path, :enoent}} =
               PresidioResearchLoader.load(
                 dataset: :nemotron_pii_test_subset,
                 profile: :deterministic_plus
               )
    end
  end

  test "reports unknown Presidio-Research dataset aliases deterministically" do
    assert {:error, {:unknown_presidio_research_dataset, :unknown}} =
             PresidioResearchLoader.load(dataset: :unknown)
  end

  test "can split Presidio-Research datasets by template for heldout evaluation" do
    assert {:ok, _path} = PresidioResearchLoader.path_for(:generated_small)

    assert {:ok, train} =
             PresidioResearchLoader.load(
               dataset: :generated_small,
               profile: :deterministic_plus,
               invalid_span: :drop_sample,
               template_split: :template_train,
               template_train_ratio: 0.7
             )

    assert {:ok, heldout} =
             PresidioResearchLoader.load(
               dataset: :generated_small,
               profile: :deterministic_plus,
               invalid_span: :drop_sample,
               template_split: :template_heldout,
               template_train_ratio: 0.7
             )

    train_templates = MapSet.new(train.template_split.selected_template_ids)
    heldout_templates = MapSet.new(heldout.template_split.selected_template_ids)

    assert train.template_split.name == :template_train
    assert heldout.template_split.name == :template_heldout
    assert train.template_split.strategy == :template_id
    assert MapSet.disjoint?(train_templates, heldout_templates)

    assert train.sample_count + heldout.sample_count ==
             train.original_sample_count - train.invalid_sample_count

    assert heldout.sample_count > 0
  end
end
