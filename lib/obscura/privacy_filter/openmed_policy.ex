defmodule Obscura.PrivacyFilter.OpenMedPolicy do
  @moduledoc false

  alias Obscura.PrivacyFilter.Serving

  @id "openmed_latency_v1"
  @sequence_length_buckets [192, 256, 384, 512, 768]
  @sequence_length_bucket_threshold 129

  @spec id() :: String.t()
  def id, do: @id

  @spec default_buckets() :: [pos_integer()]
  def default_buckets, do: @sequence_length_buckets

  @spec default_bucket_threshold() :: pos_integer()
  def default_bucket_threshold, do: @sequence_length_bucket_threshold

  @spec effective_options(keyword()) :: keyword()
  def effective_options(opts \\ []) when is_list(opts) do
    decoder = option(opts, [:decoder, :privacy_filter_decoder], :viterbi)
    min_span_logprob = option(opts, [:min_span_logprob, :privacy_filter_min_span_logprob], nil)

    buckets =
      option(
        opts,
        [:sequence_length_buckets, :privacy_filter_sequence_length_buckets],
        @sequence_length_buckets
      )
      |> normalize_buckets()

    bucket_threshold =
      option(
        opts,
        [:sequence_length_bucket_threshold, :privacy_filter_sequence_length_bucket_threshold],
        if(is_list(buckets), do: @sequence_length_bucket_threshold)
      )

    default_conversion =
      if decoder == :viterbi and is_nil(min_span_logprob), do: :raw_logits, else: :reference

    [
      decoder: decoder,
      sequence_length_buckets: buckets,
      sequence_length_bucket_threshold: bucket_threshold,
      logprob_conversion:
        option(
          opts,
          [:logprob_conversion, :privacy_filter_logprob_conversion],
          default_conversion
        )
    ]
    |> maybe_put(:min_span_logprob, min_span_logprob)
  end

  @spec metadata(Serving.t()) :: map()
  def metadata(%Serving{} = serving) do
    policy = %{
      id: @id,
      decoder: serving.decoder,
      sequence_length_buckets: serving.sequence_length_buckets,
      sequence_length_bucket_threshold: serving.sequence_length_bucket_threshold,
      logprob_conversion: serving.logprob_conversion,
      min_span_logprob: serving.min_span_logprob
    }

    Map.merge(policy, %{
      default_policy_sha256: fingerprint(default_policy()),
      matches_default: policy == default_policy()
    })
  end

  @spec default_metadata() :: map()
  def default_metadata do
    policy = default_policy()

    Map.merge(policy, %{
      default_policy_sha256: fingerprint(policy),
      matches_default: true
    })
  end

  defp default_policy do
    %{
      id: @id,
      decoder: :viterbi,
      sequence_length_buckets: @sequence_length_buckets,
      sequence_length_bucket_threshold: @sequence_length_bucket_threshold,
      logprob_conversion: :raw_logits,
      min_span_logprob: nil
    }
  end

  defp option(opts, keys, default) do
    Enum.reduce_while(keys, default, fn key, _acc ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, default}
      end
    end)
  end

  defp fingerprint(policy) do
    policy
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_buckets(:disabled), do: nil
  defp normalize_buckets(buckets), do: buckets

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
