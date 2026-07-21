defmodule Obscura.Fixtures.Loader do
  @moduledoc """
  Loads and validates Phase 0 fixture files.
  """

  alias Obscura.Fixtures.Schema

  @fixture_root "fixtures"

  @doc """
  Loads all fixtures under the fixture root.
  """
  @spec load_all(keyword()) :: {:ok, [map()]} | {:error, term()}
  def load_all(opts \\ []) do
    opts
    |> fixture_files()
    |> load_files()
  end

  @doc """
  Loads fixture files and validates unique IDs.
  """
  @spec load_files([Path.t()]) :: {:ok, [map()]} | {:error, term()}
  def load_files(files) when is_list(files) do
    with {:ok, fixtures} <- eval_files(files),
         :ok <- validate_unique_ids(fixtures),
         :ok <- validate_all(fixtures) do
      {:ok, fixtures}
    end
  end

  @doc """
  Returns fixture file paths matching options.
  """
  @spec fixture_files(keyword()) :: [Path.t()]
  def fixture_files(opts \\ []) do
    suite = Keyword.get(opts, :suite)

    @fixture_root
    |> Path.join("**/*.exs")
    |> Path.wildcard()
    |> Enum.filter(&fixture_file_for_suite?(&1, suite))
    |> Enum.sort()
  end

  defp fixture_file_for_suite?(file, nil), do: not fixture_file_for_suite?(file, :accuracy)
  defp fixture_file_for_suite?(file, :analyzer), do: String.contains?(file, "fixtures/analyzer/")
  defp fixture_file_for_suite?(file, :operator), do: String.contains?(file, "fixtures/operator/")

  defp fixture_file_for_suite?(file, :structured),
    do: String.contains?(file, "fixtures/structured/")

  defp fixture_file_for_suite?(file, :context), do: String.contains?(file, "fixtures/context/")
  defp fixture_file_for_suite?(file, :vault), do: String.contains?(file, "fixtures/vault/")
  defp fixture_file_for_suite?(file, :llm), do: String.contains?(file, "fixtures/llm/")
  defp fixture_file_for_suite?(file, :stream), do: String.contains?(file, "fixtures/stream/")
  defp fixture_file_for_suite?(file, :nlp), do: String.contains?(file, "fixtures/nlp/")
  defp fixture_file_for_suite?(file, :ner), do: String.contains?(file, "fixtures/ner/")
  defp fixture_file_for_suite?(file, :logger), do: String.contains?(file, "fixtures/logger/")
  defp fixture_file_for_suite?(file, :plug), do: String.contains?(file, "fixtures/plug/")
  defp fixture_file_for_suite?(file, :accuracy), do: String.contains?(file, "fixtures/accuracy/")

  defp eval_files(files) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
      try do
        case Code.eval_file(file) do
          {fixtures, _binding} when is_list(fixtures) ->
            {:cont, {:ok, acc ++ fixtures}}

          {fixture, _binding} when is_map(fixture) ->
            {:cont, {:ok, acc ++ [fixture]}}

          {other, _binding} ->
            {:halt, {:error, {:invalid_fixture_file_return, file, other}}}
        end
      rescue
        error -> {:halt, {:error, {:fixture_file_error, file, Exception.message(error)}}}
      end
    end)
  end

  defp validate_unique_ids(fixtures) do
    duplicates =
      fixtures
      |> Enum.map(&Map.get(&1, :id))
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, _count} -> id end)

    if duplicates == [], do: :ok, else: {:error, {:duplicate_fixture_ids, duplicates}}
  end

  defp validate_all(fixtures) do
    Enum.reduce_while(fixtures, :ok, fn fixture, :ok ->
      case Schema.validate(fixture) do
        {:ok, _fixture} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_fixture, Map.get(fixture, :id), reason}}}
      end
    end)
  end
end
