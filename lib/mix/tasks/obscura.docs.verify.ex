defmodule Mix.Tasks.Obscura.Docs.Verify do
  @moduledoc """
  Verifies local links in repository Markdown files.

      mix obscura.docs.verify
      mix obscura.docs.verify README.md docs/profiles.md

  Fenced code blocks and external URLs are ignored. Absolute local paths are
  rejected because they cannot work for another checkout or a Hex user.
  """

  use Mix.Task

  @shortdoc "Verifies repository-local Markdown links"

  @default_globs ["README.md", "docs/**/*.md", "eval/**/*.md"]
  @inline_link ~r/\[[^\]]*\]\((?<target><[^>]+>|[^)\s]+)(?:\s+["'][^"']*["'])?\)/
  @reference_link ~r/^\s*\[[^\]]+\]:\s*(?<target><[^>]+>|\S+)/
  @external_target ~r/^(?:[a-z][a-z0-9+.-]*:|#|\/\/)/i
  @line_suffix ~r/:\d+(?::\d+)?$/

  @impl Mix.Task
  def run(args) do
    files = source_files(args)
    errors = Enum.flat_map(files, &verify_file/1)

    if errors == [] do
      Mix.shell().info("Verified local Markdown links in #{length(files)} files.")
    else
      Enum.each(errors, fn error -> Mix.shell().error(error) end)
      Mix.raise("Markdown link verification failed with #{length(errors)} error(s)")
    end
  end

  defp source_files([]) do
    @default_globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_files(paths), do: Enum.sort(paths)

  defp verify_file(file) do
    file
    |> File.stream!(:line, [])
    |> Stream.with_index(1)
    |> Enum.reduce({false, []}, fn source_line, state ->
      verify_source_line(file, source_line, state)
    end)
    |> elem(1)
  end

  defp verify_source_line(file, {line, line_number}, {in_fence?, errors}) do
    if fence_line?(line) do
      {not in_fence?, errors}
    else
      {in_fence?, line_errors(file, line_number, line, in_fence?) ++ errors}
    end
  end

  defp line_errors(_file, _line_number, _line, true), do: []
  defp line_errors(file, line_number, line, false), do: verify_line(file, line_number, line)

  defp fence_line?(line), do: Regex.match?(~r/^\s*(?:```|~~~)/, line)

  defp verify_line(file, line_number, line) do
    targets =
      Regex.scan(@inline_link, line, capture: ["target"])
      |> List.flatten()
      |> Kernel.++(
        @reference_link
        |> Regex.scan(line, capture: ["target"])
        |> List.flatten()
      )

    targets
    |> Enum.uniq()
    |> Enum.flat_map(&verify_target(file, line_number, &1))
  end

  defp verify_target(file, line_number, raw_target) do
    target = raw_target |> String.trim_leading("<") |> String.trim_trailing(">")

    cond do
      target == "" or Regex.match?(@external_target, target) ->
        []

      Path.type(target) == :absolute ->
        [format_error(file, line_number, raw_target, "absolute local path")]

      true ->
        path =
          target
          |> String.split(["#", "?"], parts: 2)
          |> hd()
          |> URI.decode()
          |> String.replace(@line_suffix, "")
          |> then(&Path.expand(&1, Path.dirname(file)))

        if File.exists?(path),
          do: [],
          else: [format_error(file, line_number, raw_target, "target does not exist")]
    end
  end

  defp format_error(file, line_number, target, reason),
    do: "#{file}:#{line_number}: #{reason}: #{target}"
end
