defmodule Obscura.Recognizer.Domain do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern
  alias Obscura.Recognizer.SpanHelpers

  @regex ~r/(?<![@A-Za-z0-9.-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}(?![A-Za-z0-9-])/
  @posted_photo_url ~r/\bJust posted a photo\s+(https?:\/\/[A-Za-z0-9.-]+\/)/

  @impl true
  def name, do: :domain

  @impl true
  def supported_entities, do: [:domain]

  @impl true
  def entity, do: :domain

  @impl true
  def analyze(text, opts) do
    text
    |> domain_spans(opts)
    |> Kernel.++(posted_photo_url_spans(text, opts))
    |> SpanHelpers.prefer_longest()
  end

  defp domain_spans(text, opts) do
    Pattern.scan(text, @regex,
      entity: :domain,
      source_entity: "DOMAIN_NAME",
      recognizer: :domain,
      pattern: :domain,
      score: 0.7,
      explain: Keyword.get(opts, :explain, false),
      include_text: Keyword.get(opts, :include_text, true),
      validate: &validate/1
    )
  end

  defp posted_photo_url_spans(text, opts) do
    @posted_photo_url
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [_full, {start, byte_length}] ->
      value = binary_part(text, start, byte_length)

      %Obscura.Analyzer.Result{
        entity: :domain,
        start: start,
        end: start + byte_length,
        byte_start: start,
        byte_end: start + byte_length,
        score: 0.71,
        text: Obscura.Internal.ResultText.maybe_materialize(value, opts),
        source_entity: "DOMAIN_NAME",
        recognizer: :domain,
        explanation: nil,
        metadata: %{pattern: :posted_photo_url}
      }
    end)
  end

  defp validate(value) do
    cond do
      String.starts_with?(value, ".") -> {:error, :invalid_domain}
      String.ends_with?(value, ".") -> {:error, :invalid_domain}
      invalid_domain?(value) -> {:error, :invalid_domain}
      true -> {:ok, %{}}
    end
  end

  defp invalid_domain?(domain) do
    labels = String.split(domain, ".")
    tld = List.last(labels)

    cond do
      Enum.count_until(labels, 2) < 2 -> true
      not Regex.match?(~r/^[A-Za-z]{2,63}$/, tld) -> true
      Enum.any?(labels, &SpanHelpers.invalid_domain_label?/1) -> true
      true -> false
    end
  end
end
