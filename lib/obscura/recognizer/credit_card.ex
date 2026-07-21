defmodule Obscura.Recognizer.CreditCard do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern
  alias Obscura.Validator.Luhn

  @regex ~r/(?<!\d)(?:\d[ -]?){13,19}(?!\d)/

  @impl true
  def name, do: :credit_card

  @impl true
  def supported_entities, do: [:credit_card]

  @impl true
  def entity, do: :credit_card

  @impl true
  def analyze(text, opts) do
    Pattern.scan(text, @regex,
      entity: :credit_card,
      source_entity: "CREDIT_CARD",
      recognizer: :credit_card,
      pattern: :card_number,
      score: 0.9,
      explain: Keyword.get(opts, :explain, false),
      validate: &validate/1
    )
  end

  defp validate(value) do
    digits = String.replace(value, ~r/[\s-]/, "")

    cond do
      not Regex.match?(~r/^\d+$/, digits) ->
        {:error, :invalid_characters}

      String.length(digits) not in 13..19 ->
        {:error, :invalid_length}

      Luhn.valid?(digits) ->
        {:ok, %{validator: :luhn, context_words: ["credit", "card", "visa", "payment"]}}

      true ->
        {:error, :luhn_failed}
    end
  end
end
