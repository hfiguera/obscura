defmodule Mix.Tasks.Obscura.Benchmarks.Verify do
  @moduledoc """
  Verifies the authoritative benchmark manifest and promoted artifact hashes.

      mix obscura.benchmarks.verify
  """

  use Mix.Task

  alias Obscura.CLI
  alias Obscura.Eval.AuthoritativeManifest

  @shortdoc "Verifies authoritative benchmark evidence"

  @impl Mix.Task
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args, strict: [manifest: :string], aliases: [m: :manifest])

    if invalid != [] or remaining != [] do
      Mix.raise("Invalid options.")
    end

    manifest = Keyword.get(opts, :manifest, AuthoritativeManifest.path())

    case AuthoritativeManifest.verify(manifest) do
      :ok ->
        Mix.shell().info("Authoritative benchmark manifest verified.")

      {:error, reason} ->
        Mix.raise("Authoritative benchmark verification failed: #{CLI.format_error(reason)}")
    end
  end
end
