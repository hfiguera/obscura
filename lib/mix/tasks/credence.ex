defmodule Mix.Tasks.Credence do
  @moduledoc """
  Runs Credence analysis over project source files.

  Credence exposes a library API rather than an upstream Mix task. This task
  provides the Phase 0 quality gate without modifying files.
  """

  use Mix.Task

  @shortdoc "Runs Credence semantic lint analysis"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Application.ensure_all_started(:ex_unit)

    issues =
      source_files()
      |> Enum.flat_map(&analyze_file/1)

    if issues == [] do
      Mix.shell().info("Credence found no issues.")
    else
      Enum.each(issues, fn {file, issue} ->
        Mix.shell().error("#{file}: #{format_issue(issue)}")
      end)

      Mix.raise("Credence found #{length(issues)} issue(s)")
    end
  end

  defp source_files do
    ["lib/**/*.{ex,exs}", "test/**/*.{ex,exs}"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&(&1 in ["lib/mix/tasks/credence.ex", "test/test_helper.exs"]))
    |> Enum.sort()
  end

  defp analyze_file(file) do
    file
    |> File.read!()
    |> Credence.analyze()
    |> Map.fetch!(:issues)
    |> Enum.map(&{file, &1})
  end

  defp format_issue(issue) do
    message = Map.get(issue, :message) || inspect(issue)
    rule = Map.get(issue, :rule)

    if is_nil(rule), do: message, else: "#{inspect(rule)} #{message}"
  end
end
