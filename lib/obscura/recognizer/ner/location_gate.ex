defmodule Obscura.Recognizer.NER.LocationGate do
  @moduledoc """
  Cheap text gate for opt-in secondary location NER.

  This is intentionally conservative about accuracy, not about skipping as many
  samples as possible. It only decides whether the location-specialist model is
  worth running; deterministic recognizers and the primary NER recognizer still
  run through the normal analyzer pipeline.
  """

  @strong_context ~r/\b(address(?:es)?|city|state|country|county|province|region|zip|postal|street|st\.?|avenue|ave\.?|road|rd\.?|boulevard|blvd\.?|lane|ln\.?|drive|dr\.?|apartment|apt\.?|suite|located|location|lives\s+in|based\s+in|works\s+in|town|from|in|near|toward|towards|inside|outside|at|to|serving|arrived|coming)\b/i
  @comma_capitalized ~r/\b[A-Z][\w'-]+(?:\s+[A-Z][\w'-]+){0,2},\s+[A-Z][\w'-]+/
  @street_number ~r/\b\d{1,6}\s+[A-Z][\w'-]+/

  @type decision :: %{run?: boolean(), reason: atom()}
  @type summary :: %{
          strategy: atom(),
          total_samples: non_neg_integer(),
          run_count: non_neg_integer(),
          skip_count: non_neg_integer(),
          run_rate: float(),
          skip_rate: float()
        }

  @doc """
  Returns true when the secondary location model should run.
  """
  @spec run?(String.t()) :: boolean()
  def run?(text) when is_binary(text), do: decide(text).run?
  def run?(_text), do: false

  @doc """
  Returns the decision and the first matched reason.
  """
  @spec decide(String.t()) :: decision()
  def decide(text) when is_binary(text) do
    cond do
      Regex.match?(@strong_context, text) -> %{run?: true, reason: :location_context}
      Regex.match?(@comma_capitalized, text) -> %{run?: true, reason: :comma_capitalized_phrase}
      Regex.match?(@street_number, text) -> %{run?: true, reason: :street_number}
      true -> %{run?: false, reason: :no_location_signal}
    end
  end

  def decide(_text), do: %{run?: false, reason: :invalid_text}

  @doc """
  Summarizes gate behavior for report metadata.
  """
  @spec summary([String.t()]) :: summary()
  def summary(texts) when is_list(texts) do
    total = length(texts)
    run_count = Enum.count(texts, &run?/1)
    skip_count = total - run_count

    %{
      strategy: :location_context,
      total_samples: total,
      run_count: run_count,
      skip_count: skip_count,
      run_rate: rate(run_count, total),
      skip_rate: rate(skip_count, total)
    }
  end

  defp rate(_count, 0), do: 0.0
  defp rate(count, total), do: count / total
end
