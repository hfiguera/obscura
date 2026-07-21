defmodule Mix.Tasks.ExSlop do
  @moduledoc """
  Runs ExSlop checks through Credo.

  ExSlop is a Credo plugin, not a standalone upstream Mix task. This project
  task keeps the Phase 0 quality alias explicit while delegating to Credo with
  the plugin registered in `.credo.exs`.
  """

  use Mix.Task

  @shortdoc "Runs ExSlop checks through Credo"

  @impl Mix.Task
  def run(args) do
    Mix.Task.reenable("credo")
    Mix.Task.run("credo", ["--strict" | args])
  end
end
