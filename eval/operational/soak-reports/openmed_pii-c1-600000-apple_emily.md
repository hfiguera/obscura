# Operational Soak: openmed_pii

Status: `complete`
Source commit: `fd3dc8ebfbf26baa4b65b86f6b73e8f9000bbfef`
Classification: `allocator_caching`

## Workload

- Requested duration: `600000 ms`
- Measured duration: `600424.366 ms`
- Concurrency: `1`
- Completed: `1013`
- Failed / rejected / timed out: `0 / 0 / 0`
- Throughput: `1.687 req/s`
- Resource samples: `599`
- Sampling coverage: `0.998`
- Stable output: `true`

## Time Windows

| Window | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 2.067 | 325.000 | 1250.000 | 3150.000 | 124 |
| 1 | 1.700 | 335.000 | 1600.000 | 2350.000 | 102 |
| 2 | 1.733 | 355.000 | 1550.000 | 2550.000 | 104 |
| 3 | 1.667 | 355.000 | 1750.000 | 2250.000 | 100 |
| 4 | 1.400 | 355.000 | 2100.000 | 3900.000 | 84 |
| 5 | 2.000 | 290.000 | 1250.000 | 2050.000 | 120 |
| 6 | 1.700 | 305.000 | 1550.000 | 2300.000 | 102 |
| 7 | 1.650 | 330.000 | 2200.000 | 3850.000 | 99 |
| 8 | 1.550 | 330.000 | 2500.000 | 3250.000 | 93 |
| 9 | 1.400 | 285.000 | 1950.000 | 5300.000 | 84 |
| 10 | 2.356 | 1500.000 | 1500.000 | 1500.000 | 1 |

## Memory Analysis

| Metric | Status | Baseline | Final | Growth | Final slope bytes/min | Trend |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| in_flight | measured | 1.000 | 1.000 | 0.000 | 0.000 | plateau |
| os_rss | measured | 52058226688.000 | 890077184.000 | -51168149504.000 | -12623632.460 | inconclusive |
| beam_atom | measured | 1020466.000 | 1028857.000 | 8391.000 | 0.000 | plateau |
| beam_binary | measured | 22887944.000 | 19983416.000 | -2904528.000 | 36421.545 | plateau |
| beam_ets | measured | 1353616.000 | 1358800.000 | 5184.000 | 0.000 | plateau |
| beam_processes | measured | 21960776.000 | 35445744.000 | 13484968.000 | 200901.551 | plateau |
| beam_system | measured | 107242351.000 | 104380355.000 | -2861996.000 | 40224.979 | plateau |
| beam_total | measured | 129203127.000 | 139826099.000 | 10622972.000 | 241126.530 | plateau |
| emily_active | measured | 2799234178.000 | 8142826336.000 | 5343592158.000 | 674513105.131 | inconclusive |
| emily_cache | measured | 55384238454.000 | 101378362198.000 | 45994123744.000 | -718344213.071 | inconclusive |
| mailbox_length | measured | 0.000 | 0.000 | 0.000 | 0.000 | plateau |

Classification reasons: `cache_growth_released_by_cache_clear`

Emily values are direct allocator statistics, not inferred physical GPU
residency.

## Request Correlation

| Metric | Status | Pearson coefficient | Samples |
| --- | --- | ---: | ---: |
| os_rss | measured | -0.335 | 599 |
| beam_total | measured | 0.689 | 599 |
| emily_active | measured | 0.281 | 599 |
| emily_cache | measured | -0.086 | 599 |

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
