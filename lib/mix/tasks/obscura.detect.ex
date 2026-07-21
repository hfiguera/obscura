defmodule Mix.Tasks.Obscura.Detect do
  @moduledoc """
  Detects PII in a file or stdin using Obscura.
  """

  use Mix.Task

  alias Obscura.CLI

  @shortdoc "Detects PII with Obscura"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, path} = parse_args(args)
    text = CLI.read_input!(path, opts)

    case CLI.detect(text, opts) do
      {:ok, output} -> Mix.shell().info(format(output, opts))
      {:error, reason} -> Mix.raise("Detection failed: #{CLI.format_error(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          stdin: :boolean,
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

  defp format(output, opts) do
    case Keyword.get(opts, :format, "text") do
      "json" -> Jason.encode!(output)
      "text" -> text_output(output)
      _other -> Mix.raise("Unsupported output format.")
    end
  end

  defp text_output(output) do
    output.results
    |> Enum.map_join("\n", fn result ->
      "#{result.entity} #{result.start}..#{result.end} score=#{result.score}"
    end)
    |> case do
      "" -> "No detections."
      lines -> lines
    end
  end
end
