# spaCy CPU (Experimental)

For the public `:efficient` profile with versioned installation and improved
form boundaries, see [the efficient guide](efficient.md). This page preserves
the experimental alias and its historical results.

`:spacy_cpu` combines Obscura's deterministic recognizers with the pinned
`en_core_web_lg` 3.8.0 NER-only model in a native CPU process. The model adds
person and location detection; organizations and other spaCy labels are excluded
from the profile's model outputs. All 18 labels still participate in decoding.
The assigned NER score is 0.85, not a calibrated probability.

The profile is opt-in and supports Apple Silicon macOS and glibc Linux on ARM64
and x86-64. Linux uses OpenBLAS; macOS uses Accelerate. Alpine/musl, Windows,
Intel macOS, and other CPU architectures are not supported. `:balanced`
remains the stronger general accuracy recommendation. The initial native
benchmark reproduced spaCy NER-only outputs on all 2,648 documents twice, with
4.7–6.1× lower end-to-end latency than the Python control. Strict F1 on Nemotron
was 0.5403 versus 0.5659 for `:balanced`. Those are feasibility measurements;
see `eval/spacy_native/results/PROFILE.md` for validation through the profile API.

## Provision local assets

Build the executable and export the pinned model outside request handling:

```sh
mix obscura.spacy.build --offline
.presidio-authoritative-venv/bin/python native/spacy_cpu/export.py \
  --output .cache/spacy_cpu/en_core_web_lg-3.8.0
```

On macOS the build requires Rust's `aarch64-apple-darwin` target, Xcode command-line
tools, and ARM64 Homebrew PCRE2. On Debian/Ubuntu Linux, install a current Rust
toolchain and `build-essential libopenblas-dev libpcre2-dev`. The build chooses
`aarch64-unknown-linux-gnu` or `x86_64-unknown-linux-gnu` from the running host.
Use the standard LP64 OpenBLAS library, whose CBLAS dimensions are 32-bit integers;
an ILP64/OpenBLAS64 library is incompatible. Omit `--offline` only if Cargo may
retrieve its locked code dependencies. The exporter uses the existing pinned
evaluation Python environment, with a standalone lock in
`native/spacy_cpu/export-environment.json`.
The exported files can then be copied unchanged between supported runtime hosts
without Python. Build the executable on the target architecture and a compatible
glibc distribution; macOS binaries cannot be copied to Linux. Linux runtime hosts
need the OpenBLAS and PCRE2 shared libraries (on Debian: `libopenblas0-pthread`
and `libpcre2-8-0`).

By default, the build installs the executable in the app's `priv/spacy_cpu`
directory. `mix obscura.spacy.build --output PATH` chooses an external location.
Pass that path as `native_binary: PATH`, or set `OBSCURA_SPACY_BINARY`.
The model directory is explicit via `model_dir: PATH` or
`OBSCURA_SPACY_MODEL_DIR`; there is no automatic model download or implicit search
under the evaluation directory. Options take precedence over environment values.

Preparation streams and verifies SHA-256 for all five pinned files before
starting native workers. Assets occupy about 408 MiB. Vectors are mapped read-only;
resident memory depends on pages touched, so the earlier 170 MiB observed worker
peak is not a memory limit. Provision immutable model files, then stop the runtime
before replacing or removing them. Weights and prebuilt executables are not bundled
in the Hex package. The source and export tooling are included.

## Prepare and use

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:spacy_cpu,
    model_dir: ".cache/spacy_cpu/en_core_web_lg-3.8.0",
    workers: 1,
    request_timeout: 30_000
  )

{:ok, detections} =
  Obscura.analyze("José García lives in São Paulo.",
    profile: runtime,
    include_text: false
  )

{:ok, redacted} = Obscura.redact("Call Alice Smith.", profile: runtime)
Obscura.Spacy.Serving.status(runtime.resources.spacy)
Obscura.Spacy.Serving.stop(runtime.resources.spacy)
```

Analysis consumes the reusable runtime. Passing `profile: :spacy_cpu` without a
prepared `spacy_serving:` returns a missing-resource diagnostic. Analysis never
loads model files, builds Rust, invokes Python, or downloads assets. Deterministic
recognizers, supported entity filtering, normal conflict resolution, byte offsets,
and redaction use the existing Obscura path. Requesting only deterministic entity
types skips NER execution on an already prepared runtime.

## Ownership and bounded admission

Use a supervised preparer for an application-wide runtime:

```elixir
children = [
  {Obscura.Profile.Preparer,
   name: MyApp.SpacyCPU,
   profile: :spacy_cpu,
   prepare_options: [model_dir: "/models/en_core_web_lg-3.8.0", workers: 2]}
]

{:ok, runtime} = Obscura.Profile.Preparer.await(MyApp.SpacyCPU)
Obscura.analyze(text, profile: runtime)
```

The pool monitors its owning preparer and closes its native processes when the
preparer stops. Direct `Profile.prepare/2` ties the pool to the calling process;
prepare from a long-lived owner, or pass `runtime_owner: owner_pid`. Explicit
`Serving.stop/1` releases resources and is safe after owner-driven shutdown.
`Serving.start_link/1` is also available for direct supervision of an experimental
pool, using the same preparation options.

`workers` accepts 1–4 and defaults to 1. Each worker uses one math thread. The pool
sets `VECLIB_MAXIMUM_THREADS`, `OPENBLAS_NUM_THREADS`,
`OPENBLAS_DEFAULT_NUM_THREADS`, and `OMP_NUM_THREADS` to 1 for its child processes.
This covers both pthread and OpenMP OpenBLAS builds; see the
[OpenBLAS runtime variables](https://www.openmathlib.org/OpenBLAS/docs/runtime_variables/).
A caller reserves a slot before sending text. With no free slot, inference
returns `:spacy_busy`; there is no internal text queue and no fallback to weaker
detection. The analyzer wraps native errors as recognizer failures. Hosts should
bound concurrency or handle saturation before accepting more input.

`request_timeout` accepts 1–300,000 ms and defaults to 30,000 ms. Reservations,
inference, and caller death are monitored. Timeout, native exit, malformed response,
and abandoned work close the affected Port before replacement. Restarts are limited
to five attempts within five seconds; persistent startup failure reduces available
capacity until the host explicitly recreates the runtime. Status reports available
workers, busy slots, failures, and native RSS without source text. Restart handshakes
can temporarily delay pool responses; this experimental pool does not promise a
hard real-time deadline or a production tail-latency SLO.

Inputs are limited to valid UTF-8, 1 MiB, and 10,000 native tokens. Protocol frames
are bounded. Prediction labels, scores, lengths, and UTF-8 boundaries are validated.
Error reasons and crash formatting exclude source text and raw native responses.

## Readiness and checks

```sh
mix obscura.profile.check --profile spacy_cpu \
  --model-dir .cache/spacy_cpu/en_core_web_lg-3.8.0 --offline --json
mix obscura.profile.prepare --profile spacy_cpu \
  --model-dir .cache/spacy_cpu/en_core_web_lg-3.8.0 --workers 2 --offline --json
```

Local preflight verifies platform, executable presence, and asset hashes without
inference. `--prepare` on `profile.check` additionally checks native startup.
The CLI tasks release their temporary pools after reporting; application code must
retain its own runtime. Explicit incompatible backend options are rejected; this
profile always runs on CPU, independent of global GPU backend configuration.
Readiness/status identify `:accelerate_cpu` on macOS or `:openblas_cpu` on Linux;
the native handshake must match the host backend. Peak RSS is normalized to bytes
on both platforms.

```sh
mix test test/obscura/spacy test/obscura/profile_test.exs test/obscura/profile
OBSCURA_SPACY_MODEL_DIR="$PWD/.cache/spacy_cpu/en_core_web_lg-3.8.0" \
  mix test test/obscura/spacy/real_model_test.exs
mix run --no-start eval/spacy_native/profile_benchmark.exs
```

Portable tests use an explicitly fake executable only to exercise pool lifecycle
and error handling. Real-model tests and the profile benchmark use the native
executable and pinned weights. Real-model tests skip when assets/platform are
unavailable. No authoritative accuracy profile is promoted by these checks.

For reproducible Docker Desktop checks of both Linux architectures, see
[Linux validation](../eval/spacy_native/linux/README.md). The lane requires the
real assets, tests the public profile and worker lifecycle, and compares all
2,648 selected documents to the pinned native baseline twice with networking
disabled; see the [recorded Linux results](../eval/spacy_native/results/LINUX.md).
x86-64 runs under emulation on an Apple Silicon host, so its timing
does not predict performance on physical x86-64 hardware.

The model package declares MIT licensing; review its training/vector provenance
for deployment. Obscura does not bundle or license the model weights. See
`model-asset-licensing.md` and `native/spacy_cpu/THIRD_PARTY_NOTICES.md`.
