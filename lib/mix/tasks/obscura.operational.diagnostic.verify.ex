defmodule Mix.Tasks.Obscura.Operational.Diagnostic.Verify do
  @moduledoc """
  Verifies promoted sustained-latency diagnostic evidence.
  """

  use Mix.Task

  alias Obscura.Eval.Operational.Diagnostic.Manifest

  @shortdoc "Verifies authoritative sustained-latency evidence"

  @impl true
  def run(args) do
    {parsed, remaining, invalid} = OptionParser.parse(args, strict: [manifest: :string])
    if remaining != [] or invalid != [], do: Mix.raise("Invalid diagnostic verification options.")
    path = Keyword.get(parsed, :manifest, Manifest.path())

    case Manifest.verify(path) do
      :ok -> Mix.shell().info("Authoritative operational diagnostic manifest verified.")
      {:error, reason} -> Mix.raise("Diagnostic manifest verification failed: #{inspect(reason)}")
    end
  end
end
