defmodule Obscura.PplxPii.ExportPredictions do
  @moduledoc false

  alias Obscura.Eval.Offset
  alias Obscura.Eval.PresidioResearchLoader

  @profiles %{"fast" => :fast, "accurate" => :accurate}
  @entities %{
    "credit_card" => :credit_card,
    "email" => :email,
    "ip_address" => :ip_address,
    "location" => :location,
    "person" => :person,
    "phone" => :phone,
    "url" => :url,
    "us_ssn" => :us_ssn
  }

  def main(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          profile: :string,
          dataset: :string,
          selection: :string,
          out: :string,
          phone_parser: :boolean
        ]
      )

    if remaining != [] or invalid != [], do: fail!("invalid arguments")

    profile = fetch_profile!(opts)
    dataset = fetch_dataset!(opts)
    selection_path = fetch_required!(opts, :selection)
    out = fetch_required!(opts, :out)
    selection = selection_path |> File.read!() |> Jason.decode!()
    entities = selection_entities!(selection)

    {:ok, loaded} =
      PresidioResearchLoader.load(
        dataset: dataset,
        profile: profile,
        invalid_span: :drop_sample
      )

    samples = select_samples!(loaded.samples, selection)
    analyzer_profile = prepare_profile!(profile)
    analyze_opts = analyzer_options(analyzer_profile, entities, opts)
    rows = Enum.map(samples, &prediction_row(&1, analyze_opts))

    artifact = %{
      schema_version: 1,
      producer: "Obscura",
      profile: Atom.to_string(profile),
      dataset: Atom.to_string(dataset),
      phone_parser: Keyword.get(opts, :phone_parser, false),
      selection_sha256: sha256_file(selection_path),
      rows: rows,
      raw_text_omitted: true
    }

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Jason.encode_to_iodata!(artifact, pretty: true))
    IO.puts(Jason.encode!(%{out: out, profile: profile, samples: length(rows)}))
  end

  defp fetch_profile!(opts) do
    case Map.fetch(@profiles, fetch_required!(opts, :profile)) do
      {:ok, profile} -> profile
      :error -> fail!("profile must be fast or accurate")
    end
  end

  defp fetch_dataset!(opts) do
    dataset = fetch_required!(opts, :dataset)

    Enum.find(PresidioResearchLoader.known_datasets(), &(Atom.to_string(&1) == dataset)) ||
      fail!("unknown dataset: #{dataset}")
  end

  defp fetch_required!(opts, key) do
    Keyword.get(opts, key) ||
      fail!("missing --#{key |> Atom.to_string() |> String.replace("_", "-")}")
  end

  defp selection_entities!(selection) do
    selection
    |> get_in(["entity_policy", "entities"])
    |> Enum.map(&Map.fetch!(@entities, &1))
  rescue
    _error -> fail!("selection has an invalid entity policy")
  end

  defp select_samples!(samples, selection) do
    by_id = Map.new(samples, &{to_string(&1.id), &1})
    ids = get_in(selection, ["dataset", "ordered_sample_ids"]) || fail!("selection has no IDs")

    Enum.map(ids, fn id ->
      Map.get(by_id, to_string(id)) || fail!("selection sample is missing: #{id}")
    end)
  end

  # The authoritative reports resolve the stable alias before analysis.
  defp prepare_profile!(:fast), do: :deterministic_plus

  defp prepare_profile!(:accurate) do
    case Obscura.Profile.prepare(:accurate, offline: true) do
      {:ok, runtime} -> runtime
      {:error, reason} -> fail!("could not prepare accurate profile: #{inspect(reason)}")
    end
  end

  defp analyzer_options(profile, entities, opts) do
    [profile: profile, entities: entities, include_text: false]
    |> maybe_put_phone_parser(opts)
  end

  defp maybe_put_phone_parser(analyze_opts, opts) do
    if Keyword.get(opts, :phone_parser, false) do
      Keyword.put(
        analyze_opts,
        :phone_parser,
        Obscura.Recognizer.Phone.ExPhoneNumberValidator
      )
    else
      analyze_opts
    end
  end

  defp prediction_row(sample, analyze_opts) do
    started_at = System.monotonic_time()

    {:ok, predictions} = Obscura.analyze(sample.text, analyze_opts)

    %{
      sample_id: sample.id,
      latency_ms: elapsed_ms(started_at),
      predictions: Enum.map(predictions, &prediction(sample.text, &1))
    }
  end

  defp prediction(text, result) do
    {:ok, char_start} = Offset.byte_to_char(text, result.byte_start)
    {:ok, char_end} = Offset.byte_to_char(text, result.byte_end)

    %{
      entity: result.entity,
      source_entity: result.source_entity,
      char_start: char_start,
      char_end: char_end,
      byte_start: result.byte_start,
      byte_end: result.byte_end,
      score: result.score
    }
  end

  defp elapsed_ms(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end

  defp sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp fail!(message), do: raise(ArgumentError, message)
end

Obscura.PplxPii.ExportPredictions.main(System.argv())
