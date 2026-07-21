defmodule Obscura.PrivacyFilter.LogprobsTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Logprobs

  test "raw-logit conversion preserves Viterbi paths" do
    logits =
      Nx.tensor([
        [
          [1.0, -2.0, 3.5],
          [-10.0, 0.25, 0.5],
          [100.0, 100.0, 99.0]
        ]
      ])

    assert {:ok, raw_rows} = Logprobs.to_rows(logits, :raw_logits)
    assert {:ok, reference_rows} = Logprobs.to_rows(logits, :reference)

    assert best_path(raw_rows) == best_path(reference_rows)
  end

  test "conversion modes reject invalid tensor shapes" do
    for mode <- [:reference, :raw_logits] do
      assert {:error, {:privacy_filter_logits_shape_mismatch, {1, 3}}} =
               Logprobs.to_rows(Nx.tensor([[1.0, 2.0, 3.0]]), mode)
    end
  end

  defp best_path(rows),
    do: Enum.map(rows, &Enum.find_index(&1, fn value -> value == Enum.max(&1) end))
end
