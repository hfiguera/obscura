defmodule Obscura.Eval.Operational.DatasetTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.Dataset

  test "loads the exact authoritative generated_large heldout order" do
    assert {:ok, dataset} = Dataset.load(:generated_large_template_heldout)
    locked = get_in(dataset.selection, ["dataset", "ordered_sample_ids"])

    assert Enum.map(dataset.samples, & &1.id) == locked
    assert Enum.count(dataset.samples) == 648
    assert byte_size(dataset.selection_sha256) == 64
  end

  test "rejects unknown datasets without creating atoms" do
    assert {:error, {:unknown_operational_dataset, "not-a-dataset"}} =
             Dataset.selection_path("not-a-dataset")
  end
end
