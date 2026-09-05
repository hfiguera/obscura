# Efficient release validation protocol

Frozen before the first release-candidate measurements, 2026-09-05.

## Workload gate

Run the public `:efficient` runtime with 1, 2, 3, and 4 native workers and the
same number of continuously active callers. Warm up for ten seconds, then
measure each configuration for at least 300 seconds. Use a deterministic mix
of short support records (80%), medium documents (18%), and long documents
(2%, 250 sentences), including Unicode names and structured identifiers.
This exercises sustained traffic, not a production trace or an hours-long leak test.

Record throughput, latency histograms (0.1 ms resolution), current native RSS
and BEAM RSS every ten seconds. Summed process RSS double-counts shared pages;
it is a conservative process-memory measure, not unique physical consumption.
Report memory growth after the first third of the run separately from loading.
The gate requires zero unexpected errors/restarts during normal traffic,
native growth no greater than 32 MiB per worker and BEAM growth no greater than
64 MiB after that first third. These are engineering regression budgets, not
proof of absence of a leak. No universal throughput SLO is asserted.

After traffic, explicitly hold every worker reservation to test saturation,
verify no input queue, release callers, kill an actual native process and
verify recovery. Reject oversized/invalid UTF-8 input and token overflow,
then successfully analyze another request. A stopped runtime must fail closed.
Portable compatibility tests separately exercise timeouts and malformed IPC.

Required environments: Apple Silicon macOS, native Linux ARM64, and physical
Linux x86-64. A container running natively on bare-metal x86-64 qualifies for
the CPU measurement; Docker Desktop x86-64 emulation does not. Record the
host CPU, OS, virtualization detection and container recipe separately.

## Accuracy gate

Use the previously unused `gretelai/gretel-pii-masking-en-v1` dataset revision
`e06eb1499ca8d54470f085021cd8e54f9efac7fd` (Apache-2.0, synthetic English
application-like documents). Freeze file hashes, label mapping and disjoint
selection manifests before obtaining model predictions. Use the publisher's
validation split for development and test split for the final evaluation.
Deduplicate normalized text across splits. Never tune on final test outputs.

Report exact typed spans, precision, recall, F1, false positives and missed
gold spans, per entity and overall. Also report partial overlaps separately;
an overlap must not silently count as an exact match. Map supported labels
explicitly and report unsupported labels and invalid/missing annotations.
Compare `:fast`, the unmodified native spaCy profile, the final `:efficient`
policy, and the pinned Presidio reference on identical text and gold spans.
Choose boundary rules only from development errors; retain a rule only if
development exact F1 improves without reducing person/location recall by more
than 0.5 percentage points. The final policy must improve on `:fast` for
person/location recall and must not regress overall exact F1 from the frozen
native baseline by more than 0.5 percentage points. Publish failures too.

Synthetic labels are not an independent human audit and may omit real spans.
App-specific real-world accuracy and an exhaustive PII taxonomy remain outside
this release evidence. The profile must document these limits.
