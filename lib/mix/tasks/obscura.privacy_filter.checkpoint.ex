defmodule Mix.Tasks.Obscura.PrivacyFilter.Checkpoint do
  @moduledoc """
  Validates a local native privacy-filter checkpoint.

  Example:

      mix obscura.privacy_filter.checkpoint --checkpoint .cache/privacy-filter/openai
  """

  use Mix.Task

  alias Obscura.CLI
  alias Obscura.PrivacyFilter.Checkpoint

  @shortdoc "Validates a native privacy-filter checkpoint"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    checkpoint =
      Keyword.get(opts, :checkpoint) || System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")

    if is_nil(checkpoint) or checkpoint == "" do
      Mix.raise("Pass --checkpoint or set OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    end

    case Checkpoint.validate(checkpoint,
           encoding: Keyword.get(opts, :encoding),
           metadata_only: not Keyword.get(opts, :materialize, false)
         ) do
      {:ok, summary} ->
        Mix.shell().info(Jason.encode!(summary, pretty: true))

      {:error, reason} ->
        Mix.raise("Privacy-filter checkpoint validation failed: #{CLI.format_error(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          checkpoint: :string,
          encoding: :string,
          materialize: :boolean
        ]
      )

    if invalid != [] or remaining != [], do: Mix.raise("Invalid options.")
    parsed
  end
end
