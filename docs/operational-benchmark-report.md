# Authoritative Operational Benchmark Report

## Conclusion

The three stable profiles and one experimental measured alias complete the
authoritative Apple/Emily operational matrix without canonical request
failures, timeouts, rejections, output drift, backend fallback, or per-request
runtime construction.

The profiles have materially different operating envelopes:

- `:fast` is suitable for high-volume synchronous structured-PII detection.
- Stable `:balanced` is the best measured general model-backed operating
  point. Use concurrency `2` for tighter latency or `4` for
  throughput-oriented workers.
- Stable `:accurate` now uses the output-aware cascade and has the
  highest measured general F1. Its useful concurrency depends on workload:
  generated heldout peaks near C4, while Synth/Nemotron plateau around C4-C8.
  Higher concurrency mainly adds tail latency.
- `:openmed_pii` now uses the promoted `openmed_latency_v1` default and is
  materially faster than the superseded matrix. It remains an experimental,
  tail-heavy specialist requiring bounded queues, strict admission control,
  explicit memory headroom, and deployment-specific evaluation.

These are operational conclusions only. Recognition quality remains governed
by `eval/authoritative/manifest.json` and `docs/benchmark-status.md`.

## Provenance

| Field | Value |
| --- | --- |
| Base profile source commit | `ab84d4ce5a4f4c0c482228b94b30584b8e687de8` |
| Refreshed OpenMed source commit | `226edc36bf7bd39a1969ef7a112863ea6e0ba396` |
| Refreshed accurate source commit | `9ebb01b70ffa427ac8ce2bfd6fbaa276e9fc21d9` |
| Host | Apple M4 Max, 16 logical processors, 128 GiB memory |
| OS | Darwin `25.5.0`, `aarch64-apple-darwin25.5.0` |
| Elixir / OTP | Elixir `1.20.2`, OTP `29` |
| Nx / Emily | Nx `0.12.1`, Emily `0.7.2` |
| Model backend | Emily GPU, fallback `raise` |
| Fast backend | BEAM CPU |
| Warm repetitions | `2` complete dataset passes per concurrency |
| Concurrency | `1`, `2`, `4`, `8`, `16` |
| Sustained load | 60 seconds, concurrency `4` |
| Downloads | Prohibited; all assets preprovisioned |
| Linux/EXLA | Not measured on this Apple runner |

Every model report proves `actual_backend: emily`, `actual_device: gpu`,
`backend_proven: true`, and `fallback_occurred: false`. The `:fast` reports
prove the requested BEAM CPU path.

The operational manifest contains 12 promoted rows: four measured aliases by
three locked datasets. The OpenMed and accurate rows use their refreshed source
commits; the other six retain their prior clean source. Every row includes dataset,
selection, ordered sample-ID, entity-policy, scoring, model revision, and
asset hashes.

Every refreshed OpenMed row records the exact default policy:
`openmed_latency_v1`, buckets `[192, 256, 384, 512, 768]`, threshold `129`,
Viterbi, and raw logits. `matches_default=true` is schema-validated.

## Cold Lifecycle

Cold timing starts a fresh OS `mix` process with preprovisioned offline assets.
First inference includes lazy Nx compilation because Nx does not expose that
compile duration independently.

| Profile | Ready ms | Runtime preparation ms | First inference ms | Cold/warm p50 ratio |
| --- | ---: | ---: | ---: | ---: |
| `:fast` | 374.869 | 2.268 | 12.324 | 3288.32x |
| `:balanced` | 1198.078 | 745.083 | 75.447 | 48.84x |
| `:accurate` | 1720.101 | 1262.933 | 72.778 | 40.99x |
| `:openmed_pii` | 28763.889 | 26559.983 | 1667.196 | 129.18x |

The cold/warm ratio is a projection showing why runtime construction must stay
out of request handling. It is not a canonical per-request benchmark.

OpenMed readiness is dominated by parameter loading. Applications using this
profile must prepare it during controlled startup and expose readiness only
after the prepared runtime is available.

## Warm Load

The table keeps the most useful comparison points. Complete concurrency rows,
including p50, p95, p99, maximum, service time, resources, and both
repetitions, are in `eval/operational/reports/`.

| Profile | Dataset | C1 p50/p95/p99 ms | C1 req/s | C4 p95 ms / req/s | C16 p95/p99 ms | C16 req/s |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `:fast` | generated heldout | 0.114 / 0.193 / 0.248 | 7862.64 | 0.236 / 24174.81 | 0.373 / 0.502 | 55229.14 |
| `:fast` | synth v2 | 0.117 / 0.189 / 0.241 | 7730.92 | 0.255 / 22375.47 | 0.363 / 0.453 | 53828.20 |
| `:fast` | Nemotron subset | 0.375 / 0.933 / 1.255 | 2259.31 | 0.953 / 8131.52 | 1.181 / 1.563 | 22795.10 |
| `:balanced` | generated heldout | 21.820 / 22.778 / 23.269 | 45.56 | 78.700 / 52.15 | 299.512 / 300.998 | 54.09 |
| `:balanced` | synth v2 | 24.531 / 26.201 / 26.803 | 40.88 | 97.629 / 42.75 | 372.044 / 395.628 | 45.10 |
| `:balanced` | Nemotron subset | 26.195 / 29.440 / 31.208 | 37.80 | 94.755 / 43.04 | 365.581 / 367.037 | 44.48 |
| `:accurate` | generated heldout | 41.966 / 43.776 / 44.593 | 29.72 | 157.943 / 33.68 | 1066.570 / 1095.273 | 20.30 |
| `:accurate` | synth v2 | 54.521 / 58.713 / 66.571 | 20.54 | 205.460 / 23.09 | 807.615 / 874.161 | 23.40 |
| `:accurate` | Nemotron subset | 54.765 / 58.703 / 61.320 | 20.19 | 207.449 / 22.41 | 858.056 / 901.091 | 22.79 |
| `:openmed_pii` | generated heldout | 222.666 / 309.593 / 355.049 | 4.38 | 628.129 / 8.63 | 2007.619 / 2280.503 | 9.77 |
| `:openmed_pii` | synth v2 | 220.706 / 349.203 / 438.342 | 4.25 | 639.937 / 9.07 | 2117.998 / 2427.242 | 9.79 |
| `:openmed_pii` | Nemotron subset | 741.473 / 1808.185 / 2583.496 | 1.16 | 6670.706 / 1.21 | 25497.807 / 33111.646 | 1.24 |

Every row completed with:

- two full repetitions;
- zero failed, timed-out, or rejected canonical requests;
- identical output fingerprints across repetitions;
- exactly one prepared profile runtime.

### OpenMed Refresh Delta

The comparison below uses the same host, backend, datasets, concurrency, and
two-repetition protocol. Negative p95 deltas are improvements.

| Dataset | C1 req/s delta | C1 p95 delta | C4 req/s delta | C4 p95 delta |
| --- | ---: | ---: | ---: | ---: |
| generated heldout | +18.85% | -37.35% | +35.94% | -52.35% |
| synth v2 | +34.71% | -43.93% | +63.66% | -57.56% |
| Nemotron subset | +72.48% | -52.10% | +51.77% | -45.90% |

These are measured gains, not estimates. The old and new operational rows are
from clean commits, and every refreshed cell has two stable-output repetitions.

## Capacity Decisions

### Fast

Throughput continues to improve through concurrency `16`, while p99 remains
below `1.6 ms` on all three selections. The tested maximum is a reasonable
starting admission limit, but it is not a proven ceiling.

### Balanced

Concurrency `2` captures most of the throughput gain with materially lower
tail latency than `4` or above. Concurrency `4` is reasonable for bounded
worker pools when roughly `79-98 ms` p95 is acceptable. Concurrency `16`
improves throughput only modestly over `4` while pushing p95 to
`300-372 ms`.

### Accurate

Use concurrency `1` for interactive work. Generated heldout improves from
`29.72 req/s` at C1 to `33.68 req/s` at C4, then declines; Synth and Nemotron
reach roughly `23 req/s` around C4-C8. C4 p95 is `158-207 ms`, while C16 p95
reaches `808-1067 ms`. Use C2 or C4 for bounded throughput only when those tail
latencies fit the deployment SLO.

### OpenMed PII

Generated heldout and synth approach `9-10` req/s at concurrency `4-16`, but
tail latency grows with queueing. Concurrency `4` is a practical starting point
for bounded broad-input workers. Nemotron behaves differently: concurrency
`2` is the best measured throughput point at `1.38` req/s and p95 `2.83`
seconds. Concurrency `4` falls to `1.21` req/s with p95 `6.67` seconds.

Use concurrency `1` for latency-sensitive long inputs and `2` for bounded
Nemotron throughput. Do not use concurrency `16` for interactive OpenMed work
on this host.

## Resource Peaks

These are maxima across the three separately measured warm dataset runs.
Emily values are direct allocator statistics. They are not inferred physical
GPU residency and include allocator/cache behavior.

| Profile | Peak BEAM | Peak process RSS | Peak Emily allocator | Interpretation |
| --- | ---: | ---: | ---: | --- |
| `:fast` | 85.1 MiB | 184.7 MiB | unavailable | Low host footprint |
| `:balanced` | 279.9 MiB | 1.754 GiB | 1.453 GiB | Practical single-model footprint |
| `:accurate` | 334.0 MiB | 3.157 GiB | 2.773 GiB | Two-model footprint |
| `:openmed_pii` | 199.7 MiB | 48.303 GiB | 41.293 GiB | Severe transient pressure; retained growth inconclusive |

OpenMed's high peaks occur in different dataset runs and must not be summed.
They still require substantial host memory headroom. The Nemotron selection
produces the largest Emily peak; generated heldout produces the largest
sampled process RSS.

## Sustained Load

Sustained load is one profile-wide mixed workload. It cycles the concatenated
ordered samples from all three locked datasets for 60 seconds at concurrency
`4`. The same profile-level sustained result is referenced from each of that
profile's three dataset reports; it is not a dataset-specific sustained row.

| Profile | Completed | Throughput req/s | Drift ratio | RSS growth | Fail/timeout/reject |
| --- | ---: | ---: | ---: | ---: | ---: |
| `:fast` | 1,097,572 | 18292.69 | 1.011 | -8.6 MiB | 0 / 0 / 0 |
| `:balanced` | 2,592 | 43.17 | 1.011 | -64.2 MiB | 0 / 0 / 0 |
| `:accurate` | 1,450 | 24.12 | 1.087 | -94.8 MiB | 0 / 0 / 0 |
| `:openmed_pii` | 568 | 9.39 | 0.877 | +7.4 MiB | 0 / 0 / 0 |

The first three profiles are stable over the 60-second window. Refreshed
OpenMed also becomes faster in the second half, so drift below `1.0` is
warm-up improvement, not degradation. Its positive sampled RSS growth and
large transient peaks do not prove a leak, but the memory conclusion remains
inconclusive without a longer bounded-growth experiment.

## Resilience And Reuse

Every profile passed:

- structured request timeout handling;
- bounded overload rejection;
- supervised request-gateway replacement;
- an unavailable response from the old gateway;
- successful serving after gateway replacement;
- privacy-safe report payload checks.

The recovery test intentionally replaces the request gateway around immutable
prepared runtime resources. It does not claim recovery from a GPU driver,
native allocator, or model-resource failure.

Lifecycle stage counts prove one normal runtime build. No report detected
model, tokenizer, checkpoint, or serving reconstruction inside request
handling.

## Accuracy Context

Operational speed does not change the authoritative quality decision:

- `:accurate` has the best exact-span F1 across the three shared eight-entity
  datasets.
- `:balanced` remains the practical model-backed recommendation because it
  uses one model and has lower latency and memory cost.
- `:openmed_pii` has the best Nemotron recall and F2, but its lower precision
  and high operational cost make it specialized.
- `:fast` remains the high-precision structured-PII path and does not replace
  broad model-backed NER.

See `docs/benchmark-status.md` for exact quality metrics and the promoted
Presidio comparison.

## Long-Soak Follow-Up

The historical 10- and 30-minute Apple/Emily soaks are promoted separately.
They do not classify OpenMed as a probable leak, and cache clearing succeeded,
but they do not satisfy a production-duration bounded-growth claim. Memory is
therefore explicitly **inconclusive**. Follow-up diagnostics show that the
historical latency decline was a repeatable workload-length cycle.
`:balanced` has a separate fixed-shape model-serving slowdown. See
`docs/operational-soak-and-memory-report.md` and
`docs/sustained-latency-diagnostic-report.md`.

## Remaining Work

1. Run both operational schemas on a controlled Linux/EXLA host. Do not compare
   that result directly with Apple/Emily unless hardware and backend
   differences are stated.
2. Run a longer OpenMed memory-focused experiment before claiming bounded
   retained growth.
3. Run longer `:fast` and `:balanced` controls because their ten-minute memory
   classifications remain inconclusive.
4. Evaluate batching or vectorized decoder work against this exact source,
   dataset, and report protocol.
5. Re-run both matrices after performance changes and promote only
   reproducible improvements without accuracy or parity regressions.

## Evidence

The source of truth is:

- `eval/operational/manifest.json`
- `eval/operational/reports/`

Working files under `eval/reports/operational/` are not authoritative unless
their hashes are promoted in the operational manifest.

The OpenMed optimization audit and its before/after operational deltas are in
`openmed-sequence-bucketing-logprob-report.md`.
