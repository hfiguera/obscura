# Operational Benchmark: balanced / nemotron_pii_test_subset_all

Status: `complete`

Dataset SHA-256: `a36582d34f64ba871a604eabd53a8d92f0628b76ddb027105ac0f9d9a3042577`
Selection SHA-256: `a38604f5ce5e556d0bc23aa0ac1f58a95948c1748f2f752e21f126e22d3468cd`
Samples: `500`
Source commit: `ab84d4ce5a4f4c0c482228b94b30584b8e687de8`

## Cold Lifecycle

- Fresh OS process: `true`
- Application start: `6.560 ms`
- Runtime preparation: `745.083 ms`
- Compile-inclusive first inference: `75.447 ms`
- Total process ready: `1198.078 ms`
- Empty-cache/network timing: unavailable; assets were pre-provisioned and offline loading was enforced.

Nx does not expose lazy compilation as an independent public timing. First
inference is therefore explicitly compile-inclusive.

## Warm Load

| Concurrency | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed | Failed | Rejected | Timed out |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 37.801 | 26.195 | 29.440 | 31.207 | 1000 | 0 | 0 | 0 |
| 2 | 41.067 | 48.294 | 52.612 | 54.761 | 1000 | 0 | 0 | 0 |
| 4 | 43.043 | 92.943 | 94.755 | 95.787 | 1000 | 0 | 0 | 0 |
| 8 | 42.795 | 185.764 | 200.218 | 202.363 | 1000 | 0 | 0 | 0 |
| 16 | 44.476 | 359.397 | 365.581 | 367.037 | 1000 | 0 | 0 | 0 |

Queue time is unavailable because the inline Nx serving path does not expose
it independently. Service and end-to-end latency are recorded separately in
the JSON artifact.

## Sustained Load

- Requested duration: `60000 ms`
- Measured duration: `60046.547 ms`
- Throughput: `43.167 req/s`
- Latency drift ratio: `1.011`
- RSS growth: `-67321856 bytes`
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

No raw input, detected value, model asset, cache content, or absolute local
path is included in this report.
