# English Redact candidate evaluation

Started 2026-09-13 on `eval/redact-english`, from main `46428566`.
This is evaluation tooling only; it adds no public profile. No model training,
publication, push, or vendor contact is part of this experiment.

## Required evidence

1. Pin SDK dependencies, model/tokenizer files, source identity, inference
   configuration, platform and actual compute device. Preserve telemetry.
2. Reproduce longer-input misses on macOS and physical Linux. Compare stock
   behavior with supported CPU configuration before changing code. Any workaround
   is a separately named experiment, never silently included in stock results.
3. Freeze a fresh English development/test corpus, its annotation policy and
   hashes before final predictions. Do not tune on the test set. Cover support
   messages, logs, narrative text, ambiguous names, Unicode, full addresses,
   structured identifiers, negatives and long documents. Synthetic probes do not
   establish production generalization. Gretel is supplementary only because of
   declared Redact training-source overlap; predictions are never training data.
4. Compare the complete Redact pipeline and Obscura fast/efficient/balanced on
   identical inputs. Freeze taxonomy, person/address merging and UTF-16 to UTF-8
   conversion. Disclose unsupported labels. Report exact typed precision/recall/F1,
   per-entity counts, complete/partial PII exposure and negative-text false positives.
5. Run matched CPU workloads on Apple Silicon and SSH host `linux`, with cold
   startup, warm latency, sustained traffic, throughput, RSS/growth, saturation,
   and process failure/recovery at 1–4 workers. Record runtime and native process
   memory separately where possible, and distinguish disk assets from memory.
   Existing backend results and Docker emulation cannot substitute for this matrix.
6. Assess license, attribution, redistribution, telemetry and offline contract.
   Record unresolved vendor questions without contacting the vendor.
7. Deliver pinned, reproducible tooling and sanitized reports, with an explicit
   recommendation and limitations. No champion claim without matched evidence.

## Progress

- Created branch from main; pre-existing untracked training work preserved.
- Initial review and 37 diagnostic calls exist in ignored
  `eval/reports/desert-ant-review-2026-09-13/`.
- Physical Linux is reachable: Pop!_OS 24.04, i5-1135G7, 8 logical CPUs;
  `systemd-detect-virt` reports `none`. Do not reuse older environment metadata.
- SDK source exposes `DAL_COREML_COMPUTE_UNITS=cpu` in CoreMLSession. The initial
  review did not use it, so its macOS measurements are not CPU benchmarks.
- See DIAGNOSIS.md: cross-platform misses reproduced, Mac CPU nonfinite output
  observed, and canonical tokenizer parity verified in all eight windows.
- Isolated baseline consumers run on both hosts, with verified CPU execution.
- Frozen corpus/mapping and all 18 development/test reports are complete;
  see ACCURACY.md. Saved reports were independently recomputed and checked.
- Sentence segmentation mitigated the specific repetitive-context probes on
  Linux CPU and Mac default; it is excluded from stock comparison results.
- Installed-file measurements and source/license review are complete. All 32
  sustained runs finished and passed the workload audit. Background load is
  recorded; these are development hosts, not isolated laboratory machines.
- Release-source tensor replays reproduce the original observations on both
  hosts. Post-run model-byte integrity and Linux actual CPU backend checks pass.
- See WORKLOAD_RESULTS.md, REPORT.md and COMPLETION.md for results, the decision
  and requirement-by-requirement evidence. This frozen objective remains broader
  than any individual automated check.
