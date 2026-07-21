defmodule Obscura.Eval.Operational.Dataset do
  @moduledoc """
  Loads the exact sample order locked by an authoritative selection.
  """

  alias Obscura.Eval.PresidioResearchLoader

  @selection_root "eval/authoritative/selections"
  @selections %{
    generated_large_template_heldout: "generated_large_template_heldout.json",
    synth_dataset_v2_all: "synth_dataset_v2_all.json",
    nemotron_pii_test_subset_all: "nemotron_pii_test_subset_all.json"
  }

  @type name ::
          :generated_large_template_heldout
          | :synth_dataset_v2_all
          | :nemotron_pii_test_subset_all

  @spec names() :: [name()]
  def names, do: @selections |> Map.keys() |> Enum.sort()

  @spec load(name(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(name, opts \\ []) do
    with {:ok, selection_path} <- selection_path(name),
         {:ok, selection_binary} <- File.read(selection_path),
         {:ok, selection} <- Jason.decode(selection_binary),
         {:ok, dataset} <- dataset_atom(get_in(selection, ["dataset", "name"])),
         split <- split_atom(get_in(selection, ["dataset", "template_split", "name"])),
         ratio <- get_in(selection, ["dataset", "template_split", "train_ratio"]) || 0.7,
         {:ok, loaded} <-
           PresidioResearchLoader.load(
             dataset: dataset,
             profile: Keyword.get(opts, :profile, :regex_only),
             invalid_span: :drop_sample,
             template_split: split,
             template_train_ratio: ratio
           ),
         :ok <- validate_loaded(loaded, selection),
         {:ok, samples} <- order_samples(loaded.samples, selection) do
      {:ok,
       %{
         name: name,
         dataset: dataset,
         samples: samples,
         selection: selection,
         selection_path: selection_path,
         selection_sha256: sha256(selection_binary)
       }}
    end
  end

  @spec selection_path(name()) :: {:ok, Path.t()} | {:error, term()}
  def selection_path(name) do
    case Map.fetch(@selections, name) do
      {:ok, filename} -> {:ok, Path.join(@selection_root, filename)}
      :error -> {:error, {:unknown_operational_dataset, name}}
    end
  end

  defp validate_loaded(loaded, selection) do
    expected = selection["dataset"]

    cond do
      loaded.sha256 != expected["sha256"] ->
        {:error, :operational_dataset_sha256_mismatch}

      length(loaded.samples) != expected["sample_count"] ->
        {:error, :operational_dataset_sample_count_mismatch}

      true ->
        :ok
    end
  end

  defp order_samples(samples, selection) do
    by_id = Map.new(samples, &{&1.id, &1})
    ids = get_in(selection, ["dataset", "ordered_sample_ids"])

    ordered = Enum.map(ids, &Map.get(by_id, &1))

    if Enum.any?(ordered, &is_nil/1) do
      {:error, :operational_dataset_sample_ids_mismatch}
    else
      actual_hash = canonical_sha256(ids)
      expected_hash = get_in(selection, ["dataset", "sample_ids_sha256"])

      if actual_hash == expected_hash,
        do: {:ok, ordered},
        else: {:error, :operational_dataset_sample_ids_sha256_mismatch}
    end
  end

  defp dataset_atom(value) when is_binary(value) do
    case Enum.find(PresidioResearchLoader.known_datasets(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, {:unknown_operational_dataset, value}}
      dataset -> {:ok, dataset}
    end
  end

  defp split_atom("template_heldout"), do: :template_heldout
  defp split_atom("template_train"), do: :template_train
  defp split_atom(_value), do: :all

  defp canonical_sha256(term) do
    term
    |> Jason.encode!()
    |> sha256()
  end

  defp sha256(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end
end
