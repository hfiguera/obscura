# Operational Soak: balanced

Status: `complete`
Source commit: `fd3dc8ebfbf26baa4b65b86f6b73e8f9000bbfef`
Classification: `inconclusive`

## Workload

- Requested duration: `600000 ms`
- Measured duration: `600060.396 ms`
- Concurrency: `4`
- Completed: `22717`
- Failed / rejected / timed out: `0 / 0 / 0`
- Throughput: `37.858 req/s`
- Resource samples: `599`
- Sampling coverage: `0.998`
- Stable output: `true`

## Time Windows

| Window | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 55.000 | 73.000 | 75.500 | 76.500 | 3300 |
| 1 | 49.333 | 80.500 | 94.000 | 96.500 | 2960 |
| 2 | 33.333 | 125.000 | 140.000 | 170.000 | 2000 |
| 3 | 34.067 | 120.000 | 135.000 | 140.000 | 2044 |
| 4 | 37.867 | 110.000 | 115.000 | 125.000 | 2272 |
| 5 | 35.817 | 115.000 | 135.000 | 150.000 | 2149 |
| 6 | 34.217 | 120.000 | 145.000 | 175.000 | 2053 |
| 7 | 33.333 | 120.000 | 150.000 | 165.000 | 2000 |
| 8 | 32.583 | 125.000 | 155.000 | 175.000 | 1955 |
| 9 | 33.000 | 125.000 | 155.000 | 180.000 | 1980 |
| 10 | 66.230 | 105.000 | 120.000 | 120.000 | 4 |

## Memory Analysis

| Metric | Status | Baseline | Final | Growth | Final slope bytes/min | Trend |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| in_flight | measured | 4.000 | 4.000 | 0.000 | 0.004 | plateau |
| os_rss | measured | 1670987776.000 | 1697398784.000 | 26411008.000 | -104752.420 | inconclusive |
| beam_atom | measured | 1093907.000 | 1094106.000 | 199.000 | 0.000 | plateau |
| beam_binary | measured | 4858672.000 | 5681840.000 | 823168.000 | 2426.916 | plateau |
| beam_ets | measured | 1454424.000 | 1459608.000 | 5184.000 | 0.000 | plateau |
| beam_processes | measured | 28096304.000 | 78778488.000 | 50682184.000 | -60082.567 | inconclusive |
| beam_system | measured | 64514037.000 | 65423905.000 | 909868.000 | 2263.335 | plateau |
| beam_total | measured | 92610341.000 | 144202393.000 | 51592052.000 | -57819.232 | inconclusive |
| emily_active | measured | 1417427176.000 | 1492029908.000 | 74602732.000 | 2806783.173 | inconclusive |
| emily_cache | measured | 144588991.000 | 70090815.000 | -74498176.000 | -2813753.993 | inconclusive |
| mailbox_length | measured | 0.000 | 0.000 | 0.000 | 0.002 | plateau |

Classification reasons: `rss_trend_inconclusive, live_allocator_trend_inconclusive`

Emily values are direct allocator statistics, not inferred physical GPU
residency.

## Request Correlation

| Metric | Status | Pearson coefficient | Samples |
| --- | --- | ---: | ---: |
| os_rss | measured | 0.771 | 599 |
| beam_total | measured | 0.310 | 599 |
| emily_active | measured | -0.066 | 599 |
| emily_cache | measured | 0.066 | 599 |

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
