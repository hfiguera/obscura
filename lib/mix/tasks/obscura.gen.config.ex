defmodule Mix.Tasks.Obscura.Gen.Config do
  @moduledoc """
  Generates safe Obscura configuration examples.
  """

  use Mix.Task

  @shortdoc "Generates Obscura config examples"

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args, strict: [write: :string, force: :boolean])

    if invalid != [] or remaining != [], do: Mix.raise("Invalid options.")

    case Keyword.get(opts, :write) do
      nil ->
        Mix.shell().info(Obscura.CLI.config_example())

      path ->
        write_config!(path, opts)
        Mix.shell().info("Config example written to #{path}")
    end
  end

  defp write_config!(path, opts) do
    if File.exists?(path) and not Keyword.get(opts, :force, false) do
      Mix.raise("Refusing to overwrite the output file; pass --force to replace it.")
    end

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Obscura.CLI.config_example())
  end
end
