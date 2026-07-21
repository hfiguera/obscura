defmodule Mix.Tasks.Obscura.Operational.Soak.Verify do
  @moduledoc """
  Verifies the authoritative soak manifest and promoted artifact hashes.
  """

  use Mix.Task

  alias Obscura.Eval.Operational.Soak.Manifest

  @shortdoc "Verifies authoritative soak evidence"

  @impl true
  def run(args) do
    {parsed, remaining, invalid} = OptionParser.parse(args, strict: [manifest: :string])
    if remaining != [] or invalid != [], do: Mix.raise("Invalid soak verification options.")
    path = Keyword.get(parsed, :manifest, Manifest.path())

    case Manifest.verify(path) do
      :ok -> Mix.shell().info("Authoritative operational soak manifest verified.")
      {:error, reason} -> Mix.raise("Soak manifest verification failed: #{inspect(reason)}")
    end
  end
end
