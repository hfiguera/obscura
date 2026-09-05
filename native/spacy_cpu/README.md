# Experimental spaCy CPU runtime

This Rust source implements the pinned spaCy `en_core_web_lg` 3.8.0 NER-only
inference path. It runs without Python, Nx, Bumblebee, a GPU, or network access.
It supports Apple Silicon macOS with Accelerate and ARM64 Homebrew PCRE2, or
glibc Linux on ARM64/x86-64 with OpenBLAS and PCRE2. Alpine/musl and Windows are
not supported. The pinned exported assets are identical on all supported hosts.

From the Obscura source directory:

```sh
mix obscura.spacy.build --offline
.presidio-authoritative-venv/bin/python native/spacy_cpu/export.py \
  --output .cache/spacy_cpu/en_core_web_lg-3.8.0
mix obscura.profile.check --profile spacy_cpu \
  --model-dir .cache/spacy_cpu/en_core_web_lg-3.8.0 --prepare --offline --json
```

Omit `--offline` on the build command only when Cargo may retrieve its locked
dependencies. The source build is explicit and never runs during ordinary Mix
compilation. Rust and the host target must already be installed. macOS additionally
requires Xcode command-line tools and PCRE2; Debian/Ubuntu Linux requires
`build-essential libopenblas-dev libpcre2-dev`. Use LP64 OpenBLAS (32-bit CBLAS
dimensions), not OpenBLAS64. The build chooses `aarch64-apple-darwin`,
`aarch64-unknown-linux-gnu`, or `x86_64-unknown-linux-gnu` for the running host.
The executable is installed into the app's
`priv/spacy_cpu` directory by default; `--output` chooses another location.
Linux runtime hosts need the matching OpenBLAS/PCRE2 shared libraries and a
compatible glibc version. On Debian these are `libopenblas0-pthread` and
`libpcre2-8-0`. Build separately for each OS/architecture.

`export.py` is standalone and uses the versions in `export-environment.json`.
The repository's existing `.presidio-authoritative-venv` meets that lock. Export
assets once in that Python environment, then provision the resulting directory
to runtime hosts. Python and its packages are not inference dependencies.
`Obscura.Spacy.Assets` pins the complete manifest and every exported binary by
SHA-256. The exporter preserves the original weights and tokenizer configuration.
It does not use evaluation data. Model files must remain immutable while mapped.

See the repository's `docs/spacy-cpu.md` for the profile API, ownership,
bounded admission, shutdown, and validation commands. Build output, exported
weights, and local installed binaries are excluded from the source package.

The source was moved here from the completed `eval/spacy_native` feasibility
prototype. Its parameter math and label policy are unchanged. The JSON readiness
message now identifies protocol version 1 and the exact model version. The Elixir
pool verifies that handshake and validates all prediction records.
The handshake identifies `rust_accelerate_cpu` or `rust_openblas_cpu`, and RSS
uses bytes on both platforms. The Elixir pool sets the backend's thread limits
to one per worker. Direct executable callers must set these themselves.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for spaCy/Thinc MIT notices,
MurmurHash provenance, and dynamically linked runtime dependencies.
