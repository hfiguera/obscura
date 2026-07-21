defmodule Obscura.Eval.Operational.ManifestSupport do
  @moduledoc false

  @spec init(Path.t(), pos_integer()) :: :ok | {:error, term()}
  def init(path, schema_version) do
    if File.exists?(path) do
      :ok
    else
      File.mkdir_p!(Path.dirname(path))

      File.write(
        path,
        Jason.encode!(%{schema_version: schema_version, reports: []}, pretty: true) <> "\n"
      )
    end
  end

  @spec load(Path.t(), (map() -> :ok | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  def load(path, validator) do
    with {:ok, body} <- File.read(path),
         {:ok, manifest} <- Jason.decode(body),
         :ok <- validator.(manifest) do
      {:ok, manifest}
    end
  end

  @spec verify_reports([map()], (map() -> :ok | {:error, term()})) ::
          :ok | {:error, term()}
  def verify_reports(reports, verifier) do
    Enum.reduce_while(reports, :ok, fn entry, :ok ->
      case verifier.(entry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec relative(Path.t()) :: Path.t()
  def relative(path), do: Path.relative_to_cwd(path)

  @spec sha256_file(Path.t()) :: String.t()
  def sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
