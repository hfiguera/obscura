# Operational Benchmark: openmed_pii / nemotron_pii_test_subset_all

Status: `complete`

Dataset SHA-256: `a36582d34f64ba871a604eabd53a8d92f0628b76ddb027105ac0f9d9a3042577`
Selection SHA-256: `a38604f5ce5e556d0bc23aa0ac1f58a95948c1748f2f752e21f126e22d3468cd`
Samples: `500`
Source commit: `226edc36bf7bd39a1969ef7a112863ea6e0ba396`

## Cold Lifecycle

- Fresh OS process: `true`
- Application start: `29.478 ms`
- Runtime preparation: `26559.983 ms`
- Compile-inclusive first inference: `1667.196 ms`
- Total process ready: `28763.889 ms`
- Empty-cache/network timing: unavailable; assets were pre-provisioned and offline loading was enforced.

Nx does not expose lazy compilation as an independent public timing. First
inference is therefore explicitly compile-inclusive.

## Warm Load

| Concurrency | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed | Failed | Rejected | Timed out |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1.155 | 741.473 | 1808.185 | 2583.496 | 1000 | 0 | 0 | 0 |
| 2 | 1.378 | 1251.922 | 2829.918 | 3936.150 | 1000 | 0 | 0 | 0 |
| 4 | 1.205 | 2897.494 | 6670.706 | 8885.924 | 1000 | 0 | 0 | 0 |
| 8 | 1.208 | 5774.047 | 13532.735 | 16975.245 | 1000 | 0 | 0 | 0 |
| 16 | 1.241 | 11393.782 | 25497.806 | 33111.646 | 1000 | 0 | 0 | 0 |

Queue time is unavailable because the inline Nx serving path does not expose
it independently. Service and end-to-end latency are recorded separately in
the JSON artifact.

## Sustained Load

- Requested duration: `60000 ms`
- Measured duration: `60468.506 ms`
- Throughput: `9.393 req/s`
- Latency drift ratio: `0.877`
- RSS growth: `7733248 bytes`
- Failures: `0`

## Resilience And Reuse

- Timeout behavior: `passed`
- Bounded overload: `passed`
- Supervised crash recovery: `passed`
- Privacy check: `passed`
- Normal runtime builds: `1`
- Per-request rebuild detected: `false`

## Environment

- Platform: `apple_emily`
- Requested backend: `emily`
- Requested device: `gpu`
- Fallback policy: `raise`
- Backend proven: `true`
- Fallback occurred: `false`
- Linux/EXLA: `unavailable`
- OpenMed optimization policy: `openmed_latency_v1`
- Sequence-length buckets: `[192, 256, 384, 512, 768]`
- Sequence-length bucket threshold: `129`
- Log-prob conversion: `raw_logits`
- Policy matches default: `true`


No raw input, detected value, model asset, cache content, or absolute local
path is included in this report.
