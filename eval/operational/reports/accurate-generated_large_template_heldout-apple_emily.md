# Operational Benchmark: accurate / generated_large_template_heldout

Status: `complete`

Dataset SHA-256: `b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26`
Selection SHA-256: `591a4eef654689b47e512ca8bb7b6c95553faad55535deb5c2a3ec021c825817`
Samples: `648`
Source commit: `9ebb01b70ffa427ac8ce2bfd6fbaa276e9fc21d9`

## Cold Lifecycle

- Fresh OS process: `true`
- Application start: `6.062 ms`
- Runtime preparation: `1262.933 ms`
- Compile-inclusive first inference: `72.778 ms`
- Total process ready: `1720.101 ms`
- Empty-cache/network timing: unavailable; assets were pre-provisioned and offline loading was enforced.

Nx does not expose lazy compilation as an independent public timing. First
inference is therefore explicitly compile-inclusive.

## Warm Load

| Concurrency | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed | Failed | Rejected | Timed out |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 29.716 | 41.966 | 43.776 | 44.593 | 1296 | 0 | 0 | 0 |
| 2 | 33.397 | 74.445 | 78.779 | 80.434 | 1296 | 0 | 0 | 0 |
| 4 | 33.685 | 148.820 | 157.943 | 159.936 | 1296 | 0 | 0 | 0 |
| 8 | 25.887 | 363.910 | 441.929 | 479.932 | 1296 | 0 | 0 | 0 |
| 16 | 20.296 | 959.639 | 1066.570 | 1095.273 | 1296 | 0 | 0 | 0 |

Queue time is unavailable because the inline Nx serving path does not expose
it independently. Service and end-to-end latency are recorded separately in
the JSON artifact.

## Sustained Load

- Requested duration: `60000 ms`
- Measured duration: `60109.495 ms`
- Throughput: `24.123 req/s`
- Latency drift ratio: `1.087`
- RSS growth: `-99385344 bytes`
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
