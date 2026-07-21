defmodule Mix.Tasks.Obscura.PrivacyFilter.Setup do
  @moduledoc """
  Downloads a local native privacy-filter checkpoint and validates it.

  The download is explicit, resumable, and intended for development or
  benchmark setup. Obscura never downloads model assets during normal analysis.

  Example:

      mix obscura.privacy_filter.setup --checkpoint .cache/privacy-filter/openai

  Useful options:

      --repo openai/privacy-filter
      --revision main
      --layout native
      --layout python-original
      --file config.json --file model.safetensors
      --download-tool curl
      --download-tool hf
      --download-timeout 600000
      --download-output-limit 16384
      --no-validate
      --materialize
  """

  use Mix.Task

  alias Obscura.CLI
  alias Obscura.PrivacyFilter.Checkpoint.Setup

  @shortdoc "Downloads and validates a native privacy-filter checkpoint"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    case Setup.run(opts) do
      {:ok, summary} ->
        Mix.shell().info(Jason.encode!(summary, pretty: true))

      {:error, reason} ->
        Mix.raise("Privacy-filter checkpoint setup failed: #{CLI.format_error(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          repo: :string,
          revision: :string,
          layout: :string,
          checkpoint: :string,
          file: :keep,
          download_tool: :string,
          download_timeout: :integer,
          download_output_limit: :integer,
          hf_token: :string,
          hf_max_workers: :integer,
          validate: :boolean,
          materialize: :boolean,
          encoding: :string,
          connect_timeout: :integer
        ],
        aliases: [
          c: :checkpoint
        ]
      )

    if invalid != [] or remaining != [], do: Mix.raise("Invalid options.")

    parsed
    |> maybe_put_files()
    |> Keyword.put_new(:validate, true)
  end

  defp maybe_put_files(opts) do
    case Keyword.get_values(opts, :file) do
      [] -> opts
      files -> opts |> Keyword.delete(:file) |> Keyword.put(:files, files)
    end
  end
end
