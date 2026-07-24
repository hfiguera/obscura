defmodule Obscura.Recognizer.DateTime do
  @moduledoc """
  Conservative deterministic date/time recognizer.

  The pattern set follows Presidio's generic date recognizer shape while keeping
  ambiguous short forms out of the default deterministic-plus profile.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern
  alias Obscura.Recognizer.SpanHelpers

  @patterns [
    {:iso_timestamp, ~r/\b\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\b/},
    {:iso_8601_tz,
     ~r/\b\d{4}-[01]\d-[0-3]\dT[0-2]\d:[0-5]\d(?::[0-5]\d(?:\.\d+)?)?(?:Z|[+-][0-2]\d:[0-5]\d)\b/},
    {:yyyy_mm_dd, ~r/\b\d{4}-([1-9]|0[1-9]|1[0-2])-([1-9]|0[1-9]|[1-2][0-9]|3[0-1])\b/},
    {:yyyy_slash_mm_dd, ~r/\b\d{4}\/([1-9]|0[1-9]|1[0-2])\/([1-9]|0[1-9]|[1-2][0-9]|3[0-1])\b/},
    {:slash_date,
     ~r/\b(([1-9]|0[1-9]|1[0-2])\/([1-9]|0[1-9]|[1-2][0-9]|3[0-1])\/(\d{4}|\d{2}))\b/},
    {:dash_date, ~r/\b(([1-9]|0[1-9]|1[0-2])-([1-9]|0[1-9]|[1-2][0-9]|3[0-1])-\d{4})\b/},
    {:dot_date, ~r/\b(([1-9]|0[1-9]|[1-2][0-9]|3[0-1])\.([1-9]|0[1-9]|1[0-2])\.(\d{4}|\d{2}))\b/},
    {:month_abbrev,
     ~r/\b(([1-9]|0[1-9]|[1-2][0-9]|3[0-1])-(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)-(\d{4}|\d{2}))\b/i}
  ]

  @impl true
  def name, do: :date_time

  @impl true
  def supported_entities, do: [:date_time]

  @impl true
  def entity, do: :date_time

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    if Keyword.get(opts, :profile) in [
         :deterministic_plus,
         :hybrid_gliner_ortex,
         :hybrid_gliner_urchade,
         :hybrid_gliner_urchade_native
       ] do
      Enum.flat_map(@patterns, fn {pattern, regex} ->
        Pattern.scan(text, regex,
          entity: :date_time,
          source_entity: "DATE_TIME",
          recognizer: :date_time,
          pattern: pattern,
          score: score(pattern),
          explain: Keyword.get(opts, :explain, false),
          include_text: Keyword.get(opts, :include_text, true)
        )
      end)
      |> SpanHelpers.prefer_longest()
    else
      []
    end
  end

  defp score(:iso_timestamp), do: 0.76
  defp score(:iso_8601_tz), do: 0.8
  defp score(_pattern), do: 0.6
end
