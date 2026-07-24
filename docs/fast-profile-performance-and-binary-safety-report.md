# Fast Profile Performance And Binary Safety Report

## Executive Conclusion

The stable `:fast` profile is faster on the measured workloads and no longer
returns tiny match binaries which retain unrelated large source binaries.

The strongest measured changes are:

- `1 KiB` no-match p50 fell by `67.1%`;
- `64 KiB` one-match p50 fell by `91.4%` to `91.5%`;
- `1 MiB` one-match p50 fell by `93.0%`;
- the `400 KiB` retained-URL p50 fell by `97.7%`;
- detect-plus-redact p50 fell by `8.8%`;
- all `25` complete returned-object-graph ownership probes have zero borrowed
  binaries; text probes changed from as much as `744.879x` referenced-size
  amplification to exactly `1.0x`, or to no text binary;
- all three authoritative accuracy and per-entity fingerprints remained
  unchanged;
- two independent 30-minute targeted soaks classified binary retention as a
  `stable_plateau`.

These results prove output equivalence and returned-object ownership for the
tested built-in and controlled extension paths. They do not prove that
arbitrary caller-supplied callbacks cannot retain input, secure erasure,
universal absence of leaks, or bounded allocator RSS for every workload.

## Revisions And Environment

| Role | Revision |
| --- | --- |
| Clean baseline | `bf64512d0619bb4e54282308b1ebca32eb1de93d` |
| Owned final result text | `11461fbd` |
| Deferred dependency-light artifacts | `cde7ee2c` |
| Targeted retention soak | `cd54ca09` |
| Final validated implementation before this report | `22e7e0dd` |
| Review corrections and expanded verification | `11bcd664` |

The paired baseline and final microbenchmarks ran on:

- Apple M4 Max;
- macOS `25.5.0`;
- `aarch64-apple-darwin25.5.0`;
- 16 online schedulers;
- Elixir `1.20.2`;
- Erlang/OTP `29`;
- Obscura `0.1.1`;
- BEAM CPU execution with no model backend.

The operational baseline ran from a detached worktree at the clean baseline
revision. Three final operational repetitions ran from clean revision
`cd54ca09`. The review correction was validated at `11bcd664` with an expanded
45-case benchmark harness, a 25-case complete returned-graph retention harness,
alternating paired performance runs, a five-minute targeted soak, full tests,
and static checks.

## Commands

Baseline and final microbenchmarks:

```sh
mix run eval/fast_profile/benchmark.exs -- \
  --label baseline_clean \
  --repetitions 5 \
  --scale 1.0 \
  --output eval/reports/fast_profile/baseline_clean.json

mix run eval/fast_profile/benchmark.exs -- \
  --label paired_final_candidate \
  --repetitions 5 \
  --scale 1.0 \
  --output eval/reports/fast_profile/paired_final_candidate.json
```

Ownership probes:

```sh
mix run eval/fast_profile/retention.exs -- \
  --label review_corrections_final_v2 \
  --output eval/reports/fast_profile/retention_review_corrections_final_v2.json
```

Operational matrix:

```sh
mix obscura.operational.benchmark \
  --profiles fast \
  --repetitions 2 \
  --sustained-duration-ms 60000 \
  --output-root eval/reports/fast_profile/operational_final_r1
```

The final command was repeated into `operational_final_r2` and
`operational_final_r3`. The clean baseline used the same command and datasets
from the detached baseline worktree.

Soaks:

```sh
mix obscura.operational.soak \
  --profile fast \
  --concurrency 4 \
  --authoritative \
  --output-root eval/reports/fast_profile/soak_canonical_final

mix run eval/fast_profile/soak.exs -- \
  --label final_c4_30m \
  --duration-ms 1800000 \
  --concurrency 4 \
  --output eval/reports/fast_profile/targeted_soak_final_c4_30m.json

mix run eval/fast_profile/soak.exs -- \
  --label final_c1_30m \
  --duration-ms 1800000 \
  --concurrency 1 \
  --output eval/reports/fast_profile/targeted_soak_final_c1_30m.json
```

## Architecture Changes

### Final text ownership

Built-in recognizers honor `include_text` while constructing candidate
results. Address, domain, location, and person recognition no longer create a
match sub-binary when `include_text: false`.

With `include_text: true`, candidate filtering, allow-list handling, context,
thresholding, and conflict resolution happen before central final assembly.
Final assembly copies only escaping sub-binaries whose referenced size exceeds
their own byte size. Already-owned binaries are reused.

Custom recognizers remain compatible. Their returned text is removed when
`include_text: false`; with `include_text: true`, an existing binary is detached
at final assembly when it borrows a larger source binary. A custom result with
`text: nil` remains nil, preserving the nullable public result contract.

Recognizer exceptions, throws, and exits are converted to structured,
input-free failure reasons. This prevents an exit reason containing source text
from reaching task-exit logs.

Allow-list matching derives temporary values from source offsets when result
text is absent. Parser-backed phone validation similarly uses temporary source
slices without putting text into escaping candidate results.

### Dependency-light NLP artifacts

The built-in `:deterministic_plus` pipeline previously tokenized every input
into `Obscura.NLP.Artifacts` before deterministic recognizers ran. This
duplicated full-input token and lemma work even when there were no results or
no context-dependent results.

The analyzer now defers those artifacts only when all of these are true:

- the resolved profile is `:deterministic_plus`;
- no custom recognizers are configured;
- no explicit artifacts are supplied;
- no NLP engine is configured.

Context processing builds artifacts lazily only when a result or caller context
actually requires token-aware matching. Custom recognizers and explicit NLP
engines continue to receive central artifacts.

Lazy construction is measured as `:nlp_artifacts`. Context enhancement and
acceptance filtering have separate diagnostic stages, so operational reports no
longer attribute tokenization to `:analyzer_filtering`.

## Public Behavior Invariants

The following contracts did not change:

- `:fast` still resolves to `:deterministic_plus`;
- `include_text: true` remains the default;
- built-in returned text equals the exact source byte range;
- a custom recognizer's documented nullable `text` value remains nil;
- `include_text: false` returns `text: nil`;
- entities, byte offsets, scores, metadata, ordering, and conflict behavior are
  unchanged;
- custom recognizers still receive NLP artifacts;
- explicit NLP engines and supplied artifacts still take precedence;
- analyzer, batch, anonymizer, structured, telemetry, and error shapes are
  unchanged.

Property and contract tests prove that changing `include_text` changes only
the documented text field for built-in recognizers. Custom-recognizer tests
separately prove borrowed binary detachment and nil preservation.

## Microbenchmark Matrix

This table uses an immediate paired run of the exact baseline revision and the
final revision after the long soaks. Times are microseconds. Throughput is
operations per second.

| Case | p50 baseline -> final | p95 baseline -> final | p99 baseline -> final | Throughput baseline -> final | Reductions baseline -> final |
| --- | ---: | ---: | ---: | ---: | ---: |
| Common, no text | 110.417 -> 105.375 | 127.667 -> 123.083 | 139.750 -> 135.167 | 9,026 -> 9,379 | 11,332 -> 11,513 |
| Common, with text | 110.000 -> 108.417 | 126.709 -> 124.750 | 138.583 -> 136.250 | 9,086 -> 9,187 | 11,314 -> 11,542 |
| No match, 1 KiB | 196.458 -> 64.708 | 223.042 -> 76.083 | 235.500 -> 84.375 | 5,060 -> 15,202 | 19,353 -> 6,326 |
| One match, 64 KiB, no text | 9,357.250 -> 807.084 | 10,066.125 -> 851.125 | 10,400.708 -> 881.667 | 106 -> 1,230 | 969,427 -> 141,854 |
| One match, 64 KiB, text | 9,376.250 -> 800.584 | 10,211.792 -> 843.954 | 10,513.083 -> 881.375 | 106 -> 1,240 | 969,520 -> 141,861 |
| One match, 1 MiB, no text | 181,045.459 -> 12,722.834 | 197,871.412 -> 13,226.583 | 202,896.125 -> 13,438.875 | 5.4 -> 78.4 | 15,518,642 -> 2,250,807 |
| Long URL, with text | 66,225.806 -> 1,541.583 | 72,285.004 -> 1,601.834 | 73,460.417 -> 1,629.417 | 14.8 -> 645.5 | 5,864,643 -> 804,635 |
| Batch 8 | 837.089 -> 799.708 | 892.213 -> 852.417 | 927.625 -> 895.917 | 1,186 -> 1,241 | 85,231 -> 86,426 |
| Batch 32 | 3,224.267 -> 3,158.208 | 3,347.142 -> 3,254.708 | 3,431.667 -> 3,332.375 | 310.5 -> 316.6 | 337,275 -> 342,035 |
| Detect plus redact | 118.834 -> 108.416 | 136.876 -> 121.750 | 147.292 -> 133.625 | 8,352 -> 9,147 | 12,781 -> 12,954 |
| Structured redact | 469.877 -> 457.291 | 496.295 -> 485.500 | 524.625 -> 509.625 | 2,119 -> 2,171 | 53,490 -> 54,311 |

The `1.4%` to `2.0%` reduction increases on short, batch, anonymization, and
structured paths come from centralized ownership handling. They are accepted
for the binary-retention guarantee. Paired latency and throughput did not
regress. Large-input reduction cost fell by `67.3%` to `86.3%`.

The review expanded the harness from `11` to `45` cases. It now includes batch
sizes `1`, `8`, `32`, and `128`; every operator; Logger and Plug paths; each
built-in entity; four input scales; match positions; multibyte and malformed
input; dense and overlapping matches; and disabled and parser-backed phone
modes. Every case completed with its expected output or controlled error.

Two alternating seven-repetition runs compared the review correction with its
immediate parent using the original 11 cases. Depending on run order, p50,
p95, and throughput moved in both directions. In the adverse ordering, the
largest movements were `+1.76%` p50, `+2.20%` p95, and `-1.78%` throughput;
reductions remained within `0.12%`. These are treated as run-to-run noise, not a
performance regression. The large gains against clean `main` remain intact.

## Operational Matrix

The final values below are medians across three clean runs. Each run contains
two repetitions. Latency is milliseconds.

### Generated Large Template Heldout

| Concurrency | p50 baseline -> final | p95 baseline -> final | p99 baseline -> final | Throughput baseline -> final |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 0.1245 -> 0.1135 | 0.2055 -> 0.2000 | 0.2670 -> 0.2730 | 7,235 -> 7,716 |
| 2 | 0.1350 -> 0.1285 | 0.2105 -> 0.2145 | 0.2660 -> 0.2805 | 13,377 -> 13,796 |
| 4 | 0.1520 -> 0.1450 | 0.2420 -> 0.2500 | 0.2970 -> 0.3155 | 23,237 -> 23,635 |
| 8 | 0.2050 -> 0.1820 | 0.3050 -> 0.2855 | 0.3950 -> 0.3845 | 33,744 -> 37,917 |
| 16 | 0.2510 -> 0.2370 | 0.3790 -> 0.3735 | 0.4685 -> 0.4720 | 51,033 -> 54,340 |

Generated-large p50 and throughput improved at every concurrency. Some p95 and
p99 rows moved upward by low absolute values. Repeated runs and the immediate
paired microbenchmark show this is tail noise around sub-millisecond requests,
not a broad latency regression. This report does not claim a generated-large
p99 improvement.

### Synth Dataset V2

| Concurrency | p50 baseline -> final | p95 baseline -> final | p99 baseline -> final | Throughput baseline -> final |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 0.1260 -> 0.1140 | 0.2025 -> 0.1690 | 0.2500 -> 0.2290 | 7,174 -> 7,999 |
| 2 | 0.1395 -> 0.1270 | 0.2260 -> 0.1965 | 0.2695 -> 0.2555 | 12,764 -> 14,000 |
| 4 | 0.1520 -> 0.1430 | 0.2470 -> 0.2210 | 0.3000 -> 0.2810 | 22,996 -> 24,618 |
| 8 | 0.1870 -> 0.1825 | 0.2825 -> 0.2635 | 0.3400 -> 0.3175 | 36,759 -> 38,127 |
| 16 | 0.2600 -> 0.2330 | 0.3810 -> 0.3375 | 0.4840 -> 0.4145 | 51,098 -> 57,036 |

### Nemotron PII Test Subset

| Concurrency | p50 baseline -> final | p95 baseline -> final | p99 baseline -> final | Throughput baseline -> final |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 0.3855 -> 0.3360 | 0.9390 -> 0.8520 | 1.2050 -> 1.1480 | 2,182 -> 2,502 |
| 2 | 0.3975 -> 0.3445 | 0.9520 -> 0.8460 | 1.2140 -> 1.1535 | 4,256 -> 4,902 |
| 4 | 0.4100 -> 0.3615 | 0.9635 -> 0.8650 | 1.2655 -> 1.1975 | 8,230 -> 9,404 |
| 8 | 0.4745 -> 0.4205 | 0.9675 -> 0.9165 | 1.2940 -> 1.2445 | 14,188 -> 15,867 |
| 16 | 0.5890 -> 0.5125 | 1.2650 -> 1.0815 | 1.7080 -> 1.4485 | 21,633 -> 25,021 |

The shared sustained workload improved from `18,531` to a median `20,121`
requests per second, an `8.6%` gain. Median latency drift was `1.0000`. Every
run had zero failures, rejections, and timeouts; exactly one runtime was built;
and crash recovery, overload, timeout, and privacy probes passed.

Warm BEAM peaks remained within noise. Median final RSS peaks were below the
baseline on all three datasets, but RSS is allocator evidence and is not used
as proof of object ownership.

## Accuracy And Fingerprints

The requested entity set was identical:

```text
credit_card,email,ip_address,location,person,phone,url,us_ssn
```

| Dataset | Precision | Recall | F1 | F2 | TP | FP | FN | Offset mismatch | Wrong type | Unsupported |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Generated heldout | 0.9618 | 0.5101 | 0.6667 | 0.5630 | 503 | 20 | 483 | 34 | 0 | 964 |
| Synth v2 | 0.9349 | 0.4844 | 0.6382 | 0.5361 | 747 | 52 | 795 | 33 | 0 | 1,288 |
| Nemotron subset | 0.8037 | 0.2729 | 0.4074 | 0.3144 | 438 | 107 | 1,167 | 101 | 19 | 2,361 |

Every value matches the promoted baseline exactly. Canonically sorted
per-entity hashes also match:

| Dataset | Baseline and final per-entity SHA-256 |
| --- | --- |
| Generated heldout | `ec829cd8781d9721f3578658c683169d9d1ad0f9c6bf7bf4e324ed2e59b9b461` |
| Synth v2 | `b1b017729c7a79a4d856c996ddac539a116b6a8d85246936e63643124dc49305` |
| Nemotron subset | `887ecf1e9104c97b00c7094df00d33d8bb491747af4fec93b7555627559fca1e` |

Operational output fingerprints were stable across all repetitions and match
the baseline:

- generated heldout:
  `cd3d55fdf4329ab434c67e1f8c1a5a8e1b742fa9f1d22ad235872c9ab9f4651f`;
- synth v2:
  `e3642c2d1028ae347c6b3f0b04b9721f36ed201aee2fa5f4ee368564895a172b`;
- Nemotron subset:
  `8f0b7a1746f12f274efbc17b129698fcbd8655e7270ea9be8d4ae8561da0a803`.

This is exact output equivalence, not an accuracy improvement.

## Binary Ownership Evidence

| Probe | Baseline referenced amplification | Final |
| --- | ---: | ---: |
| Short email with text | 5,461x | 1.0x |
| Long URL with text | 744.879x | 1.0x |
| Long URL batch result | 744.879x | 1.0x |
| Custom borrowed text | 258.732x | 1.0x |
| Deny-list text | 619.195x | 1.0x |
| Built-in, no text | no escaping text | no escaping text |
| Custom, no text | no escaping text | no escaping text |
| Allow-list rejected | no result | no result |

The exact amplification depends on source size, but the final invariant is
stable: escaping text references only its own bytes. Offset-only built-in
results carry no match-text binary.

The review harness retains and recursively inspects the complete returned term,
including map keys and values, structs, lists, and tuples. Its `25` cases cover:

- analyzer results with explanations and metadata;
- analyzer batches, allow/deny filtering, context rejection, overlap handling,
  score rejection, telemetry, and many accepted matches;
- anonymizer results and operator items;
- structured results and items;
- Logger and full Plug connection results;
- custom borrowed and offset-only results;
- sanitized recognizer error, exception, throw, exit, and timeout paths.

All `25` cases reported zero borrowed binaries anywhere in their returned
object graph. Every holder process terminated normally after release and
became unreachable through `Process.info/2`. The in-memory vault was checked
separately: it retained the exact independently owned value and did not retain
its larger source binary.

## Long-Duration Evidence

### Canonical ten-minute soak

The concurrency-4 canonical soak completed `11,529,716` requests at
`19,216` requests per second:

- failures, rejections, timeouts, and output mismatches: `0`;
- p50 / p95 / p99: `0.15 / 0.49 / 0.89 ms`;
- first-window throughput: `19,379 req/s`;
- final full-window throughput: `19,170 req/s`;
- BEAM binary trend: `plateau`;
- post-idle/GC binary memory: `5.37 MB`;
- runtime builds: `1`.

The generic classifier reports `inconclusive` because Emily active/cache
metrics are unavailable for the BEAM-only profile. That classification is kept
as produced rather than rewritten.

### Targeted thirty-minute soaks

| Concurrency | Completed | Controlled failures | Unexpected failures | Held/released | Overall req/s | First/final-half req/s | Final-half binary slope | Post-GC binary delta | Classification |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 271,133 | 54,226 | 0 | 54,226 / 54,226 | 150.63 | 150.70 / 150.56 | -10 B/min | -1.50 MiB | `stable_plateau` |
| 4 | 1,029,665 | 205,933 | 0 | 205,933 / 205,933 | 572.04 | 572.22 / 571.87 | 201.3 KiB/min | -3.00 MiB | `stable_plateau` |

The workload alternated unique large no-match inputs, large inputs with one
tiny match, many rejected candidates, offset-only results, bounded-held owned
text, structured large binary leaves, and controlled callback failure.

Both holder processes had zero held results, zero binary bytes, and empty
mailboxes after release and GC. Input values were not written to the reports.

This establishes bounded finite-run binary-retention evidence for the tested
workload. It does not establish cryptographic zeroization or a universal RSS
bound.

### Review-correction five-minute soak

The final review correction completed `169,560` operations at concurrency `4`
with zero unexpected failures. It exercised `33,912` controlled failure and
holder-release cycles:

- first/final-half throughput: `567.62 / 562.69 req/s`;
- final-half binary slope: `-254 B/min`;
- post-GC binary delta: `-3.00 MiB`;
- post-idle holder results, binary bytes, and mailbox messages: `0`;
- RSS changed from `127.48 MiB` to `107.39 MiB`.

The finite run remained on a stable plateau. RSS is reported as observational
allocator evidence, not as proof of live-object ownership.

## Experiments

| Experiment | Hypothesis | Result | Speed effect | Allocation/reduction effect | Retention effect | Decision | Commit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Central final text ownership | Copy only escaping final sub-binaries | All ownership tests passed | Within noise on short paths | Small accepted short-path overhead | Amplification reduced to 1.0x | Accepted | `11461fbd` |
| Defer dependency-light artifacts | Avoid full-input token/lemma work when unused | Exact accuracy and output fingerprints | 67% to 98% lower p50 on scaling cases | 67% to 86% fewer reductions on scaling cases | No regression | Accepted | `cde7ee2c` |
| Reverse recognizer accumulation | Avoid repeated list append | Common latency worsened 4% to 6% | Regression | Reductions rose about 0.3% to 0.5% | Unchanged | Rejected | none |
| Cache recognizer option keywords | Avoid repeated struct conversion | Effects stayed below 1%; tails moved both ways | Inconclusive | About 0.1% fewer reductions | Unchanged | Rejected | none |
| Trivial conflict fast paths | Skip conflict passes for zero/one result | Reduced no-match reductions 3.5%, but paired wall-time gate did not pass | Inconclusive/regressing pair | Small isolated gain | Unchanged | Rejected | none |
| Review corrections | Preserve nullable custom text, inspect full returned graphs, correct diagnostics, avoid four temporary slices, and contain callback throws/exits | `25/25` graph probes and full CI passed | Alternating A/B stayed within noise | Reductions within `0.12%` | Zero borrowed returned-graph binaries; stable five-minute soak | Accepted | `11bcd664` |

Rejected implementation changes were reverted. Their ignored local reports
remain available during branch review but are not promoted as authoritative
artifacts.

## Validation

All required gates passed:

```text
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
mix ci.base
```

The final test result was `742 passed`, including `10` property tests, with
`14` optional/model tests excluded by their normal tags. Strict Credo,
Dialyzer, ExDNA, ExSlop, Credence, local Markdown verification, ExDoc
generation, and every promoted manifest verification passed.

## Remaining Risks

- `include_text: true` intentionally returns sensitive text. Independent
  ownership prevents unrelated parent retention but does not make the result
  non-sensitive.
- `include_text: false` avoids direct match-text materialization in built-in
  result construction, but validators may borrow temporary source slices.
  Those values do not escape the call.
- A malicious or stateful custom callback can retain its input independently
  of Obscura's final result normalization, including through caller-controlled
  metadata or external state. The complete-graph harness proves only the
  controlled extension outputs it constructs.
- BEAM and native allocators may retain freed pages. RSS is not a live-object
  inventory.
- Secure memory erasure is not guaranteed.
- The generated-large operational p99 rows remain noisy at very low absolute
  latency. No p99 gain is claimed for that dataset.

## Usage Guidance

Use `include_text: false` when downstream code needs only entities, offsets,
scores, or anonymization spans. This minimizes escaping sensitive data and
avoids match-text materialization in built-in recognizers.

Use `include_text: true` only when the caller needs the exact detected value.
Final text is independently owned when necessary, so retaining a small result
does not keep an unrelated large input alive. The caller must still treat that
text as raw PII and control its lifetime, logging, inspection, and storage.

## Next Opportunity

The next measured opportunity is reducing the small `1.4%` to `2.0%`
short-path reduction overhead from centralized ownership without weakening
custom-recognizer normalization. Any attempt should keep final ownership
central and must beat the existing run-to-run noise. Broad regex fusion,
unconditional copying, and semantic policy changes remain out of scope.
