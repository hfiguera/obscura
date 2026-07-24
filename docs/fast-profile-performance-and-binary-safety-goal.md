# Fast Profile Performance and Binary Safety Goal

## Purpose

Optimize Obscura's stable `:fast` profile as far as the evidence supports while
preserving its public behavior, accuracy, and dependency-light runtime.

This phase has two independent objectives:

1. Reduce warm latency, tail latency, allocations, reductions, and memory
   pressure for `:fast`.
2. Prove that small detections and short-lived intermediate values do not keep
   large source binaries reachable longer than required.

Neither objective may be achieved by weakening the other. A change which makes
one microbenchmark faster but increases retained source memory, changes
detections, breaks byte offsets, or moves raw PII into another long-lived
structure must be rejected.

## Branch And Delivery

Work only on:

```text
performance/fast-profile-binary-safety
```

The branch must start from `main`.

Keep every experiment narrow and independently measurable. Commit an experiment
only after its tests and benchmark gates pass. Record rejected experiments in
the final report so they are not repeated later. Do not promote exploratory
reports as authoritative evidence.

The completed phase must include:

- implementation changes;
- focused unit, property, retention, and integration tests;
- a reusable dependency-light benchmark and retention harness;
- fresh before/after performance evidence;
- fresh accuracy and output-fingerprint evidence;
- a long-duration memory report;
- updated public documentation where behavior or guarantees changed;
- one final report explaining gains, regressions, retained risks, and rejected
  experiments.

## Read First

Read these files before changing code:

- `README.md`
- `docs/profiles.md`
- `docs/public-api-stability.md`
- `docs/security-threat-model.md`
- `docs/security-review-report.md`
- `docs/known-limitations.md`
- `docs/operational-benchmarking.md`
- `docs/operational-benchmark-report.md`
- `docs/operational-soak-and-memory.md`
- `docs/operational-soak-and-memory-report.md`
- `lib/obscura.ex`
- `lib/obscura/input.ex`
- `lib/obscura/profile.ex`
- `lib/obscura/profile/runtime.ex`
- `lib/obscura/analyzer/options.ex`
- `lib/obscura/analyzer/result.ex`
- `lib/obscura/analyzer/engine.ex`
- `lib/obscura/anonymizer/engine.ex`
- `lib/obscura/eval/offset.ex`
- `lib/obscura/recognizer/registry.ex`
- `lib/obscura/recognizer/pattern_definition.ex`
- `lib/obscura/recognizer/pattern.ex`
- `lib/obscura/recognizer/deny_list.ex`
- `lib/obscura/context.ex`
- `lib/obscura/conflict.ex`
- every deterministic recognizer selected by `:deterministic_plus`;
- structured traversal, Logger, Plug, CLI, and operational runner modules which
  call `:fast`;
- existing analyzer, anonymizer, security-property, profile, fixture, and
  operational tests.

Search the full dependency-light path for at least:

```sh
rg -n \
  "binary_part|slice_bytes|referenced_byte_size|binary.copy|include_text|\
iodata_to_binary|List.flatten|acc \\+\\+|Enum.sort|Enum.uniq|Task.async_stream" \
  lib test eval docs
```

Do not restrict the investigation to `binary_part/3`. Regex captures, string
functions, maps, explanations, callback returns, task messages, structured
items, and operator metadata can also retain or copy binaries.

## Current Evidence

The committed operational evidence establishes a useful historical reference,
not the new baseline:

- `:fast` resolves to `:deterministic_plus`.
- It runs on BEAM CPU without model assets.
- The optional phone parser is the only optional dependency associated with
  the stable product profile.
- The ten-minute concurrency-4 soak completed 10,591,487 requests at
  17,652.45 requests/second with no failures, rejections, or timeouts.
- First and last one-minute windows retained 99.25% of throughput.
- First and last p50/p95/p99 were approximately
  `0.16 / 0.56 / 0.99 ms` and `0.16 / 0.56 / 1.00 ms`.
- RSS finished below its initial value, but BEAM total memory rose from
  `79.2 MiB` to `116.8 MiB`.
- The conservative memory classifier therefore left retained memory
  `inconclusive`.

These values were measured on a previous source revision and cannot be used as
the before side of this phase. Capture a fresh baseline on the same machine,
runtime, datasets, and command configuration used for the final comparison.

## Definitions

Use precise terms in code, reports, and documentation.

### Borrowed Sub-Binary

A binary value whose storage may reference a larger parent binary. A short
visible value can therefore keep the parent reachable.

### Owned Binary

A binary whose retained storage is independent of an unrelated larger source
binary. Ownership here concerns reachability and retention, not secure
zeroization.

### Temporary Reference

A reference needed only during a synchronous operation and no longer reachable
after that operation, its worker tasks, and garbage collection complete.

### Retention Defect

A returned result, process state, mailbox message, ETS entry, callback state,
or other long-lived object unintentionally keeps a substantially larger source
binary reachable.

### Allocation Regression

A change which removes parent retention by copying excessively and materially
worsens allocation volume, garbage collection, latency, throughput, or RSS.

### Binary Leak

Use this term only when evidence demonstrates unbounded or unintended retained
growth. A ref-counted binary, allocator high-water behavior, delayed garbage
collection, or a noisy RSS slope is not by itself proof of a leak.

### Privacy Lifetime

The period during which raw source PII remains reachable through documented
results or internal runtime state. Obscura cannot promise in-place zeroization
of immutable BEAM binaries, allocator pages, caller-owned inputs, crash dumps,
VM tracing, or privileged process inspection.

## Non-Negotiable Invariants

### Public API

- `:fast` must remain stable and resolve to `:deterministic_plus`.
- No new required runtime dependency may be added.
- `include_text: true` must remain the compatibility default for analyzer calls.
- `include_text: true` must return exact matched text in `Result.text`.
- `include_text: false` must return `text: nil`.
- Documented `Obscura.Analyzer.Result` fields and their types must remain
  compatible with the `0.1.x` public API policy.
- Custom recognizers, pattern definitions, deny lists, allow lists, language
  callbacks, operators, Logger integration, Plug integration, structured
  traversal, CLI commands, and telemetry contracts must remain compatible.
- Error shapes and safe `Inspect` behavior must not regress.

### Detection Semantics

For identical input and options, the optimized implementation must preserve:

- result count and ordering;
- entity type;
- byte start and byte end;
- score within the existing deterministic numerical contract;
- recognizer identity;
- conflict decisions;
- context acceptance and score behavior;
- relevant metadata and explanation semantics;
- anonymized output and replacement-item offsets.

If an optimization intentionally changes semantics, treat it as a separate
quality change. It must not be hidden inside this performance phase.

### Privacy

Raw source text must not be added to:

- errors or exception messages;
- safe inspection output;
- Logger events;
- telemetry metadata;
- stage diagnostics;
- benchmark reports;
- retained task exit reasons;
- process names or registry keys;
- ETS tables other than an explicitly requested reversible vault;
- metadata or explanations that previously contained no raw source value.

## Core Design Direction

Do not begin by replacing every `binary_part/3` call with
`:binary.copy/1`. That may trade retention for copying and garbage-collection
pressure.

Investigate and prefer this ordering:

1. Built-in recognizers produce offsets and only the temporary values required
   for validation.
2. Filtering, allow-list handling, context scoring, thresholding, and conflict
   resolution operate on offsets and metadata wherever possible.
3. Dropped candidate results never receive an owned text copy.
4. `include_text: false` never materializes final result text.
5. `include_text: true` materializes exact text only for final accepted results.
6. Escaping text is independently owned when retaining it would otherwise keep
   an unrelated larger input alive.

An internal binary-slice helper may be appropriate if it centralizes and tests
the policy. Keep it private to Obscura unless a public API is demonstrably
necessary.

Potential internal operations include:

- validation-only borrowed slice;
- final optional result materialization;
- explicit owned copy;
- referenced-size observation for tests or an evidence-backed heuristic.

Do not expose VM-specific details as a stable public contract.

## Required Workstream 1: Establish A Fresh Baseline

Before implementation changes:

1. Record source revision, dirty state, host, OS, architecture, Elixir, OTP, and
   dependency versions.
2. Confirm `Profile.resolve(:fast) == {:ok, :deterministic_plus}`.
3. Run the full test and quality suite.
4. Run fresh accuracy evaluation on all authoritative datasets.
5. Capture output fingerprints for representative analyzer, anonymizer,
   structured, Logger, Plug, CLI, and `analyze_many/2` calls.
6. Run the dependency-light microbenchmark matrix below.
7. Run the existing operational matrix for `:fast`.
8. Run the new binary-retention probes before changing behavior.

Do not compare a new optimized run against historical results captured with a
different source revision or runtime configuration.

## Required Workstream 2: Build A Reusable Benchmark Harness

The harness must run without Nx, Bumblebee, Emily, EXLA, Ortex, model assets, or
network access. Do not add a production dependency solely for benchmarking.

It must measure:

- elapsed mean, p50, p95, p99, and maximum latency;
- throughput;
- BEAM reductions per operation;
- garbage-collection count and reclaimed words where measurable;
- process heap and total-heap changes;
- process binary references where measurable;
- `:erlang.memory(:binary)`, `:erlang.memory(:processes)`, and total memory;
- process RSS;
- result count and output fingerprint;
- warm-up and measured iteration counts.

Use monotonic time. Keep samples bounded; do not retain every latency from a
long run. Separate harness overhead from the operation under test.

### API Matrix

Measure at least:

- `Obscura.analyze/2` with `include_text: false`;
- `Obscura.analyze/2` with `include_text: true`;
- detection followed by anonymization;
- each supported anonymization operator with realistic options;
- `Obscura.analyze_many/2` at batch sizes `1`, `8`, `32`, and `128`;
- structured redaction of nested maps and lists;
- Logger and Plug boundary paths with safe sinks;
- all default `:fast` entities;
- one requested entity at a time;
- no requested match;
- one match;
- many matches;
- overlapping candidate matches.

### Input Matrix

Use deterministic, synthetic values only:

- ASCII and multibyte UTF-8;
- approximately 128 B, 1 KiB, 64 KiB, and 1 MiB inputs;
- a tiny match at the beginning, middle, and end;
- no match in a large input;
- dense repeated matches;
- long lines and many short lines;
- malformed UTF-8 through public error boundaries;
- phone parser disabled and enabled when `ex_phone_number` is installed.

Keep fixtures private to tests/evaluation and ensure reports contain hashes,
sizes, and labels rather than raw PII-like values.

### Measurement Discipline

- Pin one scheduler/runtime configuration for before/after comparisons.
- Warm code paths before measurement.
- Avoid concurrent unrelated workloads.
- Run at least three clean repetitions.
- Alternate baseline and candidate order when possible.
- Report median repetition and full range.
- Treat differences smaller than observed run-to-run noise as inconclusive.
- Keep raw working reports outside authoritative manifests until promotion.

## Required Workstream 3: Prove Binary Ownership And Release

Create focused tests and an executable diagnostic harness for binary retention.
Aggregate RSS alone is insufficient.

### Required Probe Shape

For each relevant API:

1. Spawn a dedicated worker process.
2. Construct a large source binary inside that worker so the test process does
   not retain it accidentally.
3. Place one short synthetic detection near the beginning, middle, or end.
4. Execute the API.
5. Keep only the documented returned object being tested.
6. Drop all explicit source and temporary references.
7. Ensure spawned recognizer tasks have terminated and mailboxes are drained.
8. Force garbage collection where the VM permits.
9. Observe the retained result binary with
   `:binary.referenced_byte_size/1`.
10. Supplement this with `Process.info(pid, :binary)`, process memory, and
    `:erlang.memory(:binary)` observations.
11. Destroy the holder and prove the retained binary is subsequently
    releasable.

Use VM observations as test evidence, not as a public guarantee. Avoid brittle
assertions on allocator timing or exact RSS bytes.

### Required Cases

- `analyze(..., include_text: false)` with a 1 MiB source and tiny match;
- `analyze(..., include_text: true)` with the same source;
- zero matches;
- many accepted matches;
- candidates later removed by score, allow list, context, or conflict handling;
- `analyze_many/2` where one large item has a tiny match;
- anonymizer output and `Anonymizer.Item` values;
- structured results containing one large binary leaf;
- custom recognizer returning `text: nil`;
- custom recognizer returning a borrowed `text` slice;
- pattern recognizer and deny-list matches;
- successful, error, exception, throw, exit, timeout, and task-cancellation paths;
- telemetry enabled and disabled;
- explanation enabled and disabled;
- Logger and Plug integrations;
- reversible vault paths as a separately documented intentional retention case.

### Required Assertions

For `include_text: false`:

- no final result contains source text;
- accepted and rejected built-in candidates do not create an unnecessary owned
  match copy;
- after source release and worker cleanup, no returned result or long-lived
  Obscura process keeps the large source binary referenced;
- no explanation or metadata field reintroduces the source.

For `include_text: true`:

- `Result.text` equals the exact byte slice indicated by offsets;
- a tiny returned match does not retain the unrelated remainder of a large
  source binary;
- copying is limited to final escaping values unless evidence requires
  otherwise.

For anonymization:

- output text is independently valid and contains only the expected replacement
  or preserved non-sensitive content;
- replacement items do not retain original source values unless explicitly
  documented by an operator contract;
- reversible pseudonymization retains source values only inside the caller's
  explicit vault boundary.

## Required Workstream 4: Eliminate Unnecessary Text Materialization

Currently, `include_text: false` can still allow recognizers to construct
result text before the analyzer later replaces it with `nil`. Change the
built-in deterministic path so text omission is propagated to the point where
matches are constructed.

Requirements:

- built-in recognizers must honor the normalized `include_text` option;
- validators which need a temporary match may borrow it only for the duration
  of validation;
- context and conflict code must not require persistent result text when exact
  offsets are available;
- result validation must continue checking offsets safely when `text` is `nil`;
- custom recognizer compatibility must be retained;
- accepted final text must be materialized centrally or through one consistent
  internal policy;
- candidate text must not be copied before allow-list, threshold, context, and
  conflict rejection when it can be avoided safely.

Add tests proving that `include_text: false` avoids materialization rather than
merely removing text from the final struct.

## Required Workstream 5: Optimize Analyzer Assembly

Profile and test these known candidates; do not assume each is beneficial:

- repeated `Options.to_keyword/1` construction for every recognizer;
- repeated registry filtering and supported-entity expansion;
- `acc ++ results` in sequential and parallel recognizer accumulation;
- repeated entity-list membership checks;
- repeated sorting across conflict resolution and final assembly;
- exact-duplicate and contained-span passes;
- repeated result maps used only to add metadata;
- redundant byte-span validation or slicing;
- repeated context tokenization or lowercasing;
- artifacts construction when `:fast` does not need NLP artifacts;
- telemetry and stage-diagnostic overhead when enabled or disabled;
- task setup where deterministic recognizers are faster sequentially;
- `analyze_many/2` fallback traversal and per-item option reconstruction.

Favor simple local changes. Introduce caching only when:

- keys are bounded;
- invalidation is unnecessary or explicit;
- values contain no source text or callback state;
- concurrency behavior is tested;
- cache overhead is lower than recomputation;
- the cache cannot become a new retention surface.

Do not create a global cache of arbitrary caller options, entity lists, regular
expression matches, source text, or results.

## Required Workstream 6: Optimize Deterministic Recognizers

Measure each recognizer independently and as part of the full profile.

Inspect at least:

- email;
- phone, including parser-backed mode;
- credit card and checksum validation;
- IBAN;
- US SSN;
- IP address;
- URL;
- domain;
- deterministic person;
- deterministic location;
- address and address components;
- title and date/time recognizers used by `:deterministic_plus`;
- custom patterns and deny lists.

For each recognizer, investigate:

- duplicate regex scans over the same input;
- repeated capture extraction;
- unnecessary `String` conversion or normalization;
- validation after expensive value copying;
- construction of explanations when `explain: false`;
- metadata maps constructed for candidates later rejected;
- invalid or duplicate candidates that could be rejected earlier;
- parser invocation for impossible candidates;
- entity selection checks repeated inside match loops.

Do not merge recognizers into a single opaque scan unless it preserves custom
recognizer ordering, scoring, explanations, conflicts, and maintainability.

## Required Workstream 7: Optimize Anonymization And Structured Paths

The analyzer benchmark alone is not enough because `:fast` is commonly used at
application boundaries.

Investigate:

- normalization of analyzer results back into anonymizer spans;
- repeated span sorting and validation;
- prefix/source slicing in replacement assembly;
- operator option validation repeated for homogeneous calls;
- iodata construction and one final `IO.iodata_to_binary/1`;
- replacement item metadata;
- structured traversal path construction;
- repeated profile and option normalization for each structured leaf;
- list concatenation and reversal behavior;
- Logger and Plug wrappers.

Preserve:

- exact anonymized output;
- replacement offsets;
- operator behavior;
- traversal depth and limit handling;
- safe error and inspection contracts;
- no mutation of caller data.

Any reusable normalized configuration must be explicit, immutable, bounded,
safe to share, and free of input values.

## Required Workstream 8: Property And Regression Testing

Add focused tests for:

- exact result equivalence before and after optimization;
- `include_text: true` and `false`;
- multibyte UTF-8 byte offsets;
- empty and very large input;
- dense, adjacent, contained, duplicate, and overlapping spans;
- allow-list and context filtering;
- all conflict strategies;
- all stable operators;
- `analyze_many/2` ordering and batch equivalence;
- structured traversal equivalence;
- custom recognizer compatibility;
- callback failures and timeouts;
- no raw values in errors, inspection, telemetry, or diagnostics.

Use StreamData properties where useful:

- returned spans are ordered and within byte bounds;
- returned text, when present, equals the source byte slice;
- `include_text` does not alter entities, offsets, scores, or ordering;
- analyzing items individually equals `analyze_many/2`;
- optimized and reference implementations produce the same fingerprint;
- anonymized replacement offsets reconstruct the documented output;
- random Unicode and malformed boundary inputs return valid results or
  controlled errors without leaking source values.

Keep a straightforward reference implementation or golden fixture path where
it helps prove equivalence. Do not benchmark a test-only reference as if it
were the production baseline.

## Required Workstream 9: Performance Experiment Loop

For every proposed optimization:

1. State the hypothesis and affected stage.
2. Record the expected benefit and possible regression.
3. Add or update correctness and retention tests first.
4. Run focused tests.
5. Run the relevant microbenchmark at least three times.
6. Compare latency, throughput, reductions, allocations, garbage collection,
   and retained binary evidence.
7. Run full `mix test`.
8. Keep the change only when the improvement is larger than measurement noise
   and no acceptance gate regresses.
9. Commit the accepted experiment with its evidence identifier.
10. Revert rejected implementation changes without deleting the recorded
    experiment result.

The final report must contain a table:

| Experiment | Hypothesis | Result | Speed effect | Allocation effect | Retention effect | Decision | Commit |
| --- | --- | --- | ---: | ---: | --- | --- | --- |

Do not optimize only the fastest 128-byte happy path. Large-input and
many-match cases are central to the binary-safety goal.

## Required Workstream 10: Final Validation Matrix

### Quality

Run at least:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix obscura.fixtures
mix obscura.fixtures --suite accuracy
mix obscura.benchmarks.verify
mix obscura.operational.verify
mix obscura.operational.soak.verify
mix credo --strict --all
mix dialyzer
mix ex_dna
mix ex_slop
mix credence
mix obscura.docs.verify
mix docs
```

Run the repository's complete `mix ci` or equivalent precommit command if the
aliases change after this document is written.

### Accuracy

Run fresh `:fast` reports on:

- `generated_large/template_heldout`;
- `synth_dataset_v2/all`;
- `nemotron_pii_test_subset/all`.

Compare:

- precision;
- recall;
- F1;
- F2;
- true positives;
- false positives;
- false negatives;
- wrong entity type;
- offset mismatches;
- unsupported spans;
- per-entity metrics;
- output fingerprints.

Performance work must not claim an accuracy gain unless detection semantics
were intentionally changed and separately reviewed.

### Operational

Run `:fast` at concurrency:

```text
1, 2, 4, 8, 16
```

For every authoritative dataset, report:

- p50, p95, and p99 latency;
- throughput;
- failures, rejections, and timeouts;
- peak and final RSS;
- BEAM total, process, binary, and ETS memory;
- scheduler utilization and run queue;
- runtime construction count;
- output fingerprint.

Run clean baseline and final matrices with the same hardware and runtime
configuration. Perform at least two final clean repetitions; use three where
noise makes the result ambiguous.

### Long-Duration Retention

Run:

- the existing canonical ten-minute `:fast`, concurrency-4 soak;
- a new 30-minute targeted binary-retention soak;
- concurrency 1 and 4 targeted variants where runtime permits.

The targeted workload must alternate:

- large no-match inputs;
- large inputs with one tiny match;
- large inputs with many candidates but few accepted results;
- `include_text: false`;
- `include_text: true` with results held for a bounded interval;
- structured inputs with large binary leaves;
- success and controlled callback failure.

Sample:

- process RSS;
- BEAM total/process/binary/ETS memory;
- holder process memory and binary references;
- mailbox lengths;
- garbage-collection counts;
- completed requests;
- first-half and final-half slopes;
- post-idle and post-GC observations.

Classify the finite run as `stable_plateau`, `probable_leak`, or
`inconclusive` using documented thresholds. Do not call it leak-free merely
because the process did not crash.

## Acceptance Gates

### Correctness Gate

- Full tests and quality checks pass.
- All three authoritative `:fast` accuracy fingerprints are unchanged.
- Exact spans, result ordering, scores, anonymized outputs, and replacement
  offsets are unchanged.
- Custom recognizer and public API contract tests pass.

### Binary-Safety Gate

- `include_text: false` creates no escaping match-text binary for built-in
  accepted results.
- After source release, worker termination, mailbox drain, and GC, returned
  offset-only results do not retain the large source binary.
- A tiny `include_text: true` result does not retain an unrelated large parent
  binary.
- Rejected candidates do not leave owned copies or borrowed parent references
  in long-lived state.
- No raw PII appears in errors, inspection, logs, telemetry, diagnostics, or
  reports.
- The targeted soak shows no monotonic request-correlated retained binary
  growth. If evidence remains noisy, report `inconclusive`; do not overclaim.

### Performance Gate

At minimum:

- no statistically meaningful regression in p50, p95, p99, or throughput for
  any authoritative dataset at concurrency 1 or 4;
- no material regression for 64 KiB and 1 MiB inputs;
- no material increase in reductions, allocations, or garbage collection
  without a documented binary-retention benefit;
- no increase in steady-state RSS or BEAM binary memory beyond run-to-run
  noise.

The target, rather than a guaranteed outcome, is:

- at least 10% lower median warm latency or at least 10% higher throughput in
  the representative full-profile workload;
- at least 15% lower allocation or reduction cost in one identified hot stage;
- independently owned final match text without broad copy amplification;
- a stronger memory conclusion than the current `inconclusive` evidence.

If safety improves but speed remains statistically unchanged, the phase may
still succeed. Report it as a binary-safety improvement, not a performance
win.

### Scope Gate

- No required optional/model dependency is introduced.
- No model-backed profile is changed.
- No broad recognizer-quality redesign is mixed into this phase.
- No benchmark is promoted from a dirty worktree.
- No raw fixture values enter committed reports.

## Rejected Approaches Unless Proven

Do not accept these by assumption:

- copying every binary slice;
- globally changing the analyzer default to `include_text: false`;
- removing result validation;
- disabling telemetry or explanations regardless of caller options;
- caching arbitrary user options or source-dependent objects;
- parallelizing every deterministic recognizer;
- replacing clear code with a fused opaque regular expression;
- relaxing conflict resolution;
- skipping entities to make the profile faster;
- changing thresholds or context policy;
- reducing benchmark datasets or input sizes;
- treating one microbenchmark as production evidence;
- treating RSS alone as proof of binary ownership;
- promising secure erasure on the BEAM.

## Documentation And Final Report

Create:

```text
docs/fast-profile-performance-and-binary-safety-report.md
```

The report must include:

1. Executive conclusion: whether `:fast` became faster and whether binary
   retention was resolved, reduced, unchanged, or still inconclusive.
2. Source revisions and environment.
3. Exact baseline and final commands.
4. Architecture changes.
5. Public API and behavior invariants.
6. Before/after microbenchmark matrix.
7. Before/after operational matrix.
8. Before/after accuracy and fingerprints.
9. Binary ownership probe evidence.
10. Long-duration memory evidence.
11. Accepted experiments and commits.
12. Rejected experiments and reasons.
13. Remaining risks and limitations.
14. Recommended use of `include_text: true` versus `false`.
15. The next measured optimization opportunity.

Update relevant public documentation only when the final implementation changes
guidance or guarantees. Keep internal experiment detail out of ExDoc unless it
helps users make a deployment decision.

The final language must distinguish:

- exact output equivalence from benchmark accuracy;
- object-level binary ownership from allocator memory behavior;
- bounded finite-run evidence from a universal no-leak claim;
- less retention from secure memory erasure;
- statistically meaningful speedup from benchmark noise.

## Final Completion Checklist

- [ ] Branch was created from `main`.
- [ ] Fresh baseline was captured before optimization.
- [ ] Benchmark harness covers text, batch, anonymization, and structured APIs.
- [ ] Binary-retention harness covers success and failure paths.
- [ ] `include_text: false` avoids match-text materialization in built-ins.
- [ ] Final `include_text: true` text does not retain unrelated large parents.
- [ ] Custom recognizer compatibility remains intact.
- [ ] Accuracy fingerprints are unchanged on all three authoritative datasets.
- [ ] Two or more clean final operational repetitions agree.
- [ ] Ten-minute canonical and 30-minute targeted soaks completed.
- [ ] Raw PII did not enter reports, logs, telemetry, errors, or diagnostics.
- [ ] Every accepted experiment has a measured benefit and passing tests.
- [ ] Every rejected experiment is recorded.
- [ ] Full quality suite passes.
- [ ] Final report states what is proven and what remains inconclusive.
- [ ] All resulting implementation, test, report, and documentation changes are
      committed with clear messages.
