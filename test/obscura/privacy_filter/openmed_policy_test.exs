defmodule Obscura.PrivacyFilter.OpenMedPolicyTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.OpenMedPolicy
  alias Obscura.PrivacyFilter.Serving

  test "locks the measured OpenMed default policy" do
    assert OpenMedPolicy.effective_options() == [
             decoder: :viterbi,
             sequence_length_buckets: [192, 256, 384, 512, 768],
             sequence_length_bucket_threshold: 129,
             logprob_conversion: :raw_logits
           ]

    assert %{
             id: "openmed_latency_v1",
             decoder: :viterbi,
             sequence_length_buckets: [192, 256, 384, 512, 768],
             sequence_length_bucket_threshold: 129,
             logprob_conversion: :raw_logits,
             min_span_logprob: nil,
             matches_default: true,
             default_policy_sha256: fingerprint
           } = OpenMedPolicy.default_metadata()

    assert byte_size(fingerprint) == 64
  end

  test "selects the reference conversion when decoding needs probabilities" do
    assert OpenMedPolicy.effective_options(privacy_filter_decoder: :argmax)[
             :logprob_conversion
           ] == :reference

    assert OpenMedPolicy.effective_options(privacy_filter_min_span_logprob: -0.5)[
             :logprob_conversion
           ] == :reference
  end

  test "supports an explicit disabled bucket policy for controlled comparisons" do
    assert OpenMedPolicy.effective_options(privacy_filter_sequence_length_buckets: :disabled)[
             :sequence_length_buckets
           ] == nil
  end

  test "reports whether an effective serving matches the default" do
    defaults = OpenMedPolicy.default_metadata()

    serving = %Serving{
      config: %{},
      label_info: %{},
      decoder: :viterbi,
      sequence_length_buckets: [192, 256, 384, 512, 768],
      sequence_length_bucket_threshold: 129,
      logprob_conversion: :raw_logits,
      min_span_logprob: nil
    }

    assert OpenMedPolicy.metadata(serving) == defaults

    refute serving
           |> Map.put(:sequence_length_bucket_threshold, 128)
           |> OpenMedPolicy.metadata()
           |> Map.fetch!(:matches_default)
  end

  test "documented defaults cannot drift from runtime defaults" do
    document = File.read!("docs/openmed-sequence-bucketing-logprob-report.md")

    assert document =~ "Policy ID | `#{OpenMedPolicy.id()}`"
    assert document =~ "Sequence-length buckets | `#{inspect(OpenMedPolicy.default_buckets())}`"

    assert document =~
             "Activation threshold | `#{OpenMedPolicy.default_bucket_threshold()}` tokens"

    assert document =~ "Log-probability conversion | `:raw_logits`"
  end
end
