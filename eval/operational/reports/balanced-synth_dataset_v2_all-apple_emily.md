# Operational Benchmark: balanced / synth_dataset_v2_all

Status: `complete`

Dataset SHA-256: `ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012`
Selection SHA-256: `aa765814466a01f05eae4fdce67d35d874dccb0c22b52561e12a1880bfb566cc`
Samples: `1500`
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
| 1 | 40.881 | 24.531 | 26.201 | 26.803 | 3000 | 0 | 0 | 0 |
| 2 | 37.912 | 52.419 | 55.779 | 64.573 | 3000 | 0 | 0 | 0 |
| 4 | 42.750 | 93.282 | 97.629 | 103.699 | 3000 | 0 | 0 | 0 |
| 8 | 44.506 | 178.291 | 191.962 | 215.928 | 3000 | 0 | 0 | 0 |
| 16 | 45.096 | 353.112 | 372.044 | 395.627 | 3000 | 0 | 0 | 0 |

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
