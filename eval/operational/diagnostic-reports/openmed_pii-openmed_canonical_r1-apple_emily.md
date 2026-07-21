# Sustained Latency Diagnostic: openmed_pii

Status: `complete`
Experiment: `openmed_canonical_r1`
Source commit: `b762a1a0c84ea31a8178395c42da0dbcfcb70ccc`
Diagnostics enabled: `true`

## Workload

- Duration: `1800000 ms`
- Concurrency: `4`
- Completed: `5955`
- Failed / rejected / timed out: `0 / 0 / 0`
- Throughput: `3.300 req/s`
- Stable output: `true`
- Instrumentation throughput delta: `0.044`
- Instrumentation p95 delta: `-0.122`

## Timeline

| Window | Throughput req/s | Request p95 ms | Queue p95 ms | Model p95 ms | BEAM CPU % |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 3.317 | 2950.000 | 0.020 | 2250.000 | 89.598 |
| 1 | 3.183 | 2800.000 | 0.020 | 2150.000 | 93.990 |
| 2 | 2.767 | 3300.000 | 0.020 | 2700.000 | 88.050 |
| 3 | 2.417 | 3850.000 | 0.020 | 2850.000 | 76.497 |
| 4 | 2.183 | 5400.000 | 0.020 | 4150.000 | 79.255 |
| 5 | 2.283 | 4700.000 | 0.020 | 3850.000 | 82.637 |
| 6 | 1.517 | 6450.000 | 0.020 | 5500.000 | 74.529 |
| 7 | 1.750 | 6450.000 | 0.020 | 4850.000 | 74.988 |
| 8 | 3.450 | 2450.000 | 0.020 | 2050.000 | 93.665 |
| 9 | 4.067 | 2750.000 | 0.020 | 2300.000 | 95.428 |
| 10 | 9.333 | 730.000 | 0.020 | 625.000 | 142.467 |
| 11 | 8.150 | 890.000 | 0.020 | 720.000 | 132.222 |
| 12 | 3.033 | 2500.000 | 0.020 | 2050.000 | 91.205 |
| 13 | 2.733 | 3350.000 | 0.020 | 2700.000 | 87.818 |
| 14 | 2.467 | 3650.000 | 0.020 | 2950.000 | 83.995 |
| 15 | 2.317 | 3900.000 | 0.020 | 2850.000 | 80.165 |
| 16 | 1.900 | 5950.000 | 0.020 | 4550.000 | 78.280 |
| 17 | 2.000 | 6200.000 | 0.020 | 4600.000 | 81.626 |
| 18 | 1.633 | 6250.000 | 0.020 | 5050.000 | 70.276 |
| 19 | 1.333 | 7000.000 | 0.020 | 5050.000 | 69.400 |
| 20 | 1.333 | 10250.000 | 0.020 | 8550.000 | 73.265 |
| 21 | 3.550 | 2550.000 | 0.020 | 1850.000 | 96.653 |
| 22 | 4.350 | 2600.000 | 0.020 | 1950.000 | 100.763 |
| 23 | 9.450 | 725.000 | 0.020 | 555.000 | 142.733 |
| 24 | 8.133 | 880.000 | 0.020 | 695.000 | 132.681 |
| 25 | 2.817 | 3250.000 | 0.020 | 2500.000 | 83.652 |
| 26 | 2.033 | 3900.000 | 0.020 | 3100.000 | 76.402 |
| 27 | 2.100 | 4000.000 | 0.020 | 3300.000 | 84.110 |
| 28 | 1.683 | 5150.000 | 0.020 | 4250.000 | 74.403 |
| 29 | 1.900 | 4600.000 | 0.020 | 3950.000 | 77.367 |

## Stage Distributions

| Stage | Count | Mean ms | p95 ms | p99 ms | Mean share % |
| --- | ---: | ---: | ---: | ---: | ---: |
| analyzer_filtering | 5955 | 0.003 | 0.010 | 0.020 | 0.000 |
| conflict_resolution | 5955 | 0.002 | 0.010 | 0.010 | 0.000 |
| final_assembly | 5955 | 0.000 | 0.010 | 0.010 | 0.000 |
| logprob_conversion | 5955 | 258.375 | 1150.000 | 2300.000 | 21.336 |
| model_serving | 5955 | 931.739 | 2850.000 | 4750.000 | 76.941 |
| nlp_artifacts | 5955 | 0.051 | 0.200 | 0.320 | 0.004 |
| queue_admission | 5955 | 0.007 | 0.020 | 0.020 | 0.001 |
| recognizer_execution | 5955 | 1210.707 | 3600.000 | 6250.000 | 99.977 |
| service_total | 5955 | 1210.981 | 3600.000 | 6250.000 | 100.000 |
| span_reconstruction_entity_mapping | 5955 | 0.509 | 0.940 | 1.900 | 0.042 |
| token_packing | 5955 | 0.008 | 0.030 | 0.080 | 0.001 |
| tokenization | 5955 | 0.365 | 1.350 | 4.600 | 0.030 |
| viterbi_logprob_decode | 5955 | 18.962 | 41.000 | 76.500 | 1.566 |
| window_logprob_aggregation | 5955 | 0.598 | 1.800 | 4.750 | 0.049 |

Earliest degrading stage:
`%{status: :observed, stage: :span_reconstruction_entity_mapping, first_to_last_growth_ratio: 5.142646397920332}`

Attention and MoE are fused into the compiled Emily device graph. They are
not assigned invented host timings. GPU utilization, frequency, and power
require privileged `powermetrics` on this host and are reported as
unavailable.

No raw input, token ID, decoded value, span text, checkpoint path,
credential, or absolute local path is included.
