defmodule Mix.Tasks.Obscura.Redact do
  @moduledoc """
  Redacts PII in a file or stdin using Obscura.
  """

  use Mix.Task

  alias Obscura.CLI

  @shortdoc "Redacts PII with Obscura"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, path} = parse_args(args)
    text = CLI.read_input!(path, opts)

    case CLI.redact(text, opts) do
      {:ok, output} -> write_output!(output, opts)
      {:error, reason} -> Mix.raise("Redaction failed: #{CLI.format_error(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          stdin: :boolean,
          stdout: :boolean,
          out: :string,
          force: :boolean,
          format: :string,
          profile: :string,
          include_text: :boolean,
          timeout: :integer
        ]
      )

    if invalid != [], do: Mix.raise("Invalid options.")

    opts = Keyword.update(parsed, :profile, :regex_only, &CLI.profile!/1)

    {opts, List.first(remaining)}
  end

  defp write_output!(output, opts) do
    cond do
      Keyword.get(opts, :stdout, false) ->
        Mix.shell().info(format(output, opts))

      out = Keyword.get(opts, :out) ->
        write_file!(out, output.text, opts)
        Mix.shell().info("Redacted output written to #{out}")

      true ->
        Mix.shell().info(format(output, opts))
    end
  end

  defp write_file!(path, text, opts) do
    if File.exists?(path) and not Keyword.get(opts, :force, false) do
      Mix.raise("Refusing to overwrite the output file; pass --force to replace it.")
    end

    File.write!(path, text)
  end

  defp format(output, opts) do
    case Keyword.get(opts, :format, "text") do
      "json" -> Jason.encode!(output)
      "text" -> output.text
      _other -> Mix.raise("Unsupported output format.")
    end
  end
end
