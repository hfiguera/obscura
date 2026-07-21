# Operational Benchmark: openmed_pii / generated_large_template_heldout

Status: `complete`

Dataset SHA-256: `b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26`
Selection SHA-256: `591a4eef654689b47e512ca8bb7b6c95553faad55535deb5c2a3ec021c825817`
Samples: `648`
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
| 1 | 4.381 | 222.666 | 309.593 | 355.049 | 1296 | 0 | 0 | 0 |
| 2 | 7.796 | 248.752 | 351.620 | 431.104 | 1296 | 0 | 0 | 0 |
| 4 | 8.626 | 450.354 | 628.129 | 701.268 | 1296 | 0 | 0 | 0 |
| 8 | 9.923 | 791.609 | 1016.231 | 1111.659 | 1296 | 0 | 0 | 0 |
| 16 | 9.769 | 1610.226 | 2007.619 | 2280.503 | 1296 | 0 | 0 | 0 |

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
