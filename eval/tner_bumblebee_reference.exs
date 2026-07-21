alias Obscura.Recognizer.NER
alias Obscura.Recognizer.NER.ModelSpec
alias Obscura.Recognizer.NER.Serving

defaults = %{
  samples: "eval/tner_reference_samples.json",
  output: "eval/predictions/tner_bumblebee_reference.json",
  backend: "emily"
}

args =
  System.argv()
  |> OptionParser.parse!(
    strict: [
      samples: :string,
      output: :string,
      backend: :string,
      compile_sequence_length: :integer
    ]
  )
  |> elem(0)

samples_path = Keyword.get(args, :samples, defaults.samples)
output_path = Keyword.get(args, :output, defaults.output)
backend = Keyword.get(args, :backend, defaults.backend)
sequence_length = Keyword.get(args, :compile_sequence_length, 32)

backend =
  case Obscura.Recognizer.NER.Backend.normalize(backend) do
    {:ok, backend} -> backend
    {:error, reason} -> raise "unsupported backend: #{inspect(reason)}"
  end

samples =
  samples_path
  |> File.read!()
  |> Jason.decode!()

{:ok, serving} =
  Serving.build(
    model: :tner_roberta_large_ontonotes5,
    real_model_backend: backend,
    compile: [batch_size: 1, sequence_length: sequence_length]
  )

predictions =
  Enum.map(samples, fn sample ->
    {:ok, results} =
      Obscura.analyze(sample["text"],
        entities: [:person, :organization, :location],
        recognizers: [{NER, serving: serving, label_map: serving.model_spec.label_map}],
        conflict_strategy: :none,
        include_text: true,
        recognizer_timeout: 60_000
      )

    %{
      sample_id: sample["id"],
      text: sample["text"],
      predictions:
        Enum.map(results, fn result ->
          %{
            entity: result.entity,
            source_entity: result.source_entity,
            char_start: result.start,
            char_end: result.end,
            byte_start: result.byte_start,
            byte_end: result.byte_end,
            score: result.score,
            value: result.text
          }
        end)
    }
  end)

payload = %{
  adapter: "Obscura.Bumblebee",
  model: ModelSpec.metadata(serving.model_spec),
  samples: predictions
}

File.mkdir_p!(Path.dirname(output_path))
File.write!(output_path, Jason.encode!(payload, pretty: true))

IO.puts(Jason.encode!(%{output: output_path, samples: length(samples)}))
