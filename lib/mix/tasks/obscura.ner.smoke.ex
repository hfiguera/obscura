defmodule Mix.Tasks.Obscura.Ner.Smoke do
  @moduledoc """
  Runs opt-in real local NER model smoke validation.
  """

  use Mix.Task

  alias Obscura.Eval.RealModelSmoke
  alias Obscura.Recognizer.NER.Backend
  alias Obscura.Recognizer.NER.ModelRegistry

  @shortdoc "Runs opt-in real local NER model smoke"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    unless System.get_env("OBSCURA_REAL_MODEL") == "1" do
      Mix.raise("Set OBSCURA_REAL_MODEL=1 to run real local model smoke.")
    end

    :ok = RealModelSmoke.write_smoke_report(opts)
    :ok = RealModelSmoke.write_presidio_report(opts)
    Mix.shell().info("Real local NER smoke reports generated.")
  end

  defp parse_args(args) do
    {parsed, _remaining, _invalid} =
      OptionParser.parse(args,
        strict: [
          model: :string,
          text: :string,
          profile: :string,
          dataset: :string,
          limit: :integer,
          compile_batch_size: :integer,
          compile_sequence_length: :integer,
          backend: :string
        ]
      )

    parsed
    |> Keyword.put_new(:model, "dslim_bert_base_ner")
    |> normalize_model()
    |> maybe_put_text(parsed)
    |> maybe_put_limit(parsed)
    |> maybe_put_compile(parsed)
    |> maybe_put_backend(parsed)
  end

  defp normalize_model(opts) do
    alias = Keyword.fetch!(opts, :model)

    model = Enum.find(ModelRegistry.aliases(), &(Atom.to_string(&1) == alias))

    if is_nil(model) do
      Mix.raise("Unknown model alias. Known aliases: #{inspect(ModelRegistry.aliases())}")
    end

    Keyword.put(opts, :model, model)
  end

  defp maybe_put_text(opts, parsed) do
    case Keyword.fetch(parsed, :text) do
      {:ok, text} -> Keyword.put(opts, :text, text)
      :error -> opts
    end
  end

  defp maybe_put_limit(opts, parsed) do
    case Keyword.fetch(parsed, :limit) do
      {:ok, limit} -> Keyword.put(opts, :limit, limit)
      :error -> opts
    end
  end

  defp maybe_put_compile(opts, parsed) do
    batch_size = Keyword.get(parsed, :compile_batch_size)
    sequence_length = Keyword.get(parsed, :compile_sequence_length)

    if is_integer(batch_size) or is_integer(sequence_length) do
      Keyword.put(opts, :compile,
        batch_size: batch_size || 1,
        sequence_length: sequence_length || 128
      )
    else
      opts
    end
  end

  defp maybe_put_backend(opts, parsed) do
    case Keyword.fetch(parsed, :backend) do
      {:ok, backend} ->
        case Backend.normalize(backend) do
          {:ok, backend} ->
            Keyword.put(opts, :real_model_backend, backend)

          {:error, {:unsupported_real_model_backend, supported}} ->
            Mix.raise("Unsupported backend. Use one of: #{inspect(supported)}")
        end

      :error ->
        opts
    end
  end
end
