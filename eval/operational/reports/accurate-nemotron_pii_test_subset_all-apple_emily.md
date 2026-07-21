# Operational Benchmark: accurate / nemotron_pii_test_subset_all

Status: `complete`

Dataset SHA-256: `a36582d34f64ba871a604eabd53a8d92f0628b76ddb027105ac0f9d9a3042577`
Selection SHA-256: `a38604f5ce5e556d0bc23aa0ac1f58a95948c1748f2f752e21f126e22d3468cd`
Samples: `500`
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
| 1 | 20.191 | 54.765 | 58.703 | 61.320 | 1000 | 0 | 0 | 0 |
| 2 | 21.650 | 103.171 | 108.409 | 109.643 | 1000 | 0 | 0 | 0 |
| 4 | 22.413 | 199.926 | 207.448 | 209.799 | 1000 | 0 | 0 | 0 |
| 8 | 22.762 | 393.466 | 407.001 | 410.502 | 1000 | 0 | 0 | 0 |
| 16 | 22.793 | 780.241 | 858.056 | 901.091 | 1000 | 0 | 0 | 0 |

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
