# Operational Soak: fast

Status: `complete`
Source commit: `fd3dc8ebfbf26baa4b65b86f6b73e8f9000bbfef`
Classification: `inconclusive`

## Workload

- Requested duration: `600000 ms`
- Measured duration: `600000.899 ms`
- Concurrency: `4`
- Completed: `10591487`
- Failed / rejected / timed out: `0 / 0 / 0`
- Throughput: `17652.452 req/s`
- Resource samples: `600`
- Sampling coverage: `1.000`
- Stable output: `true`

## Time Windows

| Window | Throughput req/s | p50 ms | p95 ms | p99 ms | Completed |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 17845.233 | 0.160 | 0.560 | 0.990 | 1070714 |
| 1 | 17690.783 | 0.160 | 0.560 | 1.000 | 1061447 |
| 2 | 17650.633 | 0.160 | 0.560 | 1.000 | 1059038 |
| 3 | 17604.400 | 0.160 | 0.560 | 1.000 | 1056264 |
| 4 | 17638.683 | 0.160 | 0.560 | 1.000 | 1058321 |
| 5 | 17550.350 | 0.160 | 0.560 | 1.000 | 1053021 |
| 6 | 17691.733 | 0.160 | 0.560 | 1.000 | 1061504 |
| 7 | 17502.217 | 0.160 | 0.560 | 1.000 | 1050133 |
| 8 | 17638.700 | 0.160 | 0.560 | 1.000 | 1058322 |
| 9 | 17711.983 | 0.160 | 0.560 | 1.000 | 1062719 |
| 10 | 4000.000 | 0.530 | 1.150 | 1.150 | 4 |

## Memory Analysis

| Metric | Status | Baseline | Final | Growth | Final slope bytes/min | Trend |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| in_flight | measured | 4.000 | 4.000 | 0.000 | 0.009 | plateau |
| emily_active | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| emily_cache | unavailable | unavailable | unavailable | unavailable | unavailable | unavailable |
| os_rss | measured | 190906368.000 | 186941440.000 | -3964928.000 | 4659942.512 | inconclusive |
| beam_total | measured | 83029951.000 | 122519516.000 | 39489565.000 | 2784369.151 | inconclusive |
| beam_processes | measured | 23308224.000 | 61127344.000 | 37819120.000 | 2507132.781 | inconclusive |
| beam_binary | measured | 5008592.000 | 6625744.000 | 1617152.000 | 278541.983 | plateau |
| beam_ets | measured | 1351792.000 | 1356832.000 | 5040.000 | 0.000 | plateau |
| beam_atom | measured | 1062095.000 | 1062177.000 | 82.000 | 0.000 | plateau |
| beam_system | measured | 59721727.000 | 61392172.000 | 1670445.000 | 277236.370 | plateau |
| mailbox_length | measured | 0.000 | 0.000 | 0.000 | -0.003 | plateau |

Classification reasons: `emily_active_unavailable, emily_cache_unavailable, rss_trend_inconclusive`

Emily values are direct allocator statistics, not inferred physical GPU
residency.

## Request Correlation

| Metric | Status | Pearson coefficient | Samples |
| --- | --- | ---: | ---: |
| emily_active | unavailable | unavailable | unavailable |
| emily_cache | unavailable | unavailable | unavailable |
| os_rss | measured | 0.038 | 600 |
| beam_total | measured | 0.767 | 600 |

## Post-Soak Diagnostics

- Idle duration: `10000 ms`
- Cache clear: `not_applicable`
- Timeout probe: `passed`
- Overload probe: `passed`
- Gateway recovery: `passed`
- Runtime builds: `1`
- Per-request rebuild: `false`

No raw input, detected value, checkpoint path, cache content, model asset,
credential, or absolute local path is included.
