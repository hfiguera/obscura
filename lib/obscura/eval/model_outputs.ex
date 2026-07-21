defmodule Obscura.Eval.ModelOutputs do
  @moduledoc false

  @ner_entities [:person, :organization, :location, :date_time, :nationality]

  def from_sample(sample) do
    sample.spans
    |> Enum.filter(&(&1.entity in @ner_entities))
    |> Enum.map(fn span ->
      %{
        label: span.source_entity,
        start: span.char_start,
        end: span.char_end,
        offset_unit: :character,
        score: 0.95
      }
    end)
  end
end
