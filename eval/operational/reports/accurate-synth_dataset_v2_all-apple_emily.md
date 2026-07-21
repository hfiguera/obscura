# Operational Benchmark: accurate / synth_dataset_v2_all

Status: `complete`

Dataset SHA-256: `ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012`
Selection SHA-256: `aa765814466a01f05eae4fdce67d35d874dccb0c22b52561e12a1880bfb566cc`
Samples: `1500`
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
| 1 | 20.543 | 54.521 | 58.713 | 66.571 | 3000 | 0 | 0 | 0 |
| 2 | 22.618 | 100.544 | 104.927 | 106.340 | 3000 | 0 | 0 | 0 |
| 4 | 23.090 | 197.371 | 205.459 | 208.091 | 3000 | 0 | 0 | 0 |
| 8 | 23.302 | 391.303 | 405.736 | 414.717 | 3000 | 0 | 0 | 0 |
| 16 | 23.405 | 778.170 | 807.615 | 874.161 | 3000 | 0 | 0 | 0 |

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
