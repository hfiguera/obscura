defmodule Obscura.Recognizer.Title do
  @moduledoc """
  Narrow deterministic honorific-title recognizer.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern

  @honorific ~r/\b(?:Dr|Mr|Mrs|Ms|Miss)\./

  @impl true
  def name, do: :title

  @impl true
  def supported_entities, do: [:title]

  @impl true
  def entity, do: :title

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    if Keyword.get(opts, :profile) == :deterministic_plus do
      Pattern.scan(text, @honorific,
        entity: :title,
        source_entity: "TITLE",
        recognizer: :title,
        pattern: :honorific,
        score: 0.74,
        explain: Keyword.get(opts, :explain, false),
        include_text: Keyword.get(opts, :include_text, true),
        allow_list: Keyword.get(opts, :allow_list)
      )
    else
      []
    end
  end
end
