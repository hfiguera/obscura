# Sustained Latency Diagnostic Report

## Conclusion

Both reported slowdowns are real, but they have different explanations.

- `:balanced` reproduces a warm-to-sustained slowdown at concurrency 4. The
  clean control falls from `55.27` req/s in minute 1 to `33.65` req/s in
  minute 10, while p95 rises from `75.5` to `155` ms. Instrumentation locates
  the slowdown inside the fixed-shape TNER model-serving boundary. The lower
  level Metal/Emily cause remains unresolved because GPU power, frequency, and
  utilization require privileged `powermetrics` access on this host.
- `:openmed_pii` does not exhibit a monotonic 30-minute decline. Its ordered
  three-dataset workload repeatedly cycles between short and long inputs.
  Throughput ranges from `1.08` to `8.85` req/s in the clean control and later
  recovers under continuous load. Token count, model execution, and log-prob
  conversion explain the low windows. Repeated fixed-triplet experiments
  improve throughput by about three times and bound p95 below `0.8` seconds.

Obscura remains functionally correct in these runs: outputs are stable, the
runtime is prepared once, Emily GPU execution is proven, CPU fallback is
absent, and all canonical requests complete without failure, timeout, or
rejection. The findings concern capacity and tail latency, not recognition
accuracy.

## Provenance

| Field | Value |
| --- | --- |
| Source commit | `b762a1a0c84ea31a8178395c42da0dbcfcb70ccc` |
| Source worktree | clean |
| Host | Apple M4 Max, 16 logical processors, 128 GiB |
| OS / architecture | Darwin 25.5.0 / aarch64 |
| Elixir / OTP | 1.20.2 / 29 |
| Nx / Emily | 0.12.1 / 0.7.2 |
| Backend | Emily GPU |
| Fallback policy | `raise`; no fallback observed |
| Concurrency | 4 |
| Window size | 60 seconds |
| Balanced duration | 10 minutes |
| OpenMed duration | 30 minutes |
| Model downloads | disabled |

The workload interleaves the locked selections for
`generated_large/template_heldout`, `synth_dataset_v2/all`, and
`nemotron_pii_test_subset/all`. Dataset bytes, ordered sample IDs, entity
policy, scoring policy, model revisions, and asset hashes are recorded in the
promoted JSON reports.

## Instrumentation Overhead

Each authoritative run has a diagnostics-disabled control with the same source
commit, profile, duration, concurrency, sample mode, backend, and output
fingerprints.

| Profile | Control req/s | Instrumented req/s | Throughput delta | Control p95 | Instrumented p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `:balanced` | 36.085 | 35.624 | -1.28% | 170 ms | 150 ms |
| `:openmed_pii` | 3.161 | 3.300 | +4.39% | 4,100 ms | 3,600 ms |

The p95 improvements are run variance, not an instrumentation speedup.
Throughput does not show a repeated material observer penalty. Two short
`:balanced` pairs produced deltas of `-16.64%` and `+0.85%`; the first pair
had an unusually fast control. Two short OpenMed pairs produced `+6.07%` and
`+8.36%`. The same-duration canonical pairs are the authoritative overhead
evidence.

## Balanced Diagnosis

### Reproduction

The clean control reproduces the ten-minute slowdown:

| Window | Req/s | p50 | p95 | p99 |
| --- | ---: | ---: | ---: | ---: |
| Minute 1 | 55.27 | 73 ms | 75.5 ms | 76.5 ms |
| Minute 4, minimum | 23.20 | 170 ms | 250 ms | 315 ms |
| Minute 10 | 33.65 | 120 ms | 155 ms | 180 ms |

Throughput retains `60.9%` of its first-minute value. The run later stabilizes
near `34` req/s rather than declining continuously.

### Stage Evidence

| Stage | Mean | p50 | p95 | p99 | Share of service |
| --- | ---: | ---: | ---: | ---: | ---: |
| Service total | 111.68 ms | 115 ms | 150 ms | 175 ms | 100% |
| Model serving | 108.23 ms | 110 ms | 145 ms | 170 ms | 96.91% |
| Span mapping | 0.36 ms | 0.14 ms | 1.45 ms | 3.40 ms | 0.32% |
| Queue/admission | 0.19 ms | 0.02 ms | 1.05 ms | 2.65 ms | 0.17% |
| Diagnostic token probe | 1.51 ms | 0.64 ms | 7.50 ms | 11.50 ms | 1.35% |

In the instrumented run, model-serving mean rises from `91.89` ms in minute 1
to `113.21` ms in minute 10, a `23.2%` increase. Service mean rises from
`93.56` to `117.00` ms. Model-serving time has a `-0.996` correlation with
throughput.

The model shape is fixed at sequence length `128`: one first-seen shape and
21,375 repeated requests. Mean token count falls from `63.56` to `55.61`, and
input bytes also fall. Changing workload size therefore does not explain the
slowdown.

### Balanced Root Cause

**Proven stage:** sustained slowdown occurs inside TNER model execution on the
Emily/Metal path.

**Not yet proven mechanism:** thermal throttling, Metal scheduling behavior,
or another backend/runtime effect inside the synchronized model call. Direct
GPU utilization, frequency, power, and thermal-limit counters are unavailable
because `powermetrics` requires superuser privileges. AC power is proven, but
`pmset` exposes no numeric thermal/performance limits on this host.

The smallest next experiment is an alternating C4/C2/cooldown protocol while
collecting privileged `powermetrics` or Instruments Metal System Trace. If C2
or cooldown predictably restores the minute-1 model latency twice, contention
or thermal behavior becomes causal rather than inferred.

## OpenMed Diagnosis

### Reproduction

The historical first/last observation (`3.95` to `1.37` req/s) described real
windows but implied a monotonic decline that the new 30-minute control rejects.
Selected clean-control windows are:

| Minute | Req/s | p95 |
| --- | ---: | ---: |
| 1 | 2.75 | 4,450 ms |
| 10, low | 1.08 | 7,850 ms |
| 13, recovery | 8.85 | 710 ms |
| 20, low | 1.50 | 7,300 ms |
| 26, recovery | 7.78 | 1,100 ms |
| 30 | 2.32 | 3,900 ms |

Recovery above `8` req/s occurs without rebuilding the runtime, clearing the
cache, stopping load, or changing the backend. A cumulative leak, overload, or
thermal decline cannot explain the repeated low/high cycle.

### Stage Evidence

| Stage | Mean | p50 | p95 | p99 | Share of service |
| --- | ---: | ---: | ---: | ---: | ---: |
| Service total | 1,210.98 ms | 715 ms | 3,600 ms | 6,250 ms | 100% |
| Model serving | 931.74 ms | 535 ms | 2,850 ms | 4,750 ms | 76.94% |
| Log-prob conversion | 258.37 ms | 78.5 ms | 1,150 ms | 2,300 ms | 21.34% |
| Viterbi/log-prob decode | 18.96 ms | 13.5 ms | 41 ms | 76.5 ms | 1.57% |
| Span mapping | 0.51 ms | 0.13 ms | 0.94 ms | 1.90 ms | 0.04% |
| Queue/admission | 0.0065 ms | 0.01 ms | 0.02 ms | 0.02 ms | <0.01% |

Across 30 complete windows, throughput correlations are:

| Metric | Correlation with req/s |
| --- | ---: |
| Token count / model sequence length | -0.780 |
| Input bytes | -0.748 |
| Model-serving mean | -0.845 |
| Log-prob conversion mean | -0.854 |
| Viterbi/decode mean | -0.462 |
| p50 latency | -0.842 |
| p95 latency | -0.773 |

OpenMed uses 358 observed first-seen shapes and at least 256 tracked sequence
lengths; bounded tracking reports overflow rather than hiding that fact.
First-seen model calls average `1,516.90` ms versus `894.31` ms for repeated
calls, a `1.70x` penalty. Compilation/cache specialization is measurable but
secondary: 5,597 repeated calls still carry most aggregate work.

### Controlled Workload Experiment

Two mixed two-minute probes and two fixed-triplet probes used the same source,
checkpoint, backend, C4 concurrency, and three datasets:

| Mode | Repetition | Shapes | Req/s | p95 | Model mean | Log-prob mean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Mixed | 1 | 122 | 2.34 | 4,250 ms | 1,300.34 ms | 382.13 ms |
| Mixed | 2 | 132 | 2.86 | 3,400 ms | 1,060.01 ms | 301.31 ms |
| Fixed triplet | 1 | 3 | 7.53 | 770 ms | 420.56 ms | 92.72 ms |
| Fixed triplet | 2 | 3 | 7.61 | 760 ms | 416.68 ms | 91.11 ms |

This proves that workload length/shape composition causes the large latency
and throughput changes. It does not isolate shape compilation from input
length because the fixed triplet also contains shorter inputs.

### OpenMed Root Cause

**Proven primary cause:** deterministic variation in input length and shape
within the ordered dataset cycle.

**Proven dominant stages:** sequence-dependent native model execution and
host-side log-prob conversion, together accounting for `98.28%` of service
time.

**Secondary cost:** first-seen shape specialization/compilation.

The follow-up experiment introduced adaptive sequence-length buckets and
removed unnecessary log-softmax work before Viterbi. The accepted combination
preserved output fingerprints and improved the 30-minute mixed C4 workload
from `3.553` to `4.301` req/s. See
`docs/openmed-sequence-bucketing-logprob-report.md`.

## Rejected And Unresolved Hypotheses

| Hypothesis | Decision | Evidence |
| --- | --- | --- |
| Per-request runtime/model construction | Rejected | One normal runtime build in every canonical report |
| Request queue buildup | Rejected | Admission is 0.17% of balanced service and <0.01% of OpenMed service |
| Output drift or errors | Rejected | Stable fingerprints; zero canonical failures/timeouts/rejections |
| Balanced input growth | Rejected | Tokens and bytes fall while model serving slows |
| OpenMed monotonic allocator exhaustion | Rejected as primary | Throughput repeatedly recovers; cache has positive correlation with throughput and clears to zero |
| OpenMed scheduler saturation | Rejected as primary | Scheduler utilization and CPU rise with throughput, not with slow windows |
| OpenMed Viterbi | Rejected as primary | 1.57% of service time |
| First-seen shape compilation | Secondary, not primary | 1.70x penalty, but repeated calls dominate |
| Balanced thermal/backend behavior | Inconclusive below model boundary | Privileged GPU/thermal counters unavailable |
| Attention versus MoE inside OpenMed | Inconclusive | Both are fused in the compiled device graph |

## Recommended Order

1. Continue OpenMed memory study because the optimized 30-minute run's trend
   classification remained inconclusive.
2. Test `:balanced` C2 and cooldown alternation with privileged Metal/thermal
   telemetry. Use C2 operationally until C4 sustained latency has a proven
   backend-level fix.
3. Run the same protocol on Linux/EXLA. Do not compare it directly with Apple
   results without stating the hardware/backend difference.

## Evidence

Authoritative machine-readable evidence and rendered reports are governed by:

- `eval/operational/diagnostic-manifest.json`
- `eval/operational/diagnostic-reports/`
- `eval/reports/openmed-optimization/`

The OpenMed optimization reports are committed as explicitly exploratory
evidence and are not part of the authoritative operational manifest. All
committed reports retain only aggregate metrics, hashes, safe identifiers, and
structured errors.
