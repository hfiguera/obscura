defmodule Obscura.Recognizer.URL do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern

  @regex ~r/https?:\/\/[A-Za-z0-9.-]+(?:[\/?#][^\s]*)?/

  @impl true
  def name, do: :url

  @impl true
  def supported_entities, do: [:url]

  @impl true
  def entity, do: :url

  @impl true
  def analyze(text, opts) do
    Pattern.scan(text, @regex,
      entity: :url,
      source_entity: "URL",
      recognizer: :url,
      pattern: :url,
      score: 0.8,
      explain: Keyword.get(opts, :explain, false),
      include_text: Keyword.get(opts, :include_text, true),
      validate: &validate/1
    )
    |> Enum.reject(&posted_photo_domain_duplicate?(text, &1, opts))
  end

  defp posted_photo_domain_duplicate?(text, result, opts) do
    requested_entities = Keyword.get(opts, :entities, [])

    :domain in requested_entities and Keyword.get(opts, :profile) == :deterministic_plus and
      result.start >= byte_size("Just posted a photo ") and
      text
      |> binary_part(0, result.start)
      |> String.ends_with?("Just posted a photo ")
  end

  defp validate(value) do
    uri = URI.parse(value)

    cond do
      uri.scheme not in ["http", "https"] -> {:error, :invalid_scheme}
      is_nil(uri.host) or uri.host == "" -> {:error, :missing_host}
      invalid_host?(uri.host) -> {:error, :invalid_host}
      true -> {:ok, %{}}
    end
  end

  defp invalid_host?(host) do
    labels = String.split(host, ".")
    tld = List.last(labels)

    cond do
      Enum.count_until(labels, 2) < 2 -> true
      not Regex.match?(~r/^[A-Za-z]{2,63}$/, tld) -> true
      Enum.any?(labels, &invalid_host_label?/1) -> true
      true -> false
    end
  end

  defp invalid_host_label?(""), do: true
  defp invalid_host_label?(label) when byte_size(label) > 63, do: true

  defp invalid_host_label?(label) do
    String.starts_with?(label, "-") or String.ends_with?(label, "-")
  end
end
