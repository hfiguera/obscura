# Optional Dependencies and Assets

Obscura's base deterministic path does not require model weights, accelerator
libraries, external services, or network access during inference. Model-backed,
parser-backed, and ONNX capabilities are explicit additions.

The machine-readable contracts are:

- `priv/obscura/capabilities.json`
- `priv/obscura/model_assets.json`

`Obscura.Capabilities` validates and exposes those manifests. Tests verify that
the listed Hex dependencies exist in `mix.exs`, documented environment
variables exist in the codebase, stable profiles have capability coverage, and
the manifests contain no local absolute paths or obvious credential material.

## Product Profile Matrix

| Profile | Stability | Base behavior | Required optional dependencies | Assets | Preferred development backend |
| --- | --- | --- | --- | --- | --- |
| `:fast` | stable | Deterministic structured PII | None | None | BEAM |
| `:balanced` | stable; commercial TNER use requires LDC membership | Deterministic plus TNER NER | `nx`, `bumblebee` | TNER model and tokenizer | Emily on Apple Silicon; EXLA where supported |
| `:accurate` | stable; commercial TNER use requires LDC membership | Deterministic plus output-aware TNER/Jean location cascade | `nx`, `bumblebee` | Two models and two tokenizers | Emily on Apple Silicon; EXLA where supported |
| `:hybrid_gliner_urchade` | experimental | Deterministic plus Urchade GLiNER | `ortex`, `tokenizers` | Pinned local ONNX, tokenizer, and config export | Ortex CPU |
| `:openmed_pii` | experimental | Native model-only OpenMed/Nemotron PII | `nx`, `safetensors` | Validated Privacy Filter checkpoint | Explicitly selected Binary, EXLA, or Emily |

Optional dependencies are declared with `optional: true` so downstream
applications only install the capabilities they select. Obscura never downloads
assets from `Obscura.analyze/2` or `Obscura.redact/2`.

## Base Installation

The base library requires only its normal Hex dependencies:

```elixir
def deps do
  [
    {:obscura, "~> 0.1"}
  ]
end
```

Use the deterministic product profile explicitly:

```elixir
Obscura.analyze("Contact jane@example.com", profile: :fast)
```

No model cache, environment variable, or setup task is required.

## Parser-Backed Phone Validation

The optional `ex_phone_number` integration improves international telephone
validation and remains caller-controlled because region policy affects which
digit strings are valid.

```elixir
def deps do
  [
    {:obscura, "~> 0.1"},
    {:ex_phone_number, "~> 0.4.11"}
  ]
end
```

Select the parser and regions explicitly. Do not assume a global default region
is appropriate for every tenant or dataset.

```elixir
Obscura.analyze(text,
  profile: :fast,
  phone_parser: Obscura.Recognizer.Phone.ExPhoneNumberValidator,
  phone_regions: ["US", "GB"]
)
```

Obscura rejects obvious date-shaped and repeated-digit junk before accepting
parser-backed phone candidates, but applications must still benchmark their
region mix.

## Bumblebee/Nx Profiles

The `:balanced` and `:accurate` profiles use token classification through
Bumblebee/Nx.

Host applications should include:

```elixir
def deps do
  [
    {:obscura, "~> 0.1"},
    {:nx, "~> 0.12"},
    {:bumblebee, "~> 0.7"}
  ]
end
```

Then choose a backend. BinaryBackend is useful for correctness smoke tests but
is not the recommended performance path for large NER models.

### Emily on macOS Apple Silicon

Emily is the current development backend used for Metal/GPU model benchmarks:

```elixir
{:emily, "~> 0.6"}
```

Project setup:

```sh
OBSCURA_REAL_MODEL_BACKEND=emily mix deps.get
```

For validation, forbid silent fallback:

```sh
OBSCURA_REAL_MODEL=1 \
OBSCURA_REAL_MODEL_BACKEND=emily \
OBSCURA_EMILY_DEVICE=gpu \
OBSCURA_EMILY_FALLBACK=raise \
mix test --include real_model
```

The presence of Emily does not by itself prove GPU use. Runtime and benchmark
metadata must identify the requested backend, actual backend, selected device,
and fallback policy. If device proof is unavailable, report it as unknown.

Emily is currently validated primarily for macOS Apple Silicon development and
benchmarking. It is not yet Obscura's universal production backend promise.

### EXLA

EXLA is conditional in the Obscura development project:

```sh
OBSCURA_REAL_MODEL=1 mix deps.get
```

Downstream applications can add:

```elixir
{:exla, "~> 0.12"}
```

EXLA does not imply GPU. Record whether the actual client is CPU, CUDA, or
another supported target.

### Explicit Runtime Preparation

Preparing a profile is an explicit operation which may populate the configured
Hugging Face cache:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:balanced,
    allow_download: true,
    real_model_backend: :emily,
    compile: [batch_size: 1, sequence_length: 128]
  )

Obscura.analyze("Rachel works at Google in Paris.", profile: runtime)
```

The runtime owns reusable serving resources. Build it during controlled
application initialization, supervision setup, or a dedicated warmup phase. Do
not build it inside every request.

`allow_download` defaults to `false`. Without it, remote repositories are
opened with Bumblebee offline mode and only complete cached assets may be used.
`offline: true` always forbids network access, even if download authorization
was also passed. `allow_download` authorizes network I/O only; it does not
accept third-party terms or establish commercial-use authorization. Review the
reported asset licensing metadata as a separate deployment decision.

Use the preparation task to populate a cache with structured progress:

```sh
mix obscura.profile.prepare \
  --profile balanced \
  --backend emily \
  --allow-download \
  --timeout 1800000 \
  --inactivity-timeout 300000
```

For model-backed profiles, preparation emits an `asset_license_notice` before
the preparation-started event whenever Obscura knows that a model has a
specific commercial-use requirement. Human-readable task output prints the
notice directly; `--json` includes the same fields as structured progress.

The effective cache directory follows explicit repository `cache_dir`, then
`BUMBLEBEE_CACHE_DIR`, then the operating-system Bumblebee cache location.
The local Mix task prints that path; public diagnostics and telemetry expose
only the source and status so home directories do not leak. `--json` is
newline-delimited JSON and suppresses Bumblebee's terminal progress bar.

The controlled preparation worker has an overall timeout and an inactivity
timeout. Cache-byte growth and stage transitions reset inactivity. On timeout,
abnormal exit, or interrupted transfer, unreferenced files lacking Bumblebee
metadata are moved under `.obscura-quarantine` in the selected cache. A later
authorized preparation retries cleanly. Complete metadata-backed entries are
never quarantined.

`mix obscura.operational.benchmark` enforces offline model/tokenizer loading,
counts lifecycle construction stages, and fails promotion if the canonical
request path reconstructs the runtime. Promoted operational conclusions are
summarized in `docs/benchmark-status.md`.

The accurate profile prepares both models:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:accurate,
    allow_download: true,
    real_model_backend: :emily
  )
```

It routes requests by requested entity. For location requests TNER always runs;
Jean-Baptiste runs only when TNER has no accepted location. A request that
excludes `:location` does not invoke the specialist, but the runtime prepares
both resources up front to keep request handling network-free and reusable.

## Model Assets

### TNER OntoNotes5

- Alias: `tner_roberta_large_ontonotes5`
- Model: `tner/roberta-large-ontonotes5`
- Tokenizer: `tner/roberta-large-ontonotes5`
- Pinned revision: `0bce50f7884d5bb040469c907c897d4b061ccbb4`
- Published weight size: approximately 1.42 GB, excluding cache metadata and
  backend/runtime memory
- Used by: stable `:balanced` and `:accurate`
- Adapter: Bumblebee token classification
- Commercial use: requires an LDC for-profit membership, as directly confirmed
  by LDC on 2026-07-22

The profile integration is stable, but Obscura does not bundle, distribute,
sublicense, or license the checkpoint and cannot verify LDC membership. Use it
only for noncommercial evaluation or with the required LDC authorization. LDC
did not conclusively answer whether the checkpoint publisher was authorized to
redistribute the trained weights. See `docs/model-asset-licensing.md`.

### Urchade GLiNER Multi PII

- Alias: `urchade_gliner_multi_pii_v1`
- Model: `urchade/gliner_multi_pii-v1`
- Pinned revision: `1fcf13e85f4eef5394e1fcd406cf2ca9ea82351d`
- Used by: public experimental profile `:hybrid_gliner_urchade`
- Adapter: `Obscura.Recognizer.GLiNER.Ortex`
- Dependency: conditional optional Obscura fork of `ortex 0.1.10`
- Assets: locally exported `model.onnx`, tokenizer/config files from
  `microsoft/mdeberta-v3-base`
- Reported license: Apache-2.0; full provenance still requires project-owner
  review

Host applications selecting this profile must add the CPU runtime and tokenizer
dependencies explicitly:

```elixir
def deps do
  [
    {:obscura, "~> 0.1"},
    {:ortex, "~> 0.1.10"},
    {:tokenizers, "~> 0.5.1"}
  ]
end
```

The upstream checkpoint does not publish a directly usable ONNX bundle.
Generate it with the pinned script and lock in `eval/gliner/`; do not place
weights in the application package or repository. The native adapter passes
its parity checks but failed the three `:balanced` promotion gates. It is
publicly available only as an experimental CPU-only general NER option, not as
an accuracy replacement for `:balanced`. Current comparative metrics are in
`benchmark-status.md`.

Prepare and reuse the runtime:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:hybrid_gliner_urchade,
    model_dir: ".cache/gliner/urchade-gliner-multi-pii-v1"
  )

Obscura.analyze("Rachel works at Google in Paris.", profile: runtime)
```

The project-local Ortex fork adds structured CoreML options and ONNX Runtime
profiling. On Apple Silicon, callers can explicitly request:

```elixir
Obscura.Recognizer.GLiNER.Ortex.build(
  model: :urchade_gliner_multi_pii_v1,
  model_dir: model_dir,
  execution_providers: [:coreml],
  coreml_options: [
    model_format: :ml_program,
    compute_units: :cpu_and_gpu,
    require_static_input_shapes: false,
    enable_on_subgraphs: false
  ],
  profile_prefix: ".cache/ortex-profiles/urchade"
)
```

This is a diagnostic path, not a recommended accelerator configuration. The
current dynamic export preserves output parity but is substantially slower than
CPU and uses extensive CPU fallback. `finish_profiling/1` proves provider
assignment, not GPU-only execution. Model assets and generated native binaries
remain outside the package and repository.

Urchade also has an experimental native Nx/Emily adapter:

```text
Obscura.Recognizer.GLiNER.Native
```

Enable its development dependency path with `OBSCURA_GLINER_NATIVE=1`. It
requires Emily, Tokenizers, Nx, Safetensors, a pinned local
`model.safetensors` export, `tokenizer.json`, `gliner_config.json`, and
`obscura_native_manifest.json`. It does not require Ortex or ONNX Runtime.
Both Emily fallback paths are forced to `:raise`. Layer and decoded-span parity
pass, but the adapter is not promoted because it does not beat Ortex CPU
latency or the `:balanced` accuracy gates.

The registry and asset manifest pin the reviewed revision. Authoritative
benchmarks must continue recording it so an upstream branch change cannot
silently alter profile behavior.

### Jean-Baptiste Location Specialist

- Alias: `jean_baptiste_roberta_large_ner_english`
- Model: `Jean-Baptiste/roberta-large-ner-english`
- Tokenizer fallback: `FacebookAI/roberta-large`
- Model revision: `8f3abc1ef81ffbbb0e80568d4fed1dd10d459548`
- Tokenizer revision: `722cf37b1afa9454edce342e7895e588b6ff1d59`
- Published fine-tuned weight size: approximately 1.42 GB; `:accurate` also
  needs the TNER weights and both tokenizer repositories
- Used by: stable `:accurate`
- Adapter: Bumblebee token classification
- Fine-tuned model license: MIT; verify base/tokenizer terms

The tokenizer fallback is intentional because the fine-tuned repository does
not provide the Rust-compatible tokenizer artifact expected by the current
path. Authoritative runs must record both pinned repositories and revisions.

## Native Privacy Filter

The `:openmed_pii` profile uses Obscura's native Privacy Filter architecture.
It does not use Bumblebee's normal token-classification architecture loader.

Host dependencies:

```elixir
def deps do
  [
    {:obscura, "~> 0.1"},
    {:nx, "~> 0.12"},
    {:safetensors, "~> 0.1.3"}
  ]
end
```

Prepare the checkpoint explicitly:

```sh
mix obscura.privacy_filter.setup \
  --repo OpenMed/privacy-filter-nemotron-v2 \
  --checkpoint .cache/privacy-filter/openmed-nemotron-v2
```

Validate before starting inference:

```sh
mix obscura.privacy_filter.checkpoint \
  --checkpoint .cache/privacy-filter/openmed-nemotron-v2
```

Prepare a reusable runtime:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:openmed_pii,
    checkpoint: ".cache/privacy-filter/openmed-nemotron-v2",
    backend: :emily
  )
```

At minimum, the native checkpoint requires `config.json` and one or more
Safetensors files. The inspected OpenMed v2 repository also publishes
`tokenizer.json`, `tokenizer_config.json`, and `label_space_fine_v1.json`.
Python-original layout additionally requires `dtypes.json` and
`viterbi_calibration.json` and must be selected explicitly.

Checkpoint paths and hashes belong in local configuration and authoritative
benchmark metadata, not in the Hex package. The model's inspected license
metadata is not a clear production grant; verify it before deployment.

## GLiNER, Native Emily, and Generic Ortex

GLiNER and generic token-classification Ortex adapters remain advanced,
experimental capabilities rather than stable product profiles.

Project development setup:

```sh
OBSCURA_GLINER_ORTEX=1 mix deps.get
OBSCURA_GLINER_NATIVE=1 mix deps.get
```

Dependencies:

```elixir
{:ortex, "~> 0.1.10"}
{:tokenizers, "~> 0.5.1"}
```

GLiNER requires a compatible ONNX graph, `tokenizer.json`, and GLiNER config.
Configure `OBSCURA_GLINER_MODEL_DIR` or explicit paths. Generic token
classification uses `OBSCURA_NER_ORTEX_MODEL_DIR` or explicit options.

The experimental `:nvidia_gliner_pii_v1` model alias uses a pinned local export
of `nvidia/gliner-PII`. It has no public product profile and is not included in
the authoritative matrix. The export is approximately 1.78 GB and requires
the exact ONNX, tokenizer, and config hashes recorded in
`eval/gliner/nvidia-export-reference.json`. Configure the asset directory with
`OBSCURA_GLINER_NVIDIA_MODEL_DIR` for tagged parity tests or pass `model_dir`
directly.

The native Emily path uses a Safetensors checkpoint instead of ONNX. Configure
`OBSCURA_GLINER_NATIVE_MODEL_DIR`; generated assets remain local and ignored.

No ONNX model is bundled. ONNX Runtime execution provider availability is
platform-specific and must be recorded in benchmark metadata.

## Python Reference Environments

Python environments under `.presidio-venv/`, `.opf-venv/`, and
`.privacy-filter-reference-venv/` are ignored development tools. They are not
runtime dependencies of the library.

Each authoritative Python comparison must record:

- Python version;
- fully pinned package versions;
- model repository and immutable revision;
- dataset fingerprint and sample IDs;
- entity mapping and offset policy;
- checkpoint hashes;
- exact command;
- whether CPU or GPU was actually used.

## Network Policy

| Operation | Network allowed by default? |
| --- | --- |
| `Obscura.analyze/2` with local profiles | No |
| `Obscura.redact/2` with local profiles | No |
| `Obscura.Profile.validate_runtime/2` | No |
| `Obscura.Profile.prepare/2` with Hugging Face sources | Yes, explicit operation |
| Privacy Filter setup Mix task | Yes, explicit operation |

External-service calls are application-owned custom-recognizer behavior and are
not part of Obscura's built-in profiles or capability manifest.

Readiness checks must be offline. They inspect modules, paths, layouts, hashes,
and reusable serving presence without contacting model hubs or providers.

## Cache and Cleanup

Obscura does not own one global cache. The host controls:

- Hugging Face/Bumblebee cache location;
- `.cache/privacy-filter` checkpoint directories;
- GLiNER/Ortex model directories;
- Mix dependency/build caches;
- ignored Python virtual environments.

Never delete shared caches automatically from library code. Cleanup commands
are operator actions and should target only an explicitly configured directory
or dependency.

## Common Diagnostics

| Code | Meaning |
| --- | --- |
| `missing_optional_dependency` | Required optional Hex dependency is unavailable |
| `missing_model_asset` | Reusable serving or model files were not prepared |
| `missing_tokenizer_asset` | Required tokenizer is unavailable or mismatched |
| `missing_checkpoint` | Privacy Filter checkpoint path was not supplied/found |
| `checkpoint_incomplete` | Required checkpoint files are missing/truncated |
| `checkpoint_layout_mismatch` | Native versus Python-original contract is wrong |
| `checkpoint_hash_mismatch` | Local file differs from the pinned manifest |
| `unsupported_backend` | Backend name is not supported by the adapter |
| `backend_device_unavailable` | Requested CPU/GPU device could not be selected |
| `backend_fallback_forbidden` | Runtime attempted a forbidden fallback |
| `model_load_failed` | Model architecture/files could not be loaded |
| `tokenizer_load_failed` | Tokenizer files or architecture are incompatible |
| `serving_build_failed` | Runtime serving could not be constructed |

Use `Obscura.Diagnostic.format/1` for human output and inspect its stable `code`
for programmatic handling. Diagnostic inspection omits nested causes and local
paths by default.

## Production Checklist

Before deploying an optional capability:

1. Pin Obscura and optional dependency versions.
2. Pin immutable model and tokenizer revisions.
3. Record and verify local asset hashes.
4. Review every model and base-model license.
5. Run profile readiness offline.
6. Warm reusable serving resources before accepting traffic.
7. Prove actual backend/device and forbid silent fallback.
8. Benchmark the deployment hardware and representative data.
9. Define memory, concurrency, timeout, and failure behavior.
10. Ensure reports, telemetry, and logs omit raw PII and credentials.
