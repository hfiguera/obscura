# CPU workload results

These are measured external-worker workloads on development hosts with ambient load. They are not isolated hardware capacity measurements or production reliability certification.

Each worker is an independent consumer process: an Elixir VM for an Obscura profile, or Node plus the official native SDK for Redact. The Obscura consumer includes optional dependencies for all three baselines. This is not a measurement of four native workers inside one shared Elixir VM, nor of a minimal fast/efficient release.

Each configuration ran for at least 300 seconds after a full warmup cycle, completing whole seven-request cycles. The burst queues eight requests per worker in the harness. Recovery deliberately kills one owned process group, replaces it and compares a canary with its original result. All collected request-error counters are zero, all bursts complete, and all recovery comparisons pass. Those transport results do not repair Redact's invalid Mac CPU neural output.

Redact Mac CPU rows are marked **invalid NER**. Their RPC rates are diagnostic observations and must not be presented as successful NER performance. Mac default Core ML acceleration is excluded from the timed CPU matrix.

## macos

Apple M4 Max; 16 logical CPUs; 128.0 GiB RAM. macOS-26.6.2-arm64-arm-64bit-Mach-O.

| Profile / workers | RPCs/s | p95 round trip ms | p99 ms | Peak RSS MiB | RSS change MiB | Peak PSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [fast / 1](results/macos/workload-fast-1.json) | 3591.63 | 0.63 | 0.71 | 111.5 | -7.0 | — |
| [fast / 2](results/macos/workload-fast-2.json) | 6768.97 | 0.66 | 0.74 | 231.8 | -20.7 | — |
| [fast / 3](results/macos/workload-fast-3.json) | 9498.29 | 0.71 | 0.80 | 334.9 | -20.4 | — |
| [fast / 4](results/macos/workload-fast-4.json) | 12220.77 | 0.73 | 0.83 | 452.8 | -29.5 | — |
| [efficient / 1](results/macos/workload-efficient-1.json) | 962.54 | 2.74 | 2.90 | 176.8 | -24.5 | — |
| [efficient / 2](results/macos/workload-efficient-2.json) | 1819.41 | 2.91 | 3.03 | 365.0 | -57.5 | — |
| [efficient / 3](results/macos/workload-efficient-3.json) | 2587.22 | 3.04 | 3.15 | 539.5 | -81.5 | — |
| [efficient / 4](results/macos/workload-efficient-4.json) | 3325.40 | 3.15 | 3.41 | 705.9 | -94.9 | — |
| [balanced / 1](results/macos/workload-balanced-1.json) | 7.24 | 148.42 | 156.62 | 1801.2 | -85.2 | — |
| [balanced / 2](results/macos/workload-balanced-2.json) | 7.83 | 283.56 | 305.97 | 3471.4 | -53.5 | — |
| [balanced / 3](results/macos/workload-balanced-3.json) | 8.12 | 404.27 | 427.34 | 5238.9 | -104.5 | — |
| [balanced / 4](results/macos/workload-balanced-4.json) | 7.79 | 590.33 | 639.94 | 6904.3 | -65.5 | — |
| [redact_cpu / 1 (invalid NER)](results/macos/workload-redact_cpu-1.json) | 170.88 | 10.31 | 10.81 | 102.1 | +5.2 | — |
| [redact_cpu / 2 (invalid NER)](results/macos/workload-redact_cpu-2.json) | 300.40 | 11.74 | 12.15 | 203.5 | +10.2 | — |
| [redact_cpu / 3 (invalid NER)](results/macos/workload-redact_cpu-3.json) | 408.98 | 13.11 | 13.79 | 305.2 | +14.9 | — |
| [redact_cpu / 4 (invalid NER)](results/macos/workload-redact_cpu-4.json) | 479.16 | 15.18 | 16.74 | 391.9 | +4.5 | — |

| Profile / workers | Process startup median ms | First RPC median ms | Burst completion p95 ms | Restart + canary ms |
| --- | ---: | ---: | ---: | ---: |
| fast / 1 | 379.6 | 11.4 | 3.3 | 410.2 |
| fast / 2 | 375.8 | 11.1 | 3.5 | 439.5 |
| fast / 3 | 397.4 | 12.1 | 3.2 | 418.2 |
| fast / 4 | 364.7 | 10.7 | 3.3 | 376.4 |
| efficient / 1 | 601.4 | 17.1 | 8.5 | 626.0 |
| efficient / 2 | 619.3 | 17.6 | 9.6 | 666.9 |
| efficient / 3 | 610.2 | 17.3 | 9.9 | 631.9 |
| efficient / 4 | 758.3 | 18.7 | 10.1 | 644.3 |
| balanced / 1 | 1802.3 | 508.2 | 984.1 | 2261.7 |
| balanced / 2 | 1754.6 | 519.3 | 1838.5 | 2338.0 |
| balanced / 3 | 1708.2 | 503.3 | 2831.9 | 2269.2 |
| balanced / 4 | 1813.0 | 507.6 | 3901.2 | 2577.4 |
| redact_cpu / 1 (invalid NER) | 207.6 | 61.9 | 46.5 | 86.3 |
| redact_cpu / 2 (invalid NER) | 46.2 | 31.3 | 50.7 | 81.5 |
| redact_cpu / 3 (invalid NER) | 48.3 | 31.4 | 58.8 | 81.5 |
| redact_cpu / 4 (invalid NER) | 48.5 | 32.1 | 64.8 | 87.5 |

## linux

11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz; 8 logical CPUs; 62.4 GiB RAM. Linux-7.1.5-76070105-generic-x86_64-with-glibc2.39.

| Profile / workers | RPCs/s | p95 round trip ms | p99 ms | Peak RSS MiB | RSS change MiB | Peak PSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [fast / 1](results/linux/workload-fast-1.json) | 912.75 | 3.02 | 3.85 | 90.4 | -10.4 | 69.6 |
| [fast / 2](results/linux/workload-fast-2.json) | 957.86 | 6.28 | 8.82 | 173.0 | -14.6 | 127.2 |
| [fast / 3](results/linux/workload-fast-3.json) | 987.85 | 8.95 | 12.74 | 246.9 | -15.3 | 175.9 |
| [fast / 4](results/linux/workload-fast-4.json) | 1316.55 | 8.90 | 12.35 | 326.7 | -19.4 | 230.8 |
| [efficient / 1](results/linux/workload-efficient-1.json) | 159.11 | 18.77 | 24.85 | 145.1 | -22.4 | 121.5 |
| [efficient / 2](results/linux/workload-efficient-2.json) | 221.61 | 27.76 | 38.09 | 271.7 | -26.3 | 212.6 |
| [efficient / 3](results/linux/workload-efficient-3.json) | 251.87 | 38.87 | 54.88 | 384.6 | -25.0 | 289.8 |
| [efficient / 4](results/linux/workload-efficient-4.json) | 355.43 | 35.61 | 49.39 | 527.2 | -42.0 | 397.1 |
| [balanced / 1](results/linux/workload-balanced-1.json) | 0.94 | 1529.27 | 1894.04 | 2083.9 | -17.0 | 2063.2 |
| [balanced / 2](results/linux/workload-balanced-2.json) | 1.08 | 2207.94 | 2359.82 | 4095.7 | -58.4 | 3824.5 |
| [balanced / 3](results/linux/workload-balanced-3.json) | 1.05 | 3932.24 | 5251.91 | 6133.7 | -44.8 | 5607.8 |
| [balanced / 4](results/linux/workload-balanced-4.json) | 1.08 | 5143.42 | 6064.57 | 8232.6 | -44.2 | 7454.7 |
| [redact_cpu / 1](results/linux/workload-redact_cpu-1.json) | 17.89 | 97.66 | 123.64 | 186.7 | -44.2 | 178.9 |
| [redact_cpu / 2](results/linux/workload-redact_cpu-2.json) | 28.73 | 122.44 | 144.23 | 373.3 | -88.1 | 278.4 |
| [redact_cpu / 3](results/linux/workload-redact_cpu-3.json) | 24.04 | 240.75 | 316.92 | 556.9 | -133.3 | 374.9 |
| [redact_cpu / 4](results/linux/workload-redact_cpu-4.json) | 29.41 | 258.63 | 355.59 | 747.2 | -178.6 | 478.0 |

| Profile / workers | Process startup median ms | First RPC median ms | Burst completion p95 ms | Restart + canary ms |
| --- | ---: | ---: | ---: | ---: |
| fast / 1 | 554.2 | 18.3 | 8.7 | 967.6 |
| fast / 2 | 1018.0 | 39.2 | 15.8 | 1568.6 |
| fast / 3 | 1216.3 | 40.1 | 19.7 | 2087.9 |
| fast / 4 | 1466.5 | 43.3 | 19.9 | 1498.1 |
| efficient / 1 | 2583.0 | 55.8 | 51.4 | 2469.7 |
| efficient / 2 | 2885.1 | 75.0 | 59.6 | 3160.1 |
| efficient / 3 | 3999.8 | 74.2 | 141.3 | 4175.0 |
| efficient / 4 | 2489.4 | 55.0 | 75.4 | 2361.2 |
| balanced / 1 | 6076.0 | 2252.2 | 7894.1 | 8305.0 |
| balanced / 2 | 6603.5 | 2309.0 | 17094.8 | 13520.3 |
| balanced / 3 | 8157.1 | 2882.6 | 23084.5 | 10447.0 |
| balanced / 4 | 6557.5 | 2288.6 | 27808.8 | 10438.8 |
| redact_cpu / 1 | 758.9 | 397.6 | 321.3 | 618.1 |
| redact_cpu / 2 | 371.8 | 219.7 | 474.3 | 759.1 |
| redact_cpu / 3 | 438.6 | 287.9 | 941.1 | 1116.1 |
| redact_cpu / 4 | 506.8 | 316.1 | 841.8 | 985.6 |

## Input mixture and limits

| Input ID | UTF-8 bytes | Kind | Gold entity types |
| --- | ---: | --- | --- |
| development-00-0 | 53 | positive | person |
| development-01-0 | 68 | positive | email, person |
| development-05-0 | 83 | positive | location, person |
| development-08-0 | 64 | positive | credit_card |
| development-14-0 | 49 | negative | none |
| development-18-0 | 1505 | long | email, location, person |
| development-19-0 | 1490 | long | person, phone |

This is a repeated fixed input mixture. It does not establish behavior for arbitrarily large documents or an unlimited stream of unique text. Latency includes the request/response boundary and mapping; the driver is outside worker-tree memory measurements. Worker count does not cap internal BEAM, XLA or BLAS threads.

Startup means a fresh process with cached assets, including runtime initialization and asset checks. It is not a reboot, first download or purged filesystem-cache measurement. The first RPC follows readiness; warm latency follows a full seven-input warmup.

Memory sampling waits ten seconds after collection, so actual intervals include query overhead (largest observed gap: 11.98 seconds). RSS is summed over worker process trees and can count shared pages multiple times. Linux PSS apportions shared pages. Sampled peaks can miss intervening peaks. Start/end growth over five minutes is not evidence of long-term leak freedom or input-retention safety.

The hosts have unrelated background activity, including virtualization. Host snapshots and per-run load averages are retained. The fixed run order, different language-runtime builds between hosts, and one sustained sample per configuration limit generalization. Compare within a host; do not interpret cross-host ratios as a hardware benchmark.

See [WORKLOAD.md](WORKLOAD.md) for the frozen protocol, [results/workload-analysis.json](results/workload-analysis.json) for the audit and [ACCURACY.md](ACCURACY.md) for detection quality.
