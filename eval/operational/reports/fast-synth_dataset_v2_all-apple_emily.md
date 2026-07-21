# Operational Benchmark: fast / synth_dataset_v2_all

Status: `complete`

Dataset SHA-256: `ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012`
Selection SHA-256: `aa765814466a01f05eae4fdce67d35d874dccb0c22b52561e12a1880bfb566cc`
Samples: `1500`
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
| 1 | 7730.925 | 0.117 | 0.189 | 0.241 | 3000 | 0 | 0 | 0 |
| 2 | 13834.950 | 0.129 | 0.209 | 0.256 | 3000 | 0 | 0 | 0 |
| 4 | 22375.473 | 0.158 | 0.255 | 0.311 | 3000 | 0 | 0 | 0 |
| 8 | 35570.803 | 0.194 | 0.289 | 0.350 | 3000 | 0 | 0 | 0 |
| 16 | 53828.203 | 0.247 | 0.363 | 0.453 | 3000 | 0 | 0 | 0 |

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
