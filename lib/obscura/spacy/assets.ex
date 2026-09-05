defmodule Obscura.Spacy.Assets do
  @moduledoc false
  import Bitwise
  alias Obscura.Diagnostic

  @hashes %{
    "model.json" => "216f7db87f64c157181c19eaa7840fc0820198e163c81d47a10cfb0cc6533750",
    "weights.bin" => "f919ba1502890bca0f808532168495f97e4462ae28bf9e955a2415f43ec7dc17",
    "vectors.bin" => "c4a3e215076dc379c6386ef9e15fb1c4d1a58451802a3bae582c70970df0387b",
    "vector_keys.bin" => "76a86673cd8b05fecb50116871bfd8d4dbd0530e844681cbd0a4f54db17d1750",
    "unicode.bin" => "683130936bbd088c9ffdc9054c2396f06d92852e35045cb3fa112a66f7f11c7d"
  }

  def hashes, do: @hashes
  @legacy_model_hash "ea006cbbe70e3f794a7136acf9c1d85199ee6925526578b3dc920ce2947fc95b"

  def install_dir do
    System.get_env("OBSCURA_EFFICIENT_ASSET_DIR") ||
      Path.join([to_string(:filename.basedir(:user_cache, ~c"obscura")), "efficient", "v1"])
  end

  def supported_platform?, do: not is_nil(build_target())

  def build_target(os \\ :os.type(), arch \\ to_string(:erlang.system_info(:system_architecture))) do
    cond do
      os == {:unix, :darwin} and String.starts_with?(arch, ["aarch64", "arm64"]) ->
        "aarch64-apple-darwin"

      os == {:unix, :linux} and String.contains?(arch, "linux-gnu") ->
        cond do
          String.starts_with?(arch, "aarch64") -> "aarch64-unknown-linux-gnu"
          String.starts_with?(arch, "x86_64") -> "x86_64-unknown-linux-gnu"
          true -> nil
        end

      true ->
        nil
    end
  end

  def backend, do: if(:os.type() == {:unix, :linux}, do: :openblas_cpu, else: :accelerate_cpu)
  def native_backend, do: "rust_#{backend()}"

  def paths(opts) do
    %{
      model_dir:
        Keyword.get(opts, :model_dir) || System.get_env("OBSCURA_SPACY_MODEL_DIR") ||
          Path.join(install_dir(), "model"),
      native_binary:
        Keyword.get(opts, :native_binary) || System.get_env("OBSCURA_SPACY_BINARY") ||
          default_binary()
    }
  end

  defp default_binary do
    installed = Path.join(install_dir(), "obscura-spacy-cpu")

    if File.regular?(installed),
      do: installed,
      else: Application.app_dir(:obscura, "priv/spacy_cpu/obscura-spacy-cpu")
  end

  def validate(opts) do
    paths = paths(opts)

    cond do
      not supported_platform?() ->
        {:error, diagnostic(:unsupported_backend, :spacy_cpu_platform)}

      validate_backend(opts) != :ok ->
        {:error, diagnostic(:unsupported_backend, backend())}

      not executable?(paths.native_binary) ->
        {:error, diagnostic(:missing_model_asset, :native_binary)}

      not is_binary(paths.model_dir) ->
        {:error, diagnostic(:missing_model_asset, :spacy_model_dir)}

      true ->
        validate_files(paths)
    end
  rescue
    _ -> {:error, diagnostic(:model_load_failed, :spacy_assets)}
  end

  def validate_backend(opts) do
    backend = Keyword.get(opts, :backend) || Keyword.get(opts, :real_model_backend)

    if backend in [nil, :default, "default", :cpu, "cpu", backend(), to_string(backend())],
      do: :ok,
      else: {:error, diagnostic(:unsupported_backend, backend())}
  end

  defp validate_files(paths) do
    Enum.reduce_while(@hashes, {:ok, paths}, fn {name, expected}, acc ->
      case sha256(Path.join(paths.model_dir, name)) do
        {:ok, ^expected} ->
          {:cont, record_model_hash(acc, name, expected)}

        {:ok, @legacy_model_hash} when name == "model.json" ->
          {:cont, record_model_hash(acc, name, @legacy_model_hash)}

        {:ok, _} ->
          {:halt, {:error, diagnostic(:checkpoint_hash_mismatch, :spacy_assets)}}

        {:error, _} ->
          {:halt, {:error, diagnostic(:missing_model_asset, :spacy_assets)}}
      end
    end)
  end

  defp record_model_hash({:ok, paths}, "model.json", digest),
    do: {:ok, Map.put(paths, :model_sha256, digest)}

  defp record_model_hash(acc, _name, _digest), do: acc

  def sha256(path) do
    digest =
      path
      |> File.stream!(1_048_576, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, digest}
  rescue
    _ -> {:error, :unreadable_asset}
  end

  defp executable?(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} -> (mode &&& 0o111) != 0
      _ -> false
    end
  end

  defp executable?(_), do: false

  def diagnostic(code, asset),
    do:
      Diagnostic.new(code,
        profile: :spacy_cpu,
        component: :spacy_cpu,
        backend: backend(),
        asset: asset
      )
end
