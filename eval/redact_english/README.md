# Redact English evaluation

**Recommendation: retain Redact as an external reference; do not integrate this
release now.** See [REPORT.md](REPORT.md) for the measured tradeoffs.

This evaluates [Redact by Desert Ant Labs](https://desertant.com/models/redact/)
as an English-only candidate for Obscura. See [PROTOCOL.md](PROTOCOL.md) for the
full objective, [DIAGNOSIS.md](DIAGNOSIS.md) for the cross-platform investigation,
[ACCURACY.md](ACCURACY.md) for the frozen test results, and
[LICENSING.md](LICENSING.md) for distribution/offline questions. Disk measurements
are in [FOOTPRINT.md](FOOTPRINT.md), and [INTEGRATION.md](INTEGRATION.md) explains
what a later Elixir adapter would require. This branch adds
evaluation tooling only. JSON reports contain no original input text or detected
values; diagnostic inputs and documented examples are synthetic.

## Current state

After measurement, `worker.exs` received a formatting-only CI fix. Its exact
measured bytes remain in `recorded_sources/worker.exs.txt`; `source-formatting.json`
records both hashes. Auditors preserve the original report hashes and verify
that Elixir formats the archived and current worker identically. These offline
checks now require Elixir as well as Python and Node. New runs record the current
worker hash normally.

Completed: branch isolation, official SDK probes on Mac and physical Linux,
supported Mac CPU configuration, observed model tensors without changing the
pipeline, canonical tokenizer parity, immutable model/configuration hashes,
sentence segmentation as a separate diagnostic, frozen English corpus/mapping,
18 accuracy reports, installed-file measurements and a source/license review.

The full operational CPU matrix is complete: four profiles, 1–4 independent
workers on both hosts, at least five minutes per configuration. See
[WORKLOAD_RESULTS.md](WORKLOAD_RESULTS.md) and [COMPLETION.md](COMPLETION.md).
Release-source diagnostics, baseline byte verification and post-run checks also
passed. Short pilots are excluded from final performance evidence.

The isolated `consumer/` project pins Nx 0.13.1, Bumblebee 0.7.1 and EXLA 0.13.1.
It does not change the main project's dependencies. The worker uses Obscura's
actual profile preparation and analyzer. Both hosts use EXLA's verified `host`
CPU client for balanced. Its compilation uses batch size 1 and sequence length
128; Obscura's own text handling remains active. Worker count means independent
processes, not a restriction on internal scheduler/BLAS threads.

## Provision and probe

From `eval/redact_english/`:

```sh
npm ci --ignore-scripts --no-audit --no-fund
python3 prepare_assets.py --directory ../../.cache/redact-evaluation/model \
  --manifest model-manifest.json
node probe.mjs results/probe-local-default.json
DAL_COREML_COMPUTE_UNITS=cpu node probe.mjs results/probe-local-cpu.json
```

`probe.mjs` currently uses the SDK-managed cache, optionally selected with
`REDACT_CACHE_ROOT`. `prepare_assets.py` independently materializes and verifies
immutable assets. The accuracy and workload runners use an explicit
`REDACT_MODEL_DIR` and verify platform assets against `model-manifest.json`
before loading. Their metadata records the native library hashes. No model
weights, SDK copies or Node dependencies are included in Git.

## Reproduce accuracy and workload measurements

Use separate output directories for a new run; scripts refuse to overwrite
existing reports. Provision all assets before timing. From `consumer/`, run
`mix deps.get` and `mix compile`. Provision efficient using
`mix obscura.efficient.install --allow-download`. Balanced's first preparation
requires `REDACT_EVAL_PREPARE=1`; a readiness call can be made with
`REDACT_EVAL_PREPARE=1 mix run --no-start ../worker.exs balanced </dev/null`.
Do not use that download flag during measured runs.

Then, from the repository root, with the verified asset directory:

```sh
export REDACT_MODEL_DIR="$PWD/.cache/redact-evaluation/model"
python3 eval/redact_english/accuracy.py --split development \
  --profiles fast efficient balanced redact_cpu --output .cache/redact-evaluation/repeat-accuracy
python3 eval/redact_english/accuracy.py --split test \
  --profiles fast efficient balanced redact_cpu --output .cache/redact-evaluation/repeat-accuracy
python3 eval/redact_english/workload.py --profiles fast efficient balanced redact_cpu \
  --workers 1 2 3 4 --seconds 300 --output .cache/redact-evaluation/repeat-workload
```

On macOS, run `redact_default` separately for an accelerated reference if desired;
it is never classified as CPU performance. Redact CPU's invalid neural output
remains visible as a failure rather than a successful speed result.

`linux_run.sh TASK_ROOT COMMAND ...` configures the evaluation's isolated Linux
runtime, native dependencies, SDK and assets, and runs from its consumer directory.
For example, `python3 ../workload.py ...` then uses the same runner and frozen data.
Keep source files and mapping/workload policy unchanged during a measured run;
the runner verifies their hashes at the end of each configuration.

Recheck saved evidence without running inference:

```sh
python3 eval/redact_english/analyze_accuracy.py
python3 eval/redact_english/analyze_workloads.py
python3 eval/redact_english/analyze_diagnostics.py
python3 eval/redact_english/audit_reports.py
python3 -m unittest discover -s eval/redact_english -p 'test_score.py'
node --test eval/redact_english/test_spans.mjs
```

`python3 eval/redact_english/verify_evidence.py` runs these checks together, checks
baseline source/asset provenance and report links, and writes a hash inventory
to `results/final-validation.json`. It needs no model inference or network.

The first command checks all 18 original accuracy reports and their provenance.
The workload analyzer requires all 32 reports unless `--allow-partial` is passed;
partial analysis explicitly fails the matrix-complete gate. The raw-content audit
only rejects raw-content fields recursively; it is not by itself a
correctness or completeness audit. Python/Node unit tests cover mapping and
scoring edge cases without native inference.

The Swift diagnostic depends on the pinned source tree under the repository's
`.cache/redact-evaluation/`, or `REDACT_SDK_SOURCE`. The source archive URL is:
https://codeload.github.com/Desert-Ant-Labs/desert-ant-core/tar.gz/c015d5d95028caba783e802442e30ddd66c9247e

That is the initial inspected source snapshot, not npm 3.1.0's release commit.
The published packages identify `9e11fdf9566df2e34b9516ac76403b1ff0f839d8`.
[sdk-provenance.json](sdk-provenance.json) records the package integrity, release
tag and source comparison. The frozen `model-manifest.json` field `sdk_source`
names the initial diagnostic snapshot; it is not used to build the benchmark
worker. `release_diagnostics.py` replayed the observer against the release source
in a separate scratch directory, preserving the original reports. Both hosts'
release observations exactly reproduce the original rows. Run diagnostic builds
after timed workloads to avoid compilation/inference contention.

```sh
swift build --package-path swift_probe -c release -j 4
DAL_COREML_COMPUTE_UNITS=cpu swift_probe/.build/release/RedactDiagnostic \
  ../../.cache/redact-evaluation/model results/tensors-local-cpu.json
```

On Linux, link with the official npm package's `native/linux-x64/libLiteRt.so`:
pass `-Xlinker -L<absolute-native-directory>` and
`-Xlinker -rpath -Xlinker <absolute-native-directory>` to `swift build`.
The observer uses the SDK's tracked session factory; telemetry is retained.

For a release-source replay from the repository root:

```sh
python3 eval/redact_english/release_diagnostics.py \
  --sdk-source .cache/redact-evaluation/desert-ant-core-9e11fdf9566df2e34b9516ac76403b1ff0f839d8 \
  --model-directory .cache/redact-evaluation/model \
  --scratch .cache/redact-evaluation/repeat-release-replay \
  --output .cache/redact-evaluation/repeat-release-results
```

Fetch that source with the codeload URL above, replacing its commit with
`9e11fdf9566df2e34b9516ac76403b1ff0f839d8`; verify its archive hash against
`sdk-provenance.json`. Linux additionally requires `--linux-native-directory`
pointing to the official installed `native/linux-x64` directory.
`verify_baseline_assets.py --help`, `audit_linux_backends.py --help` and
`postrun_audit.py --help` document the remaining host checks. Their saved results
are under `results/{macos,linux}/`.

`REDACT_DIAGNOSTIC_INPUTS` optionally captures model inputs to a local ignored
file for `tokenizer_parity.py`. Never commit or use those token IDs for training.
The Python dependencies for that diagnostic are pinned in `diagnostic-python.lock`.

## Work locations

- Mac cache: repository `.cache/redact-evaluation/`.
- Physical Linux: `/home/humberto/obscura-redact-evaluation-20260913/`.
- Linux diagnostics: `eval/`; mirrored Obscura/consumer: `source/`.
- Linux runtime downloads: `tools/`; no system packages or services changed.
- The initial review remains in ignored `eval/reports/desert-ant-review-2026-09-13/`.

The Swift 6.3.3 Linux toolchain signature was verified with the Swift release key
fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`, fetched from Swift.org.
Node 26.8.2 and Elixir 1.18.4 archives were checked against publisher SHA-256
files. `setup_linux_beam.sh` extracts pinned Ubuntu packages into the task's own
sysroot. It does not use sudo or overwrite the user's Erlang installations.
