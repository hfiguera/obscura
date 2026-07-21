defmodule Obscura.PrivacyFilter.SequenceLabelingTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.SequenceLabeling
  alias Obscura.PrivacyFilter.SequenceLabeling.Aggregation
  alias Obscura.PrivacyFilter.SequenceLabeling.TokenizedExample

  test "example_to_windows preserves unpadded default window behavior" do
    example = example([1, 2, 3], [0, 0, 0])

    assert {:ok, [first, second]} = SequenceLabeling.example_to_windows(example, 2)

    assert first.tokens == {1, 2}
    assert first.mask == {1, 1}
    assert first.offsets == {0, 1}

    assert second.tokens == {3}
    assert second.mask == {1}
    assert second.offsets == {2}
  end

  test "example_to_windows can pad fixed-size windows with masks" do
    example = example([1, 2, 3], [0, 4, 0])

    assert {:ok, [first, second]} =
             SequenceLabeling.example_to_windows(example, 2, pad_token_id: 99, pad_label: 0)

    assert first.tokens == {1, 2}
    assert first.labels == {0, 4}
    assert first.mask == {1, 1}
    assert first.offsets == {0, 1}
    assert first.token_example_ids == {"example-1", "example-1"}

    assert second.tokens == {3, 99}
    assert second.labels == {0, 0}
    assert second.mask == {1, 0}
    assert second.offsets == {2, nil}
    assert second.token_example_ids == {"example-1", nil}
  end

  test "example_to_bucketed_windows selects the smallest fitting bucket" do
    example = example(Enum.to_list(1..11), List.duplicate(0, 11))

    assert {:ok, [first, second]} =
             SequenceLabeling.example_to_bucketed_windows(example, [4, 8],
               pad_token_id: 99,
               pad_label: 0
             )

    assert tuple_size(first.tokens) == 8
    assert first.tokens == List.to_tuple(Enum.to_list(1..8))
    assert first.mask == List.duplicate(1, 8) |> List.to_tuple()

    assert second.tokens == {9, 10, 11, 99}
    assert second.mask == {1, 1, 1, 0}
    assert second.offsets == {8, 9, 10, nil}
  end

  test "example_to_bucketed_windows rejects invalid policies and missing padding" do
    example = example([1, 2], [0, 0])

    assert {:error, :invalid_sequence_length_buckets} =
             SequenceLabeling.example_to_bucketed_windows(example, [4, 2], pad_token_id: 99)

    assert {:error, :invalid_sequence_length_buckets} =
             SequenceLabeling.example_to_bucketed_windows(example, [2, 2], pad_token_id: 99)

    assert {:error, :missing_bucket_pad_token_id} =
             SequenceLabeling.example_to_bucketed_windows(example, [2, 4])
  end

  test "inspection hides text, identifiers, token IDs, labels, and logits" do
    canary = "privacy-filter-canary-93871"

    example = %TokenizedExample{
      example([101, 93_871], [0, 1])
      | text: canary,
        example_id: canary
    }

    assert {:ok, [window]} = SequenceLabeling.example_to_windows(example, 2)

    aggregation = %Aggregation{
      logprob_logsumexp: [[93_871.0]],
      labels: [93_871],
      token_ids: [93_871],
      length: 1
    }

    for value <- [example, window, aggregation] do
      rendered = inspect(value)
      refute rendered =~ canary
      refute rendered =~ "93871"
    end
  end

  defp example(tokens, labels) do
    %TokenizedExample{
      tokens: List.to_tuple(tokens),
      labels: List.to_tuple(labels),
      example_id: "example-1",
      text: "text"
    }
  end
end
