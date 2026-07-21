# Sustained Latency Diagnostic: balanced

Status: `complete`
Experiment: `balanced_canonical_r1`
Source commit: `b762a1a0c84ea31a8178395c42da0dbcfcb70ccc`
Diagnostics enabled: `true`

## Workload

- Duration: `600000 ms`
- Concurrency: `4`
- Completed: `21376`
- Failed / rejected / timed out: `0 / 0 / 0`
- Throughput: `35.624 req/s`
- Stable output: `true`
- Instrumentation throughput delta: `-0.013`
- Instrumentation p95 delta: `-0.118`

## Timeline

| Window | Throughput req/s | Request p95 ms | Queue p95 ms | Model p95 ms | BEAM CPU % |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 42.533 | 100.000 | 0.850 | 98.500 | 84.175 |
| 1 | 42.067 | 105.000 | 1.050 | 98.000 | 112.785 |
| 2 | 37.650 | 135.000 | 1.100 | 130.000 | 124.625 |
| 3 | 33.500 | 160.000 | 0.990 | 150.000 | 122.532 |
| 4 | 32.033 | 160.000 | 1.100 | 155.000 | 121.385 |
| 5 | 32.367 | 160.000 | 1.150 | 150.000 | 121.049 |
| 6 | 33.550 | 150.000 | 1.000 | 145.000 | 122.807 |
| 7 | 34.217 | 150.000 | 1.100 | 145.000 | 124.410 |
| 8 | 34.283 | 150.000 | 1.100 | 145.000 | 124.287 |
| 9 | 34.000 | 150.000 | 1.100 | 145.000 | 122.639 |

## Stage Distributions

| Stage | Count | Mean ms | p95 ms | p99 ms | Mean share % |
| --- | ---: | ---: | ---: | ---: | ---: |
| analyzer_filtering | 21376 | 0.088 | 0.340 | 1.200 | 0.079 |
| conflict_resolution | 21376 | 0.008 | 0.020 | 0.040 | 0.007 |
| diagnostic_token_count_probe | 21376 | 1.507 | 7.500 | 11.500 | 1.349 |
| final_assembly | 21376 | 0.000 | 0.010 | 0.010 | 0.000 |
| model_serving | 21376 | 108.231 | 145.000 | 170.000 | 96.913 |
| nlp_artifacts | 21376 | 0.125 | 0.370 | 1.150 | 0.112 |
| queue_admission | 21376 | 0.194 | 1.050 | 2.650 | 0.174 |
| recognizer_execution | 21376 | 108.962 | 145.000 | 170.000 | 97.567 |
| service_total | 21376 | 111.679 | 150.000 | 175.000 | 100.000 |
| span_reconstruction_entity_mapping | 21376 | 0.360 | 1.450 | 3.400 | 0.322 |

Earliest degrading stage:
`%{status: :observed, stage: :diagnostic_token_count_probe, first_to_last_growth_ratio: 10.438301400177362}`

Attention and MoE are fused into the compiled Emily device graph. They are
not assigned invented host timings. GPU utilization, frequency, and power
require privileged `powermetrics` on this host and are reported as
unavailable.

No raw input, token ID, decoded value, span text, checkpoint path,
credential, or absolute local path is included.
