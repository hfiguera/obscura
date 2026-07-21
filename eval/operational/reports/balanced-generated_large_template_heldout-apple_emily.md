# Operational Benchmark: balanced / generated_large_template_heldout

Status: `complete`

Dataset SHA-256: `b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26`
Selection SHA-256: `591a4eef654689b47e512ca8bb7b6c95553faad55535deb5c2a3ec021c825817`
Samples: `648`
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
| 1 | 45.563 | 21.819 | 22.777 | 23.268 | 1296 | 0 | 0 | 0 |
| 2 | 51.067 | 39.120 | 40.310 | 40.855 | 1296 | 0 | 0 | 0 |
| 4 | 52.149 | 76.752 | 78.700 | 80.547 | 1296 | 0 | 0 | 0 |
| 8 | 52.930 | 151.120 | 159.524 | 163.924 | 1296 | 0 | 0 | 0 |
| 16 | 54.094 | 295.862 | 299.512 | 300.998 | 1296 | 0 | 0 | 0 |

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
