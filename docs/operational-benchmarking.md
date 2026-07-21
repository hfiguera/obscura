# Authoritative Operational Benchmarking

Operational evidence answers a different question from accuracy evidence.
`eval/authoritative/manifest.json` proves recognition quality under a shared
scoring protocol. `eval/operational/manifest.json` proves how measured product profiles
behave under startup, concurrency, sustained load, resource pressure, and
failure. Neither manifest substitutes for the other.

## Scope

The operational matrix covers all three stable product profiles:

- `:fast`
- `:balanced`
- `:accurate`

It also preserves controlled evidence for the experimental OpenMed specialist:

- `:openmed_pii`

Every profile runs the exact ordered sample IDs locked by:

- `generated_large/template_heldout`
- `synth_dataset_v2/all`
- `nemotron_pii_test_subset/all`

The loader verifies dataset SHA-256, sample count, ordered sample-ID SHA-256,
entity-policy SHA-256, scoring SHA-256, and selection-file SHA-256 before a
request is measured. Each operational report also imports immutable
model/checkpoint revisions and asset hashes from the promoted accuracy
manifest.

This protocol does not tune recognizers, thresholds, label maps, or conflict
policies.

## Canonical Environments

Apple model profiles use Emily/Metal:

```sh
export OBSCURA_REAL_MODEL_BACKEND=emily
export OBSCURA_PRIVACY_FILTER_BACKEND=emily
export OBSCURA_EMILY_DEVICE=gpu
export OBSCURA_EMILY_FALLBACK=raise
export OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openmed-nemotron-v2
```

The report must prove the actual Emily backend and GPU device. Any fallback,
unknown backend, or fallback policy other than `raise` prevents promotion.
`:fast` runs on BEAM CPU and is not presented as directly latency-comparable
with GPU profiles.

Linux model profiles use EXLA only on a real controlled Linux runner. The
report must prove EXLA as the actual backend. The Apple report marks Linux/EXLA
unavailable; it never treats an unexecuted environment as passing.

## Asset Policy

Canonical runs are process-cold but asset-warm:

- model, tokenizer, and checkpoint files must already exist;
- Bumblebee model and tokenizer repository sources use `offline: true`;
- network downloads are prohibited;
- no empty-cache or download timing is claimed;
- model assets and caches are never copied into reports or Git.

An empty-cache download experiment is a separate distribution/network
benchmark and cannot be promoted into this manifest.

## Cold Lifecycle

The parent task launches a new OS `mix` process for each profile. The child
records:

- application/dependency startup after task dispatch;
- backend configuration;
- model registry lookup;
- model loading;
- tokenizer loading;
- checkpoint layout/config/label/weight/dtype/parameter loading;
- compiler application startup;
- serving construction;
- first inference;
- total parent-observed OS process time until ready.

Nx performs lazy compilation during first execution but does not expose that
compilation as an independent public timing. Reports therefore label first
inference as **compile-inclusive**. They do not manufacture a standalone
compile duration.

## Warm Load

The canonical runtime is prepared exactly once and reused. Each dataset runs
at concurrency `1`, `2`, `4`, `8`, and `16`, with at least two repetitions.
The load runner is closed-loop and bounded by `Task.async_stream/3` plus the
runtime gateway's `max_in_flight`.

Each row records:

- elapsed time and completed throughput;
- mean, p50, p95, p99, and maximum end-to-end latency;
- service latency;
- completed, failed, rejected, and timed-out requests;
- deterministic output fingerprint;
- BEAM, RSS, scheduler, and directly measurable GPU resources.

The inline Nx serving path does not expose queue duration independently.
Reports mark queue time unavailable rather than deriving it from unrelated
timers.

Percentiles use nearest-rank within each repetition. The aggregate row reports
the mean of repetition percentiles and retains every repetition in JSON.

## Resource Measurement

| Resource | Source | Meaning |
| --- | --- | --- |
| BEAM total memory | `:erlang.memory(:total)` | VM-managed memory |
| Process RSS | OS `ps` sampling | BEAM process resident set |
| Run queue | `:erlang.statistics(:run_queue)` | runnable work |
| Scheduler utilization | scheduler wall-time counters | cumulative VM utilization |
| Emily memory | `Emily.Memory.stats/0` | active, peak, and cached MLX allocator bytes |
| EXLA GPU memory | unavailable | not inferred without a direct allocator API |

Sampling is periodic, so RSS peak means the highest observed sample, not an OS
kernel high-water mark. GPU memory is never estimated from checkpoint size.

## Sustained Load

The authoritative default is one 60-second profile-wide mixed workload at
concurrency 4. It cycles the concatenated ordered samples from all three
locked datasets with bounded workers. That result is referenced from each
dataset-specific report for the profile; it is not a separate sustained run
for each dataset. It records:

- total throughput;
- first-half versus second-half mean latency;
- latency drift ratio;
- sampled RSS growth;
- completed, failed, rejected, and timed-out requests.

A shorter duration is useful for local harness checks but cannot replace the
documented authoritative duration.

`--sustained-request-count` can cap nonauthoritative experiments. Promotion
still requires the full configured duration and `stop_reason: duration`.

## Resilience And Privacy

Each profile executes controlled probes for:

- request timeout and worker termination;
- bounded overload and structured rejection;
- request-gateway crash under a supervisor;
- a request against the unavailable old gateway;
- a successful request after supervised replacement;
- runtime reuse across gateway replacement.

Errors contain stable codes, component identity, and retryability only. The
load runner discards detected text and keeps only entity type and byte offsets
long enough to compute an output hash. JSON/Markdown promotion recursively
rejects raw-value keys, and reports reject absolute local paths.

The crash probe kills the request gateway, not immutable prepared model
resources. This proves request-process recovery and continued runtime reuse; it
does not claim that GPU driver failure can recover without reinitialization.

## Runtime Reuse

Lifecycle observers count model, tokenizer, checkpoint, compiler-start, and
serving-construction stages. Normal execution must show one profile preparation
and no rebuild during requests.

The noncanonical per-request-construction anti-pattern is represented by the
isolated fresh-process lifecycle cost relative to warm p50. It is clearly
marked as a projection and is excluded from canonical warm measurements.
Normal per-request reconstruction is a promotion failure.

## Commands

Run the full Apple matrix:

```sh
OBSCURA_REAL_MODEL_BACKEND=emily \
OBSCURA_PRIVACY_FILTER_BACKEND=emily \
OBSCURA_EMILY_DEVICE=gpu \
OBSCURA_EMILY_FALLBACK=raise \
OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openmed-nemotron-v2 \
mix obscura.operational.benchmark
```

Run one profile without weakening the matrix for that profile:

```sh
mix obscura.operational.benchmark --profiles fast
```

Useful nonauthoritative harness check:

```sh
mix obscura.operational.benchmark \
  --profiles fast \
  --datasets generated_large_template_heldout \
  --sustained-duration-ms 1000
```

Promote each complete JSON/Markdown pair after a clean-source run:

```sh
mix obscura.operational.promote \
  --report eval/reports/operational/fast-generated_large_template_heldout.json
```

Verify promoted hashes:

```sh
mix obscura.operational.verify
```

## Promotion Rules

Promotion rejects:

- dirty source state;
- missing fresh-process cold evidence;
- downloads or non-preprovisioned assets;
- missing concurrency levels or fewer than two repetitions;
- failed/timed-out canonical requests;
- inconsistent output fingerprints;
- incomplete dataset or asset fingerprints;
- Emily fallback, unknown actual backend, or unproven device;
- missing timeout, overload, crash-recovery, or privacy probes;
- per-request runtime reconstruction;
- sensitive keys or absolute machine paths;
- missing Markdown pair or later artifact hash drift.

## Interpretation

Throughput and latency are directly comparable only when hardware fingerprint,
OS, OTP/Elixir, dependency lock, backend, device, compile settings, dataset,
sample order, repetition count, and duration match. Apple/Emily, Linux/EXLA,
and BEAM CPU rows describe distinct execution environments.

Operational viability requires more than a low mean. A profile must have
bounded p99, stable sustained behavior, acceptable peak memory, zero canonical
failures, proven runtime reuse, and recovery behavior compatible with the host
application's availability target.

The current Apple/Emily results, capacity recommendations, resource peaks, and
remaining work are in `docs/operational-benchmark-report.md`.

## Long-Duration Soaks

The one-minute sustained-load row is a capacity and short-stability signal. It
is not sufficient to classify long-run memory behavior. Canonical 10- and
30-minute reuse tests, per-second detailed memory series, final-half slopes,
rolling medians, request correlations, idle/GC/cache observations, and the
separate promotion boundary are defined in
`docs/operational-soak-and-memory.md`.
