defmodule Obscura.Eval.PiiranhaOrtexParity do
  @moduledoc false

  alias Obscura.Recognizer.NER.Ortex

  @score_tolerance 1.0e-4

  def main(argv) do
    {opts, _rest, invalid} =
      OptionParser.parse(argv,
        strict: [model_dir: :string, reference: :string, output: :string]
      )

    if invalid != [], do: raise("invalid arguments: #{inspect(invalid)}")

    model_dir = Keyword.get(opts, :model_dir, ".cache/piiranha-v1-onnx")

    reference_path =
      Keyword.get(opts, :reference, "eval/piiranha/piiranha-parity-reference.json")

    output_path =
      Keyword.get(opts, :output, "eval/piiranha/piiranha-ortex-parity-reference.json")

    reference = reference_path |> File.read!() |> Jason.decode!()

    {:ok, serving} =
      Ortex.build(model_dir: model_dir, execution_providers: [:cpu], max_length: 256)

    cases = Enum.map(reference["cases"], &verify_case(serving, &1))

    report = %{
      source_reference: reference_path,
      model_dir: model_dir,
      score_tolerance: @score_tolerance,
      all_input_ids_match: Enum.all?(cases, & &1.input_ids_match),
      all_attention_masks_match: Enum.all?(cases, & &1.attention_mask_match),
      all_offsets_match: Enum.all?(cases, & &1.offsets_match),
      all_spans_match: Enum.all?(cases, & &1.spans_match),
      cases: cases
    }

    report =
      Map.put(
        report,
        :parity_passed,
        report.all_input_ids_match and report.all_attention_masks_match and
          report.all_offsets_match and report.all_spans_match
      )

    File.mkdir_p!(Path.dirname(output_path))
    File.write!(output_path, Jason.encode_to_iodata!(report, pretty: true))
    IO.puts(Jason.encode!(Map.take(report, [:parity_passed, :all_spans_match])))

    unless report.parity_passed, do: System.halt(1)
  end

  defp verify_case(serving, reference) do
    text = reference["text"]
    {:ok, inputs} = Ortex.debug_inputs(serving, text)
    {:ok, rows} = Ortex.run(serving, text)

    actual_spans =
      Enum.map(rows, fn row ->
        %{"label" => row.label, "start" => row.start, "end" => row.end}
      end)

    expected_spans = trim_reference_spans(text, reference["onnx_spans"])

    %{
      language: reference["language"],
      input_ids_match: inputs.ids == reference["input_ids"],
      attention_mask_match: inputs.attention_mask == reference["attention_mask"],
      offsets_match: normalize_offsets(inputs.offsets) == reference["offsets"],
      spans_match: actual_spans == expected_spans,
      actual_spans: actual_spans,
      expected_spans: expected_spans
    }
  end

  defp normalize_offsets(offsets),
    do: Enum.map(offsets, fn {start, ending} -> [start, ending] end)

  defp trim_reference_spans(text, spans) do
    Enum.map(spans, fn span ->
      {start, ending} = trim_boundaries(text, span["start"], span["end"])
      %{span | "start" => start, "end" => ending}
    end)
  end

  defp trim_boundaries(text, start, ending) do
    trim = ~c" \n\r\t.,;:!?()[]{}<>\"'`"
    ending = min(ending, byte_size(text))

    start =
      Stream.iterate(start, &(&1 + 1))
      |> Enum.find(start, fn index ->
        index >= ending or :binary.at(text, index) not in trim
      end)

    ending =
      Stream.iterate(ending, &(&1 - 1))
      |> Enum.find(ending, fn index ->
        index <= start or :binary.at(text, index - 1) not in trim
      end)

    {start, ending}
  end
end

Obscura.Eval.PiiranhaOrtexParity.main(System.argv())
