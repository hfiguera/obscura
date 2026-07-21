# Operational Benchmark: fast / nemotron_pii_test_subset_all

Status: `complete`

Dataset SHA-256: `a36582d34f64ba871a604eabd53a8d92f0628b76ddb027105ac0f9d9a3042577`
Selection SHA-256: `a38604f5ce5e556d0bc23aa0ac1f58a95948c1748f2f752e21f126e22d3468cd`
Samples: `500`
Source commit: `ab84d4ce5a4f4c0c482228b94b30584b8e687de8`

## Cold Lifecycle

- Fresh OS process: `true`
- Application start: `6.120 ms`
- Runtime preparation: `2.268 ms`
- Compile-inclusive first inference: `12.324 ms`
- Total process ready: `374.869 ms`
- Empty-cache/network timing: unavailable; assets were pre-provisioned and offline loading was enforced.

Nx does not expose lazy compilation as an independent public timing. First
inference is therefore explicitly compile-inclusive.

## Warm Load

| Concurrency | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed | Failed | Rejected | Timed out |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 2259.312 | 0.375 | 0.933 | 1.254 | 1000 | 0 | 0 | 0 |
| 2 | 4225.228 | 0.399 | 0.960 | 1.256 | 1000 | 0 | 0 | 0 |
| 4 | 8131.519 | 0.418 | 0.953 | 1.262 | 1000 | 0 | 0 | 0 |
| 8 | 13985.450 | 0.481 | 0.993 | 1.345 | 1000 | 0 | 0 | 0 |
| 16 | 22795.104 | 0.562 | 1.180 | 1.563 | 1000 | 0 | 0 | 0 |

Queue time is unavailable because the inline Nx serving path does not expose
it independently. Service and end-to-end latency are recorded separately in
the JSON artifact.

## Sustained Load

- Requested duration: `60000 ms`
- Measured duration: `60000.567 ms`
- Throughput: `18292.694 req/s`
- Latency drift ratio: `1.011`
- RSS growth: `-9043968 bytes`
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
- Requested backend: `beam_cpu`
- Requested device: `cpu`
- Fallback policy: `not_applicable`
- Backend proven: `true`
- Fallback occurred: `false`
- Linux/EXLA: `unavailable`

No raw input, detected value, model asset, cache content, or absolute local
path is included in this report.
