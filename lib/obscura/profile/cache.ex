defmodule Obscura.Profile.Cache do
  @moduledoc false

  alias Obscura.Profile
  alias Obscura.Recognizer.NER.ModelRegistry
  alias Obscura.Recognizer.NER.ModelSpec

  @quarantine_dir ".obscura-quarantine"

  @type status :: :not_applicable | :missing | :partial | :present | :complete
  @type snapshot :: %{
          status: status(),
          bytes: non_neg_integer(),
          repositories: [map()],
          directory: String.t(),
          directory_source: atom()
        }

  @spec inspect(Profile.t(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def inspect(%Profile{} = descriptor, opts) do
    case Keyword.get(opts, :cache_probe) do
      probe when is_function(probe, 2) -> normalize_probe(probe.(descriptor, opts), opts)
      _probe -> inspect_repositories(descriptor, opts)
    end
  rescue
    error -> {:error, {:cache_failure, error.__struct__}}
  end

  @spec effective_directory(keyword()) :: {String.t(), atom()}
  def effective_directory(opts) do
    cond do
      cache_dir = repository_cache_dir(opts) -> {cache_dir, :repository_option}
      cache_dir = System.get_env("BUMBLEBEE_CACHE_DIR") -> {cache_dir, :environment}
      true -> {to_string(:filename.basedir(:user_cache, "bumblebee")), :system_default}
    end
  end

  @spec quarantine_incomplete(snapshot()) :: {:ok, non_neg_integer()} | {:error, term()}
  def quarantine_incomplete(%{repositories: repositories, directory: root}) do
    repositories
    |> Enum.flat_map(&Map.get(&1, :incomplete_files, []))
    |> Enum.reduce_while({:ok, 0}, fn path, {:ok, count} ->
      root = cache_root_for_entry(path, root)
      destination = Path.join(root, @quarantine_dir)
      target_dir = Path.join(destination, Path.basename(Path.dirname(path)))
      target = Path.join(target_dir, Path.basename(path) <> "-" <> unique_suffix())

      with :ok <- File.mkdir_p(target_dir),
           :ok <- File.rename(path, target) do
        {:cont, {:ok, count + 1}}
      else
        {:error, :enoent} -> {:cont, {:ok, count}}
        {:error, reason} -> {:halt, {:error, {:cache_failure, reason}}}
      end
    end)
  end

  defp inspect_repositories(descriptor, opts) do
    {root, source} = effective_directory(opts)

    repositories =
      descriptor
      |> repositories()
      |> Enum.map(fn repository ->
        {repository_root, _source} = effective_directory(opts, repository.kind)
        {repository_root, repository}
      end)
      |> Enum.uniq_by(fn {repository_root, repository} ->
        {repository_root, repository.repository_id}
      end)
      |> Enum.map(fn {repository_root, repository} ->
        repository_snapshot(repository_root, repository)
      end)

    {:ok,
     %{
       status: aggregate_status(repositories),
       bytes: Enum.reduce(repositories, 0, &(&1.bytes + &2)),
       repositories: repositories,
       directory: root,
       directory_source: source
     }}
  end

  defp repositories(%Profile{name: name}) when name not in [:balanced, :accurate], do: []

  defp repositories(%Profile{default_models: models}) do
    models
    |> Enum.flat_map(fn model ->
      case ModelRegistry.fetch(model) do
        {:ok, %ModelSpec{} = spec} ->
          [
            repository_entry(model, :model, spec.model),
            repository_entry(model, :tokenizer, spec.tokenizer)
          ]

        {:error, _reason} ->
          []
      end
    end)
  end

  defp repository_entry(model, kind, reference) do
    %{model: model, kind: kind, repository_id: ModelSpec.hf_id(reference)}
  end

  defp repository_snapshot(root, repository) do
    scope = repository_scope(repository.repository_id)
    directory = Path.join([root, "huggingface", scope])
    files = regular_files(directory)
    incomplete = Enum.filter(files, &incomplete_cache_file?/1)
    metadata_count = Enum.count(files, &String.ends_with?(&1, ".json"))

    status =
      cond do
        incomplete != [] -> :partial
        metadata_count > 0 -> :present
        true -> :missing
      end

    repository
    |> Map.put(:scope, scope)
    |> Map.put(:status, status)
    |> Map.put(:bytes, Enum.reduce(files, 0, &(file_size(&1) + &2)))
    |> Map.put(:incomplete_files, incomplete)
  end

  defp regular_files(directory) do
    directory
    |> Path.join("*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  defp incomplete_cache_file?(path) do
    basename = Path.basename(path)

    not String.ends_with?(basename, ".json") and
      not String.starts_with?(basename, ".") and
      not metadata_exists_for_entry?(path, basename)
  end

  defp metadata_exists_for_entry?(path, basename) do
    case String.split(basename, ".", parts: 2) do
      [url_hash, _etag] -> File.exists?(Path.join(Path.dirname(path), url_hash <> ".json"))
      _parts -> false
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      {:error, _reason} -> 0
    end
  end

  defp aggregate_status([]), do: :not_applicable

  defp aggregate_status(repositories) do
    statuses = Enum.map(repositories, & &1.status)

    cond do
      :partial in statuses -> :partial
      Enum.all?(statuses, &(&1 == :present)) -> :present
      true -> :missing
    end
  end

  defp normalize_probe({:ok, snapshot}, opts), do: normalize_probe(snapshot, opts)
  defp normalize_probe({:error, _reason} = error, _opts), do: error

  defp normalize_probe(snapshot, opts) when is_map(snapshot) do
    {directory, source} = effective_directory(opts)

    {:ok,
     snapshot
     |> Map.put_new(:status, :missing)
     |> Map.put_new(:bytes, 0)
     |> Map.put_new(:repositories, [])
     |> Map.put_new(:directory, directory)
     |> Map.put_new(:directory_source, source)}
  end

  defp normalize_probe(other, _opts), do: {:error, {:cache_failure, {:invalid_probe, other}}}

  defp repository_cache_dir(opts) do
    repository_cache_dir(opts, :model) || repository_cache_dir(opts, :tokenizer)
  end

  defp repository_cache_dir(opts, :model),
    do: opts |> Keyword.get(:model_repository_opts, []) |> Keyword.get(:cache_dir)

  defp repository_cache_dir(opts, :tokenizer),
    do: opts |> Keyword.get(:tokenizer_repository_opts, []) |> Keyword.get(:cache_dir)

  defp effective_directory(opts, kind) do
    cond do
      cache_dir = repository_cache_dir(opts, kind) -> {cache_dir, :repository_option}
      cache_dir = System.get_env("BUMBLEBEE_CACHE_DIR") -> {cache_dir, :environment}
      true -> {to_string(:filename.basedir(:user_cache, "bumblebee")), :system_default}
    end
  end

  defp cache_root_for_entry(path, fallback) do
    case Path.split(path) |> Enum.reverse() do
      [_file, _scope, "huggingface" | reversed_root] ->
        reversed_root |> Enum.reverse() |> Path.join()

      _parts ->
        fallback
    end
  end

  defp repository_scope(repository_id) do
    repository_id
    |> String.replace("/", "--")
    |> String.replace(~r/[^\w-]/, "")
  end

  defp unique_suffix do
    System.unique_integer([:positive, :monotonic]) |> Integer.to_string()
  end
end
