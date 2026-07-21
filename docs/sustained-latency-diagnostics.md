# Sustained Latency Diagnostics

This protocol diagnoses time-dependent latency and throughput changes without
changing Obscura's model policy, entity mapping, thresholds, output spans, or
prepared-runtime lifecycle. It complements the operational benchmark and soak
protocols. It does not replace either one.

The current investigation targets:

- `:balanced` at concurrency four for at least ten minutes;
- `:openmed_pii` at concurrency four for at least thirty minutes.

Both workloads use the same ordered authoritative selections as the promoted
operational evidence:

- `generated_large/template_heldout`;
- `synth_dataset_v2/all`;
- `nemotron_pii_test_subset/all`.

## Measurement Boundary

Request instrumentation is process-local, disabled by default, and bounded.
Each request retains only aggregate counts, durations, and numeric shape
metadata until the load runner merges them into bounded histograms. Reports do
not retain source text, token IDs, decoded labels, span values, sample IDs,
checkpoint paths, credentials, or per-request event lists.

The request gateway measures:

- queue/admission delay;
- complete service time;
- NLP artifact preparation;
- recognizer execution;
- tokenization and token packing where exposed;
- model serving;
- log-probability conversion;
- Viterbi or argmax decoding;
- span reconstruction and entity mapping;
- analyzer filtering;
- conflict resolution;
- final sorting/assembly.

For Bumblebee token classification, the serving owns tokenizer preprocessing
inside `Nx.Serving`. The diagnostic performs a separate BinaryBackend token
count probe. Its duration is reported as
`diagnostic_token_count_probe` and is included in the instrumentation overhead
comparison.

Privacy-filter attention and MoE execute inside one compiled Emily device
graph. Elixir function timing around graph construction would not represent
device execution. These stages are therefore marked
`fused_compiled_device_graph`, while the synchronized model-serving boundary
is measured. A future kernel-level profiler may refine the fused stage, but
reports must not invent attention or MoE durations.

## Shape Evidence

The runtime host tracks at most 256 numeric model shapes. Shape identity uses
the effective model sequence length and request window count. Reports compare
model-serving latency for first-seen and repeated shapes.

The output-stability probe runs before measurement. Diagnostic shape history
is reset after that probe without rebuilding the model, clearing allocator
state, or changing the warm-runtime contract.

`fixed_triplet` is an exploratory causal-control workload. It repeatedly uses
one authoritative sample from each of the three datasets, so dataset presence
and model behavior remain unchanged while input shapes are held constant. It
cannot be promoted as canonical evidence.

## Environmental Sampling

The runner samples once per second:

- input byte, token, model-sequence, and window distributions;
- requests completed and in flight;
- runtime-host mailbox length;
- run queue and interval scheduler utilization;
- BEAM memory, process count, reductions, and garbage collection counters;
- process CPU percentage and RSS;
- Emily active, cache, and peak allocator values;
- macOS power source;
- numeric `pmset` thermal/performance limits when the OS exposes them.

Emily allocator values are not physical GPU residency or GPU utilization.
On macOS, GPU utilization, frequency, and power require privileged
`powermetrics`. A run without those privileges records
`powermetrics_requires_superuser`; it does not infer GPU activity from backend
selection or allocator values.

## Controlled Experiments

Every instrumented confirmation references a diagnostics-disabled control from
the same source revision, profile, concurrency, duration, sample mode, backend,
device, and output probe. The report records throughput and p95 overhead and
rejects a mismatched control.

Recommended exploratory sequence:

1. short diagnostics-disabled mixed control;
2. same-duration diagnostics-enabled mixed probe;
3. repeat both to estimate instrumentation variance;
4. two `fixed_triplet` probes for any suspected shape effect;
5. canonical mixed confirmation after the mechanism is understood.

A correlation is not a proven cause. A root cause can be called proven only
when a controlled factor change predictably changes the degradation in at
least two repetitions. Otherwise the report must use `supported`,
`rejected`, or `inconclusive`.

## Commands

Prepare the Apple/Emily environment:

```sh
export OBSCURA_REAL_MODEL_BACKEND=emily
export OBSCURA_PRIVACY_FILTER_BACKEND=emily
export OBSCURA_EMILY_DEVICE=gpu
export OBSCURA_EMILY_FALLBACK=raise
export OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openmed-nemotron-v2
```

Run a control:

```sh
mix obscura.operational.diagnose \
  --profile balanced \
  --concurrency 4 \
  --duration-ms 120000 \
  --kind control \
  --no-diagnostics \
  --run-id balanced_control_r1
```

Run its instrumented comparison:

```sh
mix obscura.operational.diagnose \
  --profile balanced \
  --concurrency 4 \
  --duration-ms 120000 \
  --kind instrumented \
  --run-id balanced_probe_r1 \
  --control-report eval/reports/operational/diagnostics/balanced-balanced_control_r1-c4-120000.json
```

Hold the three-dataset workload to a fixed triplet:

```sh
mix obscura.operational.diagnose \
  --profile openmed_pii \
  --concurrency 4 \
  --duration-ms 300000 \
  --sample-mode fixed_triplet \
  --run-id openmed_fixed_triplet_r1
```

Run canonical confirmations:

```sh
mix obscura.operational.diagnose \
  --profile balanced \
  --concurrency 4 \
  --authoritative \
  --run-id balanced_canonical_r1 \
  --control-report CONTROL_REPORT

mix obscura.operational.diagnose \
  --profile openmed_pii \
  --concurrency 4 \
  --authoritative \
  --run-id openmed_canonical_r1 \
  --control-report CONTROL_REPORT
```

Authoritative validation requires:

- a clean source revision;
- mixed sample mode and all three datasets;
- canonical duration and concurrency;
- Emily GPU proof with fallback `raise`;
- zero failures, rejections, timeouts, or output mismatches;
- at least 95% resource-sampling coverage;
- complete stage, input, shape, correlation, resilience, and runtime-reuse
  evidence;
- a matching diagnostics-disabled control;
- privacy-safe, portable JSON and Markdown.

Promote and verify:

```sh
mix obscura.operational.diagnostic.promote --report REPORT_JSON
mix obscura.operational.diagnostic.verify
```

Authoritative files live under:

- `eval/operational/diagnostic-manifest.json`;
- `eval/operational/diagnostic-reports/`.

Working files under `eval/reports/operational/diagnostics/` are exploratory or
unpromoted even when their internal status is complete.
