# Operational Benchmark: openmed_pii / synth_dataset_v2_all

Status: `complete`

Dataset SHA-256: `ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012`
Selection SHA-256: `aa765814466a01f05eae4fdce67d35d874dccb0c22b52561e12a1880bfb566cc`
Samples: `1500`
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
| 1 | 4.252 | 220.706 | 349.202 | 438.342 | 3000 | 0 | 0 | 0 |
| 2 | 7.686 | 241.051 | 415.781 | 514.719 | 3000 | 0 | 0 | 0 |
| 4 | 9.074 | 420.581 | 639.937 | 761.693 | 3000 | 0 | 0 | 0 |
| 8 | 9.401 | 819.985 | 1172.786 | 1339.031 | 3000 | 0 | 0 | 0 |
| 16 | 9.788 | 1594.854 | 2117.998 | 2427.242 | 3000 | 0 | 0 | 0 |

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
