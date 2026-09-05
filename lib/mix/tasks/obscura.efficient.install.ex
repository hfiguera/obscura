defmodule Mix.Tasks.Obscura.Efficient.Install do
  @moduledoc """
  Provisions the versioned, verified assets for the `:efficient` CPU profile.

      mix obscura.efficient.install --allow-download
      mix obscura.efficient.install --from-source --allow-download
      mix obscura.efficient.install --native-binary /local/native --model-dir /local/model

  Downloads require `--allow-download`. The default uses a native release binary
  whose checksum is pinned in this package. Model provisioning uses the official
  pinned spaCy wheel and a dedicated, hashed export environment; install uv 0.12.1
  first. Python is used only during provisioning, never inference. To provision
  without Python, supply an already exported and verified `--model-dir`.

  `--from-source` uses Rust 1.90.0 and the host's documented math/regex libraries.
  Existing successful installations are verified and reused. A failed attempt
  does not replace an installation. `--destination` selects an immutable v1
  directory; set `OBSCURA_EFFICIENT_ASSET_DIR` to that path at runtime.
  """
  use Mix.Task
  alias Obscura.Spacy.Assets
  alias Obscura.Spacy.Serving
  @shortdoc "Installs verified native CPU assets for :efficient"
  @switches [
    allow_download: :boolean,
    from_source: :boolean,
    native_binary: :string,
    model_dir: :string,
    destination: :string
  ]

  @impl true
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)
    if rest != [] or invalid != [], do: Mix.raise("Invalid installer options.")

    if opts[:from_source] && opts[:native_binary],
      do: Mix.raise("Choose a source build or a local release binary.")

    target = Assets.build_target() || Mix.raise("Unsupported efficient platform.")
    destination = Path.expand(opts[:destination] || Assets.install_dir())
    manifest = manifest()

    if File.exists?(destination) do
      verify_installation!(destination)
      Mix.shell().info("Verified existing efficient v1 installation: #{destination}")
    else
      File.mkdir_p!(Path.dirname(destination))
      staging = destination <> ".staging-#{System.unique_integer([:positive])}"
      File.mkdir!(staging)

      try do
        binary = Path.join(staging, "obscura-spacy-cpu")
        native!(binary, manifest["native"][target], opts)
        model!(Path.join(staging, "model"), manifest, opts)
        verify_installation!(staging)
        {:ok, digest} = Assets.sha256(binary)
        {:ok, model_hash} = Assets.sha256(Path.join(staging, "model/model.json"))

        receipt = %{
          asset_version: manifest["asset_version"],
          native_sha256: digest,
          platform: target,
          source_build: opts[:from_source] == true,
          model_hashes: Map.put(Assets.hashes(), "model.json", model_hash)
        }

        File.write!(
          Path.join(staging, "installation.json"),
          Jason.encode!(receipt, pretty: true) <> "\n"
        )

        File.rename!(staging, destination)
        Mix.shell().info("Installed efficient v1 assets: #{destination}")
      after
        File.rm_rf(staging)
      end
    end
  end

  defp native!(destination, release, opts) do
    cond do
      opts[:from_source] ->
        flags = ["--output", destination]
        flags = if opts[:allow_download], do: flags, else: flags ++ ["--offline"]
        Mix.Task.reenable("obscura.spacy.build")
        Mix.Task.run("obscura.spacy.build", flags)

      opts[:native_binary] ->
        verify!(opts[:native_binary], release && release["sha256"], "native executable")
        File.cp!(opts[:native_binary], destination)

      true ->
        authorize_download!(opts)

        unless release && release["sha256"],
          do:
            Mix.raise(
              "No verified native release is available for this package yet. Use --from-source."
            )

        download!(release["url"], destination)
        verify!(destination, release["sha256"], "native executable")
    end

    File.chmod!(destination, 0o755)
  end

  defp model!(destination, manifest, opts) do
    if opts[:model_dir] do
      copy_model!(opts[:model_dir], destination)
    else
      authorize_download!(opts)
      require_curl!()

      uv =
        System.find_executable("uv") ||
          Mix.raise("Install uv 0.12.1, or supply --model-dir with verified exported assets.")

      {version, 0} = System.cmd(uv, ["--version"])

      unless Enum.take(String.split(version), 2) == ["uv", "0.12.1"],
        do: Mix.raise("Model provisioning requires uv 0.12.1.")

      source = Path.expand("../../..", __DIR__) |> Path.join("native/spacy_cpu")
      temporary = destination <> "-export"
      File.mkdir_p!(temporary)

      try do
        venv = Path.join(temporary, "venv")
        python = Path.join(venv, "bin/python")
        wheel = Path.join(temporary, manifest["model"]["wheel_filename"])
        command!(uv, ["venv", "--python", "3.11.15", venv])

        command!(uv, [
          "pip",
          "install",
          "--python",
          python,
          "--require-hashes",
          "--no-deps",
          "--only-binary",
          ":all:",
          "-r",
          Path.join(source, "export-requirements.txt")
        ])

        download!(manifest["model"]["wheel_url"], wheel)
        verify!(wheel, manifest["model"]["wheel_sha256"], "official model wheel")
        command!(uv, ["pip", "install", "--python", python, "--no-deps", wheel])
        command!(python, [Path.join(source, "export.py"), "--output", destination])
      after
        File.rm_rf(temporary)
      end
    end
  end

  defp copy_model!(source_dir, destination) do
    File.mkdir_p!(destination)

    for name <- Map.keys(Assets.hashes()) ++ ["LICENSE", "LICENSES_SOURCES"] do
      source = Path.join(Path.expand(source_dir), name)
      if File.regular?(source), do: File.cp!(source, Path.join(destination, name))
    end
  end

  defp verify_installation!(directory) do
    opts = [
      native_binary: Path.join(directory, "obscura-spacy-cpu"),
      model_dir: Path.join(directory, "model")
    ]

    case Assets.validate(opts) do
      {:ok, _} ->
        :ok

      {:error, diagnostic} ->
        Mix.raise("Efficient asset verification failed: #{diagnostic.code}.")
    end

    receipt = Path.join(directory, "installation.json")

    if File.regular?(receipt) do
      digest = receipt |> File.read!() |> Jason.decode!() |> Map.fetch!("native_sha256")
      verify!(opts[:native_binary], digest, "installed executable")
    end

    # Verify integrity before executing, then check dynamic-library loading and protocol.
    case Serving.build(opts) do
      {:ok, pool} ->
        Serving.stop(pool)

      {:error, _} ->
        Mix.raise("Native startup failed. Check the platform's OpenBLAS/PCRE2 runtime libraries.")
    end
  end

  defp manifest do
    Application.app_dir(:obscura, "priv/obscura/efficient-assets.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp verify!(file, expected, label) do
    unless is_binary(expected) and Assets.sha256(file) == {:ok, expected},
      do: Mix.raise("Checksum verification failed for #{label}.")
  end

  defp authorize_download!(opts) do
    unless opts[:allow_download],
      do:
        Mix.raise(
          "Pass --allow-download to provision remote assets, or supply local verified files."
        )
  end

  defp download!(url, destination) do
    curl = require_curl!()

    command!(curl, [
      "--fail",
      "--location",
      "--silent",
      "--show-error",
      "--proto",
      "=https",
      "--proto-redir",
      "=https",
      "--tlsv1.2",
      "--connect-timeout",
      "30",
      "--max-time",
      "1800",
      "--output",
      destination,
      url
    ])
  end

  defp require_curl! do
    System.find_executable("curl") || Mix.raise("Install curl for explicit HTTPS downloads.")
  end

  defp command!(executable, args) do
    {_output, status} =
      System.cmd(executable, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    if status != 0, do: Mix.raise("Efficient provisioning command failed (exit #{status}).")
  end
end
