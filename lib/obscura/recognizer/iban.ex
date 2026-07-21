defmodule Obscura.Recognizer.IBAN do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern
  alias Obscura.Validator.IBAN

  @regex ~r/\b(?:DE|GB|FR|NL|de|gb|fr|nl)[0-9A-Za-z ]{12,34}\b/

  @impl true
  def name, do: :iban

  @impl true
  def supported_entities, do: [:iban]

  @impl true
  def entity, do: :iban

  @impl true
  def analyze(text, opts) do
    Pattern.scan(text, @regex,
      entity: :iban,
      source_entity: "IBAN_CODE",
      recognizer: :iban,
      pattern: :iban,
      score: 0.85,
      explain: Keyword.get(opts, :explain, false),
      validate: &validate/1
    )
  end

  defp validate(value) do
    if IBAN.valid?(value) do
      {:ok, %{validator: :iban_checksum}}
    else
      {:error, :invalid_iban}
    end
  end
end
