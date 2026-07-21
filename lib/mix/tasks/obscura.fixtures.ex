defmodule Mix.Tasks.Obscura.Fixtures do
  @moduledoc """
  Runs the Obscura fixture harness.
  """

  use Mix.Task

  alias Obscura.CLI
  alias Obscura.Eval.Profile
  alias Obscura.Fixtures.Runner

  @shortdoc "Runs Obscura fixtures"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    case Runner.run(opts) do
      {:ok, report} ->
        :ok = Runner.write_smoke_report(opts)
        Mix.shell().info("Fixture report generated: #{report.run_id}")

      {:error, reason} ->
        Mix.raise("Fixture run failed: #{CLI.format_error(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          suite: :string,
          entity: :string,
          tag: :string,
          profile: :string,
          adapter: :string
        ]
      )

    if invalid != [] or remaining != [], do: Mix.raise("Invalid options.")

    parsed
    |> Keyword.update(:suite, nil, &to_existing_suite/1)
    |> Keyword.update(:profile, nil, &to_existing_profile/1)
    |> Keyword.update(:adapter, :obscura, &to_existing_adapter/1)
  end

  defp to_existing_suite("analyzer"), do: :analyzer
  defp to_existing_suite("operator"), do: :operator
  defp to_existing_suite("structured"), do: :structured
  defp to_existing_suite("context"), do: :context
  defp to_existing_suite("vault"), do: :vault
  defp to_existing_suite("llm"), do: :llm
  defp to_existing_suite("stream"), do: :stream
  defp to_existing_suite("nlp"), do: :nlp
  defp to_existing_suite("ner"), do: :ner
  defp to_existing_suite("logger"), do: :logger
  defp to_existing_suite("plug"), do: :plug
  defp to_existing_suite("accuracy"), do: :accuracy
  defp to_existing_suite(_other), do: Mix.raise("Unknown fixture suite.")

  defp to_existing_profile(profile) do
    case Profile.from_string(profile) do
      {:ok, profile} -> profile
      {:error, {:unknown_profile, _other}} -> Mix.raise("Unknown profile.")
    end
  end

  defp to_existing_adapter("obscura"), do: :obscura
  defp to_existing_adapter("placeholder"), do: :placeholder
  defp to_existing_adapter(_other), do: Mix.raise("Unknown adapter.")
end
