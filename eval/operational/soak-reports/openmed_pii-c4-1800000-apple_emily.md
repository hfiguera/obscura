# Operational Soak: openmed_pii

Status: `complete`
Source commit: `fd3dc8ebfbf26baa4b65b86f6b73e8f9000bbfef`
Classification: `allocator_caching`

## Workload

- Requested duration: `1800000 ms`
- Measured duration: `1802591.451 ms`
- Concurrency: `4`
- Completed: `6404`
- Failed / rejected / timed out: `0 / 0 / 0`
- Throughput: `3.553 req/s`
- Resource samples: `1799`
- Sampling coverage: `0.999`
- Stable output: `true`

## Time Windows

| Window | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 3.950 | 815.000 | 2550.000 | 3300.000 | 237 |
| 1 | 4.033 | 845.000 | 2100.000 | 3400.000 | 242 |
| 2 | 3.200 | 1100.000 | 2900.000 | 3850.000 | 192 |
| 3 | 2.667 | 1300.000 | 3400.000 | 4700.000 | 160 |
| 4 | 2.233 | 1650.000 | 3650.000 | 4150.000 | 134 |
| 5 | 1.600 | 2050.000 | 6500.000 | 8800.000 | 96 |
| 6 | 2.050 | 1100.000 | 7050.000 | 9250.000 | 123 |
| 7 | 3.500 | 945.000 | 2600.000 | 3600.000 | 210 |
| 8 | 6.083 | 465.000 | 1850.000 | 2500.000 | 365 |
| 9 | 9.567 | 395.000 | 660.000 | 825.000 | 574 |
| 10 | 6.850 | 455.000 | 1450.000 | 1900.000 | 411 |
| 11 | 3.417 | 1050.000 | 2450.000 | 3150.000 | 205 |
| 12 | 3.350 | 920.000 | 2950.000 | 4300.000 | 201 |
| 13 | 2.883 | 1300.000 | 2950.000 | 5350.000 | 173 |
| 14 | 2.550 | 1450.000 | 4000.000 | 5100.000 | 153 |
| 15 | 2.067 | 1450.000 | 4900.000 | 5800.000 | 124 |
| 16 | 1.617 | 2200.000 | 6700.000 | 9650.000 | 97 |
| 17 | 1.917 | 1600.000 | 6650.000 | 8150.000 | 115 |
| 18 | 3.267 | 925.000 | 2800.000 | 4450.000 | 196 |
| 19 | 4.367 | 490.000 | 2800.000 | 3950.000 | 262 |
| 20 | 9.150 | 390.000 | 780.000 | 1100.000 | 549 |
| 21 | 8.217 | 430.000 | 870.000 | 1350.000 | 493 |
| 22 | 3.133 | 1200.000 | 2650.000 | 4050.000 | 188 |
| 23 | 3.050 | 1150.000 | 3050.000 | 4550.000 | 183 |
| 24 | 2.417 | 1400.000 | 4200.000 | 5100.000 | 145 |
| 25 | 2.317 | 1450.000 | 3650.000 | 5600.000 | 139 |
| 26 | 2.017 | 1800.000 | 4350.000 | 5900.000 | 121 |
| 27 | 1.950 | 1850.000 | 4350.000 | 5850.000 | 117 |
| 28 | 1.883 | 1850.000 | 5100.000 | 6050.000 | 113 |
| 29 | 1.367 | 2500.000 | 6150.000 | 9250.000 | 82 |
| 30 | 1.544 | 4650.000 | 6500.000 | 6500.000 | 4 |

## Memory Analysis

| Metric | Status | Baseline | Final | Growth | Final slope bytes/min | Trend |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| in_flight | measured | 4.000 | 2.000 | -2.000 | -0.002 | plateau |
| os_rss | measured | 52066598912.000 | 3186688000.000 | -48879910912.000 | -40575.438 | plateau |
| beam_atom | measured | 1020466.000 | 1028857.000 | 8391.000 | 0.000 | plateau |
| beam_binary | measured | 22926952.000 | 20336944.000 | -2590008.000 | -3866.311 | plateau |
| beam_ets | measured | 1353712.000 | 1358896.000 | 5184.000 | 0.000 | plateau |
| beam_processes | measured | 23533120.000 | 42267112.000 | 18733992.000 | 34184.345 | inconclusive |
| beam_system | measured | 107281183.000 | 104945555.000 | -2335628.000 | -19765.668 | plateau |
| beam_total | measured | 130814303.000 | 147212667.000 | 16398364.000 | 14418.677 | inconclusive |
| emily_active | measured | 2799237130.000 | 2799635466.000 | 398336.000 | 61267133.485 | inconclusive |
| emily_cache | measured | 55384219118.000 | 100521625332.000 | 45137406214.000 | -58553956.152 | declining |
| mailbox_length | measured | 0.000 | 0.000 | 0.000 | 0.000 | plateau |

Classification reasons: `cache_growth_released_by_cache_clear`

Emily values are direct allocator statistics, not inferred physical GPU
residency.

## Request Correlation

| Metric | Status | Pearson coefficient | Samples |
| --- | --- | ---: | ---: |
| os_rss | measured | -0.144 | 1799 |
| beam_total | measured | 0.480 | 1799 |
| emily_active | measured | 0.013 | 1799 |
| emily_cache | measured | 0.026 | 1799 |

## Post-Soak Diagnostics

- Idle duration: `10000 ms`
- Cache clear: `executed`
- Timeout probe: `passed`
- Overload probe: `passed`
- Gateway recovery: `passed`
- Runtime builds: `1`
- Per-request rebuild: `false`

No raw input, detected value, checkpoint path, cache content, model asset,
credential, or absolute local path is included.
