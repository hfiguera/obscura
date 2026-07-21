# Operational Soak and Memory-Growth Validation

This protocol extends the one-minute operational benchmark with long-duration,
profile-wide workloads. It answers whether a prepared Obscura runtime remains
bounded under sustained reuse. It does not replace accuracy evaluation,
short-load capacity measurements, or application-specific production testing.

## Required Matrix

The canonical Apple/Emily matrix is:

| Profile | Concurrency | Minimum duration |
| --- | ---: | ---: |
| `:openmed_pii` | 4 | 30 minutes |
| `:openmed_pii` | 1 | 10 minutes |
| `:balanced` | 4 | 10 minutes |
| `:fast` | 4 | 10 minutes |

Every run interleaves all three authoritative selections:

- `generated_large/template_heldout`
- `synth_dataset_v2/all`
- `nemotron_pii_test_subset/all`

The runner verifies dataset content, ordered sample IDs, selection, entity
policy, scoring policy, model revisions, and asset hashes before promotion.
Reducing the datasets or durations creates an exploratory report that cannot
pass the authoritative schema.

## Runtime Contract

Each run:

1. Loads all datasets before runtime preparation.
2. Prepares the selected profile once with network access disabled.
3. Starts one supervised `RuntimeHost` with bounded in-flight work.
4. Runs a deterministic output probe for one sample from each dataset.
5. Starts fixed-stride, long-lived workers.
6. Reuses the same prepared runtime until the deadline.
7. Samples resources at least once per second.
8. Performs idle, explicit GC, and Emily cache-release observations.
9. Runs timeout, overload, gateway-crash recovery, and privacy probes.
10. Rejects the report if runtime lifecycle stages indicate reconstruction.

Apple model-backed runs require Emily device `gpu` and fallback policy
`raise`. Linux model-backed evidence requires separately proven EXLA
execution. The `:fast` profile is a BEAM CPU workload.

## Measurements

Per-minute windows use a bounded histogram rather than retaining every request
latency. Each window records:

- completed, failed, rejected, and timed-out requests;
- throughput;
- mean, p50, p95, p99, and maximum end-to-end latency.

The resource sampler records at least once per second:

- BEAM total, processes, binary, ETS, atom, and system memory;
- process RSS from the operating system;
- run queue and scheduler utilization;
- `Emily.Memory` active, cached, and peak allocator bytes when available;
- runtime-host completed and in-flight requests;
- runtime-host mailbox length.

Emily allocator values are direct MLX allocator statistics. They are not a
measurement of physical GPU residency. Process RSS is periodic sampling, not
an operating-system high-water counter.

## Growth Analysis

The post-warm baseline is the first sample after runtime preparation and the
six-request output-stability probe. For each memory or queue metric the report
contains:

- baseline, final, minimum, maximum, and median;
- absolute and percentage growth;
- first-half and second-half growth;
- full-run and final-half linear-regression slope;
- regression fit;
- rolling-median minimum, maximum, and median;
- a conservative plateau, continuous-growth, declining, or inconclusive trend;
- Pearson correlation with cumulative completed requests when both series
  have variance.

Correlation is evidence, not causation. A high coefficient can show that
memory rises with requests, but idle/GC/cache observations are still required
to distinguish live allocation from allocator caching.

## Post-Soak Diagnostics

After the canonical request period, the runner records:

1. state immediately before idle;
2. state after a 10-second idle period;
3. state after explicit GC of the runner and runtime host;
4. state after `Emily.Memory.clear_cache/0`, when supported.

Active allocator memory and cache memory are analyzed separately. Reclaimable
Emily cache growth must not be reported as retained live model memory.

## Classifications

`stable_plateau`
: RSS and live allocator final-half trends remain inside the report's
  metric-relative noise budget.

`allocator_caching`
: live allocation plateaus while allocator cache grows and is materially
  released by the explicit cache-clear observation.

`probable_leak`
: RSS and live allocator memory both continue growing and neither idle/GC nor
  release observations materially explain the growth.

`inconclusive`
: required measurements are unavailable, noisy, contradictory, or do not
  meet one of the stronger classifications.

These names are bounded conclusions for the measured source revision,
hardware, workload, and duration. Even `stable_plateau` is not a universal
proof that no leak can exist.

## Commands

Prepare the controlled Apple environment:

```sh
export OBSCURA_REAL_MODEL_BACKEND=emily
export OBSCURA_PRIVACY_FILTER_BACKEND=emily
export OBSCURA_EMILY_DEVICE=gpu
export OBSCURA_EMILY_FALLBACK=raise
export OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openmed-nemotron-v2
```

Run the canonical matrix:

```sh
mix obscura.operational.soak --profile openmed_pii --concurrency 4 --authoritative
mix obscura.operational.soak --profile openmed_pii --concurrency 1 --authoritative
mix obscura.operational.soak --profile balanced --concurrency 4 --authoritative
mix obscura.operational.soak --profile fast --concurrency 4 --authoritative
```

Short local harness checks must state an explicit duration and cannot be
promoted. Their report status is `exploratory`:

```sh
mix obscura.operational.soak \
  --profile fast \
  --concurrency 4 \
  --duration-ms 5000
```

Promote one complete JSON/Markdown pair:

```sh
mix obscura.operational.soak.promote \
  --report eval/reports/operational/soak/openmed_pii-c4-1800000.json
```

Verify committed evidence:

```sh
mix obscura.operational.soak.verify
```

## Promotion Boundary

Soak evidence has its own manifest:

- `eval/operational/soak-manifest.json`
- `eval/operational/soak-reports/`

It is intentionally separate from:

- recognition accuracy evidence in `eval/authoritative/manifest.json`;
- short operational evidence in `eval/operational/manifest.json`.

Promotion requires:

- a clean source revision;
- canonical profile, concurrency, and duration;
- all three exact datasets;
- offline, immutable assets;
- proven backend/device with no fallback;
- at least 95% expected resource-sample coverage;
- complete memory series, slopes, rolling statistics, and correlations;
- zero canonical failures, rejections, or timeouts;
- stable deterministic output;
- one prepared runtime and no per-request reconstruction;
- passing resilience and privacy probes;
- no raw values, checkpoint paths, credentials, or absolute local paths.

Working reports are not authoritative until their JSON and Markdown hashes
appear in the soak manifest.

## CI

Dependency-light CI verifies the committed soak manifest but does not execute
hour-long model workloads. The controlled model workflow contains separately
gated Apple/Emily and Linux/EXLA soak jobs. Those jobs generate working
artifacts for review and do not auto-promote evidence.

The Apple job is enabled only with
`OBSCURA_ENABLE_APPLE_SOAK_CI=true`. The Linux job is enabled only with
`OBSCURA_ENABLE_EXLA_SOAK_CI=true`. A skipped controlled-runner job means the
infrastructure was unavailable; it is not passing soak evidence.

Current measured results and their bounded interpretation are documented in
`docs/operational-soak-and-memory-report.md`.
