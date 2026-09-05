defmodule Obscura.Spacy.Boundaries do
  @moduledoc false
  # Frozen from the disjoint Gretel development split, never the release test split.
  @next_field ~r/\n[ \t]*(?:[-*#]+[ \t]*)?[A-Za-z][A-Za-z ()\/]{1,40}:/
  @address ~r/^[ \t*#-]*(?:[A-Za-z ]{0,20} )?Address[ \t*]*:[ \t*]*([^\n\r]+)/im
  @inline_field ~r/[,;][ \t*]*[A-Za-z][A-Za-z ]{1,30}:/
  @title ~r/\b(?:Mr|Mrs|Ms|Mx|Dr|Prof)\.?[ \t]+$/
  @trim ~c" \t\r\n*_`\"[]():;,"

  def normalize(text, predictions) do
    addresses = address_fields(text)

    predictions
    |> Enum.map(&normalize_span(text, &1, addresses))
    |> Enum.uniq_by(&{&1["label"], &1["byte_start"], &1["byte_end"]})
  end

  defp normalize_span(text, %{"label" => label} = prediction, addresses)
       when label in ["PERSON", "GPE", "LOC", "FAC"] do
    first = prediction["byte_start"]
    last = prediction["byte_end"]

    {first, last} =
      if label != "PERSON" do
        Enum.find(addresses, {first, last}, fn {a, b} -> a <= first and last <= b end)
      else
        {first, last}
      end

    last =
      case Regex.run(
             @next_field,
             binary_part(text, first, min(last - first + 64, byte_size(text) - first)),
             return: :index
           ) do
        [{offset, _}] when offset < last - first -> first + offset
        _ -> last
      end

    {first, last} = trim(text, first, last)

    first =
      if label == "PERSON" do
        prefix_start = max(first - 80, 0)

        case Regex.run(@title, binary_part(text, prefix_start, first - prefix_start),
               return: :index
             ) do
          [{offset, _}] -> prefix_start + offset
          _ -> first
        end
      else
        first
      end

    if first < last,
      do: Map.merge(prediction, %{"byte_start" => first, "byte_end" => last}),
      else: prediction
  end

  defp normalize_span(_text, prediction, _addresses), do: prediction

  defp address_fields(text) do
    for [_, {first, length}] <- Regex.scan(@address, text, return: :index),
        length <= 256 do
      last =
        case Regex.run(@inline_field, binary_part(text, first, length), return: :index) do
          [{offset, _}] -> first + offset
          _ -> first + length
        end

      {first, last}
    end
  end

  defp trim(text, first, last) when first < last do
    cond do
      :binary.at(text, first) in @trim -> trim(text, first + 1, last)
      :binary.at(text, last - 1) in @trim -> trim(text, first, last - 1)
      true -> {first, last}
    end
  end

  defp trim(_text, first, last), do: {first, last}
end
