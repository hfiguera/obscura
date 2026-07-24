defmodule Obscura.Recognizer.Email do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern
  alias Obscura.Recognizer.SpanHelpers

  @regex ~r/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/

  @impl true
  def name, do: :email

  @impl true
  def supported_entities, do: [:email]

  @impl true
  def entity, do: :email

  @impl true
  def analyze(text, opts) do
    Pattern.scan(text, @regex,
      entity: :email,
      source_entity: "EMAIL_ADDRESS",
      recognizer: :email,
      pattern: :email_address,
      score: 0.85,
      explain: Keyword.get(opts, :explain, false),
      include_text: Keyword.get(opts, :include_text, true),
      allow_list: Keyword.get(opts, :allow_list),
      validate: &validate/1
    )
  end

  defp validate(value) do
    [local, domain] = String.split(value, "@", parts: 2)

    cond do
      local == "" -> {:error, :empty_local_part}
      invalid_domain?(domain) -> {:error, :invalid_domain}
      true -> {:ok, %{}}
    end
  rescue
    MatchError -> {:error, :invalid_email}
  end

  defp invalid_domain?(domain) do
    labels = String.split(domain, ".")
    tld = List.last(labels)

    cond do
      String.starts_with?(domain, ".") or String.ends_with?(domain, ".") -> true
      Enum.count_until(labels, 2) < 2 -> true
      not Regex.match?(~r/^[A-Za-z]{2,63}$/, tld) -> true
      Enum.any?(labels, &SpanHelpers.invalid_domain_label?/1) -> true
      true -> false
    end
  end
end
