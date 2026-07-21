# Evaluation

Obscura separates dependency-light correctness, governed product benchmarks,
optional real-model validation, and external Python comparisons. Only reports
promoted by `eval/authoritative/manifest.json` are current product evidence.

## Deterministic Smoke

These commands need no model assets, accelerator, remote service, or network:

```sh
mix obscura.fixtures
mix obscura.fixtures --suite accuracy
mix obscura.eval \
  --compatibility \
  --dataset generated_small \
  --profile fast \
  --limit 5
```

Fixture failures are blocking correctness failures. The small compatibility
run is a pipeline smoke, not an accuracy claim.

## Authoritative Benchmarks

The manifest promotes a 4-profile by 3-dataset matrix with repeated runs:

```sh
mix ci.authoritative_validate
mix obscura.benchmarks.promote --help
```

Promotion verifies report hashes, JSON/Markdown agreement, profile identity,
dataset fingerprints, immutable model/checkpoint identity, dependency and
backend metadata, exact and IoU metrics, per-entity metrics, repeated accuracy
counts, and sanitized output. It rejects skipped, fake-serving, gold-derived,
or incomplete evidence.

Current metrics and regression policy are in `docs/benchmark-status.md`.

## Optional Real Models

Real runs require explicit dependencies, assets, backend, and fallback policy.
They must prepare reusable runtimes outside request handling:

```sh
OBSCURA_REAL_MODEL=1 \
OBSCURA_REAL_MODEL_BACKEND=emily \
OBSCURA_EMILY_FALLBACK=raise \
mix ci.real_model_smoke
```

Apple GPU evidence is valid only on a controlled Apple Silicon runner when
runtime metadata reports Metal/GPU and fallback is forbidden. EXLA presence is
not GPU proof. Setup and readiness commands are documented in
`docs/optional-dependencies-and-assets.md` and `docs/profiles.md`.

## External Python References

Python Presidio, GLiNER, and OpenMed comparisons are optional reference jobs.
Use their pinned environments under `eval/presidio_adapter/` and the relevant
research guide. A promoted comparison must record the Python lock, package and
model revisions, sample IDs, dataset fingerprint, and entity mapping policy.
Python outputs do not become authoritative merely by being committed under
`eval/reports/`.

## Dataset Preparation

Pinned Presidio-Research benchmark snapshots are committed with the repository:

```text
eval/datasets/presidio_research/
```

Their provenance, checksums, and applicable license notices live beside the
snapshots. Larger external datasets and model assets remain cache-managed and
are not committed. The authoritative manifest records dataset source, split,
sample count, and SHA-256 fingerprint. Threshold selection belongs on
`template_train`; final claims use `template_heldout` and external datasets.
Missing or checksum-mismatched data must fail explicitly and must not be
promoted.

## Report Policy

- `eval/authoritative/`: governed release-relevant reports and manifest.
- `eval/reports/`: ignored local experiment and working output. Historical
  development reports are retained on the archived development branch, not in
  the release tree.
- `eval/predictions/`: ignored evaluator interchange files, never product
  claims by location alone.
- `eval/presidio_adapter/`: pinned external-reference tooling.

Do not infer status from filenames containing `final`, `best`, or a version.
Use the authoritative manifest.

## Reproducibility

Every promoted run records the code commit and dirty state, UTC timestamp,
dataset fingerprint, stable and resolved profile, immutable model/tokenizer or
checkpoint identity, dependency versions, OS/architecture/hardware, requested
and actual backend/device, fallback policy, compile options, warmup/repetition
counts, command/options, accuracy metrics, and latency summary.

Latency comparisons are meaningful only on the same hardware, backend, device,
compile settings, and dataset fingerprint. Accuracy counts must agree across
repetitions for a fixed deterministic configuration.

## Privacy

Committed reports omit source text, detected values, credentials, model tokens,
and raw provider payloads. Prediction exports use character offsets for Python
evaluator compatibility and omit text/value fields by default. Apart from the
reviewed, licensed synthetic snapshots under `eval/datasets/`, never upload raw
external datasets, model credentials, or caches as CI artifacts.
