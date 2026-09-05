alias Obscura.Spacy.{Assets, Serving}
input = System.fetch_env!("EFFICIENT_INPUT")
output = System.fetch_env!("EFFICIENT_PREDICTIONS")
profile = System.get_env("EFFICIENT_PROFILE") || "efficient"
rows = input |> File.read!() |> Jason.decode!()
{:ok, runtime} = Obscura.Profile.prepare(profile)
entities = ~w(person location email phone us_ssn credit_card ip_address date_time)a

try do
  predictions =
    Enum.map(rows, fn row ->
      {:ok, found} =
        Obscura.analyze(row["text"], profile: runtime, entities: entities, include_text: false)

      %{
        id: row["id"],
        predictions: Enum.map(found, &Map.take(&1, [:entity, :byte_start, :byte_end]))
      }
    end)

  result = %{
    profile: profile,
    input_sha256: input |> Assets.sha256() |> elem(1),
    predictions: predictions,
    created_at: DateTime.utc_now()
  }

  File.write!(output, Jason.encode!(result, pretty: true) <> "\n")
  IO.puts("Predicted #{length(rows)} documents with #{profile}.")
after
  if runtime.resources[:spacy], do: Serving.stop(runtime.resources.spacy)
end
