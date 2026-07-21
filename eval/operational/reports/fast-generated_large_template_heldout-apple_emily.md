# Operational Benchmark: fast / generated_large_template_heldout

Status: `complete`

Dataset SHA-256: `b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26`
Selection SHA-256: `591a4eef654689b47e512ca8bb7b6c95553faad55535deb5c2a3ec021c825817`
Samples: `648`
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
| 1 | 7862.638 | 0.114 | 0.193 | 0.248 | 1296 | 0 | 0 | 0 |
| 2 | 14152.167 | 0.128 | 0.200 | 0.250 | 1296 | 0 | 0 | 0 |
| 4 | 24174.807 | 0.144 | 0.236 | 0.286 | 1296 | 0 | 0 | 0 |
| 8 | 37673.769 | 0.181 | 0.288 | 0.351 | 1296 | 0 | 0 | 0 |
| 16 | 55229.140 | 0.234 | 0.373 | 0.502 | 1296 | 0 | 0 | 0 |

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
