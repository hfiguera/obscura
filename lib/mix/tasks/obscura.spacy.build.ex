defmodule Mix.Tasks.Obscura.Spacy.Build do
  @moduledoc """
  Explicitly builds the pinned spaCy CPU executable for the current host.

      mix obscura.spacy.build
      mix obscura.spacy.build --offline --output /local/bin/obscura-spacy-cpu

  Requires Rust and a C linker, plus Accelerate/Homebrew PCRE2 on Apple Silicon
  macOS or OpenBLAS/PCRE2 development libraries on glibc Linux (ARM64/x86-64).
  This builds code only; it never downloads model assets.
  `--offline` also forbids Cargo dependency downloads. No native compilation
  runs during ordinary Mix compilation or analyzer calls.
  """
  use Mix.Task
  alias Obscura.Spacy.Assets
  @shortdoc "Builds the optional native spaCy CPU executable"

  @impl true
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [output: :string, offline: :boolean, target_dir: :string])

    if rest != [] or invalid != [], do: Mix.raise("Invalid options.")

    target =
      Assets.build_target() ||
        Mix.raise("spaCy CPU requires Apple Silicon macOS or glibc Linux (ARM64/x86-64).")

    source = Path.expand("../../..", __DIR__) |> Path.join("native/spacy_cpu")
    manifest = Path.join(source, "Cargo.toml")
    unless File.regular?(manifest), do: Mix.raise("Native source package is missing.")

    cargo =
      System.find_executable("cargo") ||
        Mix.raise("Install Rust and the #{target} target.")

    build_dir = opts[:target_dir] || Path.join(source, "target")
    build!(cargo, manifest, target, source, build_dir, opts)

    built = Path.join(build_dir, "#{target}/release/obscura-spacy-native-prototype")
    if target == "aarch64-apple-darwin", do: normalize_macho!(built)
    output = opts[:output] || Application.app_dir(:obscura, "priv/spacy_cpu/obscura-spacy-cpu")
    File.mkdir_p!(Path.dirname(output))
    File.cp!(built, output)
    File.chmod!(output, 0o755)
    Mix.shell().info("Built native spaCy CPU executable: #{Path.expand(output)}")
  end

  defp build!(cargo, manifest, target, source, build_dir, opts) do
    flags = [
      "+1.90.0",
      "build",
      "--release",
      "--locked",
      "--target",
      target,
      "--manifest-path",
      manifest,
      "--target-dir",
      build_dir
    ]

    flags = if opts[:offline], do: flags ++ ["--offline"], else: flags
    rustflags = "--remap-path-prefix=#{source}=/obscura/native/spacy_cpu"

    rustflags =
      if target == "aarch64-apple-darwin",
        do: rustflags <> " -C link-arg=-Wl,-reproducible",
        else: rustflags

    {_output, status} =
      System.cmd(cargo, flags,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true,
        env: [
          {"SOURCE_DATE_EPOCH", "1758153600"},
          {"RUSTUP_AUTO_INSTALL", "0"},
          {"RUSTFLAGS", rustflags}
        ]
      )

    if status != 0, do: Mix.raise("Native spaCy build failed.")
  end

  # Apple's linker includes temporary object paths in LC_UUID on some SDKs.
  # Keep the required load command, derive its UUID from content excluding the
  # UUID/signature, then regenerate a deterministic ad-hoc signature.
  defp normalize_macho!(file) do
    data = File.read!(file)
    <<0xFEEDFACF::little-32, _::binary-size(12), count::little-32, _::binary>> = data

    {_, uuid_offset, signature} =
      Enum.reduce(1..count, {32, nil, nil}, fn _, {offset, uuid, signature} ->
        <<command::little-32, size::little-32>> = binary_part(data, offset, 8)

        case command do
          0x1B ->
            {offset + size, offset + 8, signature}

          0x1D ->
            <<first::little-32, bytes::little-32>> = binary_part(data, offset + 8, 8)
            {offset + size, uuid, {first, bytes}}

          _ ->
            {offset + size, uuid, signature}
        end
      end)

    unless uuid_offset && signature, do: Mix.raise("Expected Mach-O UUID and ad-hoc signature.")
    {signature_start, signature_size} = signature
    normalized = replace_bytes(data, uuid_offset, :binary.copy(<<0>>, 16))
    normalized = replace_bytes(normalized, signature_start, :binary.copy(<<0>>, signature_size))
    <<uuid::binary-size(16), _::binary>> = :crypto.hash(:sha256, normalized)
    File.write!(file, replace_bytes(data, uuid_offset, uuid))

    {_, status} =
      System.cmd(
        "codesign",
        [
          "--force",
          "--sign",
          "-",
          "--timestamp=none",
          "--identifier",
          "org.obscura.efficient.v1",
          file
        ],
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("Deterministic ad-hoc signing failed.")
  end

  defp replace_bytes(data, first, replacement) do
    last = first + byte_size(replacement)
    binary_part(data, 0, first) <> replacement <> binary_part(data, last, byte_size(data) - last)
  end
end
