# Efficient CPU profile

This is the unpublished `:efficient` release candidate for the 0.2 line.
Installation from public release URLs becomes available only after publication.
For this checkout, use `--from-source --allow-download` or the verified local
binaries recorded in the asset manifest. It combines
Obscura's deterministic recognizers with a native port of spaCy's pinned
`en_core_web_lg` 3.8.0 NER model and the frozen `efficient_v1` boundary policy.
Use it when CPU cost and memory matter and English person/location recognition
is needed. `:balanced` remains the stronger general accuracy choice on the
existing shared benchmarks. This profile does not replace `:fast` for minimum
dependencies or `:accurate` for the best measured general accuracy.

Linux x86-64 and ARM64 servers are the production targets and the focus of
release CI. Apple Silicon macOS is supported for local development on the
validated environment; compatibility with older macOS versions is outside
the release requirements.

The experimental `:spacy_cpu` alias remains available with its original span
policy. It does not silently acquire the new form-field boundary rules.

## Install once, prepare at startup

Install the platform libraries: `brew install pcre2` on Apple Silicon macOS,
or `apt-get install curl libopenblas0-pthread libpcre2-8-0` on supported Debian/Ubuntu
Linux. Use the LP64 OpenBLAS ABI, not an OpenBLAS64/ILP64 library.

For the dedicated provisioning environment, install uv **0.12.1** and ensure `curl` is available. Then run:

```sh
mix obscura.efficient.install --allow-download
mix obscura.profile.check --profile efficient --prepare --offline --json
```

The installer downloads a native executable whose SHA-256 is pinned in the
installed Obscura package. It downloads Explosion's official model wheel,
verifies its pinned SHA-256, creates a temporary Python 3.11.15 environment
from hashed requirements, and exports five verified native files. It retains
the upstream license notices and removes the temporary environment. Presidio,
its evaluator, and this repository's evaluation environments are unnecessary.
Python, uv, Rust, Nx, Bumblebee, and GPU drivers are unnecessary **at inference**.

For an offline installation using previously exported assets:

```sh
mix obscura.efficient.install \
  --native-binary /staging/obscura-efficient-v1-x86_64-unknown-linux-gnu \
  --model-dir /staging/verified-model
```

A source-build alternative is `mix obscura.efficient.install --from-source
--allow-download`; this requires Rust 1.90.0 with the host target, a C linker,
and PCRE2/OpenBLAS development libraries. Supplying `--model-dir` and omitting
`--allow-download` uses only cached Cargo dependencies and local model files.
Ordinary dependency compilation and analysis never invoke this installer.

The default destination is the OS user cache under `obscura/efficient/v1`.
Use `--destination /opt/obscura/efficient/v1` when building a deployment image,
then set `OBSCURA_EFFICIENT_ASSET_DIR` to that directory for the application.
This is preferable to depending on the build user's cache in a release.
Explicit `:model_dir`/`:native_binary` options and the legacy
`OBSCURA_SPACY_MODEL_DIR`/`OBSCURA_SPACY_BINARY` variables remain supported.

```elixir
{:ok, runtime} = Obscura.Profile.prepare(:efficient, workers: 2)
{:ok, detections} =
  Obscura.analyze("José García lives in London.", profile: runtime)
```

Reuse the runtime. For supervised ownership, add
`{Obscura.Profile.Preparer, profile: :efficient, name: MyApp.Efficient,
prepare_options: [workers: 2]}` to the supervision tree and obtain the ready
runtime with `Obscura.Profile.Preparer.await(MyApp.Efficient)`. Stopping the
preparer stops its native workers. A directly prepared runtime belongs to its
caller unless `:runtime_owner` is supplied; keep that owner alive.

## Frozen contract

| Area | Contract |
| --- | --- |
| Production platforms | glibc Linux x86-64 and ARM64. Prebuilt Linux binaries require glibc 2.36 or later, OpenBLAS LP64, and PCRE2 10.x. |
| Development platform | Apple Silicon macOS, locally validated on macOS 26.6.2. No compatibility promise for older macOS versions. |
| Unsupported | Windows, Intel macOS, Alpine/musl Linux, other CPU architectures |
| Language | English NER; valid UTF-8 input and byte offsets |
| Entities | `:credit_card`, `:date_time`, `:domain`, `:email`, `:iban`, `:ip_address`, `:location`, `:person`, `:phone`, `:street_address`, `:title`, `:url`, `:us_ssn` |
| Model contribution | `PERSON` becomes `:person`; `GPE`, `LOC`, and `FAC` become `:location`; no organization NER. Other entities use existing deterministic/context recognizers. |
| Scores | NER's assigned 0.85 is a ranking score, not calibrated confidence |
| Boundary policy | Trim outer form/Markdown punctuation, stop at a following form field, include adjacent supported honorifics, and expand an existing location within a labeled address field of at most 256 bytes |
| Capacity | Integer `workers: 1..4`, default 1; one native request per worker; math-library threads fixed to 1 |
| Limits | 1,048,576 UTF-8 input bytes, 10,000 tokens, 8 MiB response frame; native NER can reject long text within the byte limit |
| Deadline | Integer `request_timeout: 1..300_000` milliseconds, default 30,000 |
| Admission | Immediate busy error when all workers are reserved; the pool does not retain a queue of source texts |
| Failure | Controlled error tuple; no automatic fallback to `:fast` and no partial successful redaction on a model failure |
| Recovery | Faulted/expired in-flight workers are discarded and replaced; at most five restart attempts in five seconds. Exhaustion can leave reduced/unavailable capacity; restart the owning preparer after correcting the cause. |
| Network | Explicit provisioning only; no network during preparation of local assets or inference |
| Assets | About 408 MiB on disk; vectors are memory mapped. Runtime RSS depends on touched pages and worker count. |

Errors preserve the existing public diagnostic/recognizer error tuple contract;
do not branch on rendered exception text. The internal `:spacy_*` worker
reasons and status fields are implementation details. No implicit chunking is
performed. Applications must choose document splitting and cross-chunk policy
explicitly. Check readiness before accepting traffic and retry busy errors
with application-level bounds and backoff.

## Asset upgrades and provenance

`efficient-v1`, native protocol 1, model version 3.8.0, and boundary policy
`efficient_v1` are pinned. A new model, tokenizer, decoder, or boundary policy
requires a new asset/policy version, independent accuracy and workload checks,
and release notes. The installer never follows a `latest` model tag. A failed
installation removes its staging directory and leaves an existing installation
untouched. Existing valid installations are verified and reused; place an
upgrade in a new directory, prepare it, then switch application runtimes. Keep
old assets immutable until their workers have stopped so rollback remains safe.

The only accepted legacy model metadata hash is the explicitly recorded
`:spacy_cpu` export. Its four binary files must match the same pinned hashes.
No arbitrary model directories or replacements pass verification.

The model wheel's publisher license is MIT (ExplosionAI GmbH, 2021). Its
`LICENSES_SOURCES` identifies OntoNotes 5 as commercially licensed by Explosion,
WordNet 3.0 under its own notice, and Explosion's vectors as CC0. Preserve both
upstream notice files. This is a record of publisher terms and provenance,
not a new grant covering upstream training corpora. Obscura distributes its
MIT native implementation and release executables; model weights are fetched
from Explosion and exported locally, outside the Hex package and native release.
See [asset licensing](model-asset-licensing.md) and
[native third-party notices](../native/spacy_cpu/THIRD_PARTY_NOTICES.md).

The versioned asset manifest is `priv/obscura/efficient-assets.json`.
`native/spacy_cpu/export-requirements.txt` freezes the independent export
dependencies with hashes. Rust 1.90.0, Cargo.lock, and the digest/snapshot-pinned
[Linux recipe](../native/spacy_cpu/release/Dockerfile) make native builds
repeatable. macOS additionally depends on its recorded Apple SDK and PCRE2
installation; the build normalizes the content-derived Mach-O UUID and ad-hoc
signature. Reproducibility means identical bytes for the recorded build
environment, not identical output across different SDKs or library toolchains.

## Evidence and limits

The [release evaluation](../eval/efficient/README.md) uses separate development
and untouched test sets. On 5,000 synthetic application-like test documents,
exact-span F1 is 0.6654 for `:efficient`, 0.6406 for the original native profile,
0.6351 for `:fast`, and 0.6102 for pinned Presidio. Efficient has fewer false
positives than Presidio but misses more gold PII spans. Full postal addresses
remain a substantial weakness; partial redaction must not be mistaken for
complete address coverage. These labels and this eight-entity mapping differ
from the earlier authoritative benchmarks, so their headline scores are not
directly comparable.

Synthetic public data and a bounded sustained-load test do not establish
universal accuracy, hours-long leak freedom, or a deployment-specific SLO.
Validate real application traffic and data policies before relying on the profile.
