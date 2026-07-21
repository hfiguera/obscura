# Operational Soak and Memory Report

## Conclusion

All four required Apple/Emily soaks completed, passed the report schema, and
are promoted in the dedicated soak manifest.

No row met the `probable_leak` classification, but the release-level memory
conclusion remains **inconclusive**.

- The historical classifier labels `:openmed_pii` at concurrency 1 and 4 as
  `allocator_caching`. Live Emily memory returned to its pre-load baseline,
  while large cached allocations were released to zero by
  `Emily.Memory.clear_cache/0`. This distinguishes reclaimable cache from live
  growth during that run; it does not prove a production-duration bound.
- `:fast` and `:balanced` are `inconclusive` for retained memory at ten
  minutes. Both completed without failure, but their noisy RSS/BEAM series did
  not meet the conservative plateau rule.
- Sustained latency remains the important operational finding. Follow-up
  stage diagnostics reproduce `:balanced` model-serving slowdown. OpenMed's
  first/last decline is now explained primarily by the ordered workload
  cycling through different input lengths, not a monotonic 30-minute decay.

This records finite-run behavior for source `fd3dc8e`, the measured hardware,
the locked mixed workload, and the stated durations. It does **not** prove
bounded growth, a universal no-leak result, or production capacity.

## Environment

| Field | Value |
| --- | --- |
| Source commit | `fd3dc8ebfbf26baa4b65b86f6b73e8f9000bbfef` |
| Dirty source | `false` |
| Host | Apple M4 Max, 16 logical processors, 128 GiB |
| OS / architecture | Darwin 25.5.0 / aarch64 |
| Elixir / OTP | 1.20.2 / 29 |
| Nx / Emily | 0.12.1 / 0.7.2 |
| Model backend | Emily GPU, fallback `raise` |
| Fast backend | BEAM CPU |
| Network downloads | Disabled |

All model-backed reports prove actual backend `emily`, actual device `gpu`,
backend proof `true`, and fallback `false`. Linux/EXLA was not available and is
not presented as passing.

## Workload

Every row interleaves requests from:

- 648 `generated_large/template_heldout` samples;
- 1,500 `synth_dataset_v2/all` samples;
- 500 `nemotron_pii_test_subset/all` samples.

The concurrency-1 OpenMed row is too slow to visit every unique sample in ten
minutes, but it sends requests to all three datasets. The 30-minute OpenMed
row and both controls reach 100% unique-sample coverage for all selections.

| Profile | C | Duration | Completed | Req/s | Samples | Coverage | Fail/reject/timeout | Classification |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `:fast` | 4 | 10m | 10,591,487 | 17,652.45 | 600 | 100.00% | 0 / 0 / 0 | `inconclusive` |
| `:balanced` | 4 | 10m | 22,717 | 37.86 | 599 | 99.83% | 0 / 0 / 0 | `inconclusive` |
| `:openmed_pii` | 1 | 10m | 1,013 | 1.69 | 599 | 99.83% | 0 / 0 / 0 | `allocator_caching` |
| `:openmed_pii` | 4 | 30m | 6,404 | 3.55 | 1,799 | 99.94% | 0 / 0 / 0 | `allocator_caching` |

## Latency Stability

The table compares the first and last complete one-minute windows. It avoids
claiming a global percentile reconstructed from per-window summaries.

| Profile | First req/s | Last req/s | First p50/p95/p99 ms | Last p50/p95/p99 ms | Throughput retained | p95 ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `:fast` | 17,845.23 | 17,711.98 | 0.16 / 0.56 / 0.99 | 0.16 / 0.56 / 1.00 | 99.25% | 1.00x |
| `:balanced` | 55.00 | 33.00 | 73 / 75.5 / 76.5 | 125 / 155 / 180 | 60.00% | 2.05x |
| `:openmed_pii`, C1 | 2.07 | 1.40 | 325 / 1,250 / 3,150 | 285 / 1,950 / 5,300 | 67.74% | 1.56x |
| `:openmed_pii`, C4 | 3.95 | 1.37 | 815 / 2,550 / 3,300 | 2,500 / 6,150 / 9,250 | 34.60% | 2.41x |

`:fast` is operationally stable under this workload.

`:balanced` remains error-free but is not latency-stable: last-window
throughput is 40% lower and p95 is roughly double the first window.

OpenMed's first/last decline is real, but follow-up 30-minute diagnostics show
that it is not monotonic. Throughput later recovers above `8` req/s under
continuous load as the ordered workload returns to shorter inputs. Token
length, model execution, and log-prob conversion are the primary explanation;
allocator caching is not the primary latency cause. See
`docs/sustained-latency-diagnostic-report.md`.

## Host Memory

| Profile | RSS baseline | RSS final | RSS max | Growth | Final-half slope | R2 | Trend |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `:fast` | 0.178 GiB | 0.174 GiB | 0.208 GiB | -3.8 MiB | +4.44 MiB/min | 0.424 | `inconclusive` |
| `:balanced` | 1.556 GiB | 1.581 GiB | 1.594 GiB | +25.2 MiB | -0.10 MiB/min | 0.001 | `inconclusive` |
| `:openmed_pii`, C1 | 48.483 GiB | 0.829 GiB | 48.486 GiB | -48,797.8 MiB | -12.04 MiB/min | 0.011 | `inconclusive` |
| `:openmed_pii`, C4 | 48.491 GiB | 2.968 GiB | 48.563 GiB | -46,615.5 MiB | -0.04 MiB/min | 0.000 | `plateau` |

The OpenMed baseline occurs immediately after model preparation and the output
stability probe. It captures large transient process memory which is released
during the workload. It must not be treated as steady-state RSS.

The 30-minute OpenMed row provides the strongest retained-host-memory signal:
second-half RSS changes by `-35.3 MiB`, final-half slope is effectively flat,
and request/RSS correlation is `-0.144`.

`:fast` finishes below its initial RSS but has a noisy positive second-half
movement and does not pass the conservative plateau gate. `:balanced` finishes
25.2 MiB above baseline despite a flat, very-low-fit final-half regression.
Longer controls are needed before calling either a memory plateau.

## Emily Allocator

Emily active and cache statistics are allocator counters, not direct physical
GPU residency. Active, cache, and RSS peaks occur at different times and must
not be summed.

| Profile | Active baseline | Active peak | Settled active | Cache baseline | Cache peak | Cache before clear | Cache after clear |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `:balanced` | 1.320 GiB | 1.452 GiB | 1.320 GiB | 0.135 GiB | 0.135 GiB | 0.135 GiB | 0 |
| `:openmed_pii`, C1 | 2.607 GiB | 26.412 GiB | 2.607 GiB | 51.581 GiB | 99.537 GiB | 97.169 GiB | 0 |
| `:openmed_pii`, C4 | 2.607 GiB | 32.005 GiB | 2.607 GiB | 51.581 GiB | 99.537 GiB | 94.142 GiB | 0 |

The OpenMed evidence is consistent with allocator caching:

1. live active memory returns to baseline after the workload;
2. cache grows substantially;
3. explicit cache clear reduces cache to zero;
4. 30-minute correlations with completed requests are low: active `0.0135`,
   cache `0.0260`;
5. RSS reaches a final-half plateau.

This is not evidence that OpenMed is cheap or that memory is bounded. It needs
very large transient host and allocator headroom. The result only says that
the observed cache was reclaimable and live memory did not continuously
accumulate during this 30-minute observation.

## BEAM Memory

`:fast` BEAM total rises from `79.2 MiB` to `116.8 MiB`, with a final-half
slope of `+2.66 MiB/min` and request correlation `0.767`. RSS does not show the
same monotonic relationship, so the row remains inconclusive rather than a
probable leak.

`:balanced` BEAM total rises from `88.3 MiB` to `137.5 MiB`, but its final-half
slope is approximately flat at `-0.06 MiB/min`.

The OpenMed 30-minute row rises from `124.8 MiB` to `140.4 MiB`, with a
final-half slope of only `+0.014 MiB/min`. That does not indicate continuing
BEAM growth at the end of the measured run.

## Resilience and Reuse

Every row passes:

- request timeout handling;
- bounded overload rejection;
- supervised request-gateway crash recovery;
- successful request after recovery;
- privacy-safe report checks.

Every row records exactly one normal runtime build. Model, tokenizer,
checkpoint, parameter, and serving lifecycle stages are not repeated during
requests. Output fingerprints remain stable, and no report retains raw source
values.

## Production Meaning

The implementation works under sustained load: all required rows complete,
outputs remain stable, runtime reuse is proven, all resilience probes pass,
and no canonical request fails.

That does not make every profile production-ready:

- `:fast` is the only row with stable latency and throughput. Its ten-minute
  memory classification remains inconclusive.
- `:balanced` is still the best general accuracy profile, but sustained
  latency degrades and retained memory needs a longer run.
- Experimental `:openmed_pii` does not show a probable retained-memory leak in this finite
  run, but retained growth remains inconclusive. Its enormous transient/cache
  footprint requires strict admission control and large headroom. It should
  remain specialized and opt-in.

Sequence bucketing and raw-logit Viterbi conversion are the measured defaults
for experimental OpenMed and have fresh authoritative operational evidence. The remaining
memory task is a longer bounded-growth experiment under that exact policy.
Balanced still needs an alternating C4/C2 and cooldown experiment with
privileged Metal/thermal telemetry.

## Evidence

The source of truth is:

- `eval/operational/soak-manifest.json`
- `eval/operational/soak-reports/`
- `eval/operational/diagnostic-manifest.json`
- `eval/operational/diagnostic-reports/`

The soak manifest contains four rows, and the diagnostic manifest contains two
rows, all with committed JSON/Markdown SHA-256 hashes.
Working files under `eval/reports/operational/soak/` are not authoritative.
