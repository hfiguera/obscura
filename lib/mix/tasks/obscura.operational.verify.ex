defmodule Mix.Tasks.Obscura.Operational.Verify do
  @moduledoc """
  Verifies operational manifest structure and promoted report hashes.
  """

  use Mix.Task

  alias Obscura.Eval.Operational.Manifest

  @shortdoc "Verifies authoritative operational evidence"

  @impl true
  def run(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args, strict: [manifest: :string])

    if remaining != [] or invalid != [], do: Mix.raise("Invalid verification options.")
    path = Keyword.get(parsed, :manifest, Manifest.path())

    case Manifest.verify(path) do
      :ok -> Mix.shell().info("Authoritative operational manifest verified.")
      {:error, reason} -> Mix.raise("Operational verification failed: #{inspect(reason)}")
    end
  end
end
