# SDK diagnosis, before accuracy evaluation

These are constructed English probes. They are separate from the development
and test corpus and establish behavior, not an accuracy ranking.

## Confirmed results

The packaged native SDK 3.1.0 ran 42 calls per configuration: 21 cases at the
default confidence 0.6, followed by the same cases at confidence 0. Of the 21
default-confidence calls, complete detection of both name components failed in:

| Configuration | Calls missing at least one name component |
| --- | ---: |
| macOS, SDK default Core ML settings | 13 / 21 |
| macOS, official `DAL_COREML_COMPUTE_UNITS=cpu` setting | 21 / 21 |
| Physical Linux x86-64, LiteRT/XNNPACK CPU | 12 / 21 |

All calls returned consistent UTF-16 spans and could restore their own redacted
input. None of those properties establishes complete detection.

The native Linux log registered the CPU accelerator and XNNPACK delegate. No GPU
accelerator library loaded. The Apple default permits acceleration and is not
classified as CPU evidence.

## Source-level observation

The published npm 3.1.0 Redact and core packages identify release commit
`9e11fdf9566df2e34b9516ac76403b1ff0f839d8`. The initial source diagnostic used
`c015d5d95028caba783e802442e30ddd66c9247e`, 43 commits later. All 13 Redact Swift
files plus CoreMLSession/Tensor are byte-identical, but shared runtime files have
changes. [sdk-provenance.json](sdk-provenance.json) records that distinction and
the reviewed changes. Accuracy and workload measurements use the published npm
binaries throughout. After timing completed, `release_diagnostics.py` rebuilt the
observer at the actual release commit on both hosts. All six rows and eight
windows per configuration are identical to the initial observations, including
labels, histograms, finite/nonfinite counts and reported maxima. The release
replay therefore confirms the findings below without substituting a newer SDK.
Reports and source identities are retained in `results/release/`.

`swift_probe` builds that pinned official source snapshot and wraps its usage-tracked inference
session with an observer. It does not modify input/output tensors, thresholds,
postprocessing, or telemetry. Six cases were run per configuration. This avoids
the Node/C ABI layer while retaining the SDK pipeline.

- **Mac CPU:** all 22,784 output values in each observed window were nonfinite.
  The SDK nevertheless returned deterministic email detections without reporting
  an inference error. This is an invalid neural result, not a fast successful NER
  run. An additional observer in a copy of `CoreMLSession.swift` reads the native
  `MLMultiArray` using multidimensional indexing before SDK tensor conversion.
  All eight native arrays also contain 22,784 nonfinite values, and the loaded
  model configuration reports `.cpuOnly`. This excludes the SDK's tensor-buffer
  conversion as the origin in these probes. The failing Core ML export/runtime
  operation is not isolated. The original SDK source tree remains unchanged.
- **Mac default and Linux CPU:** outputs were finite. The 10-, 21-, and 43-token
  windows identified the example name and city. The 65- and 120-token windows
  predicted `O` for every real token. A longer input did run three overlapping
  windows, which also predicted `O` throughout. These are failures on repetitive
  constructed passages, not proof that all text above a given length fails.
- Captured SDK input tensors matched the publisher's canonical Hugging Face
  tokenizer in **all eight compared windows**, including input IDs, attention
  masks, positions, and type IDs. Token IDs remain in an ignored local cache;
  the saved report records only equality counts.

These observations rule out Node span decoding, confidence threshold selection,
and missing window iteration as explanations for these specific misses. They
support a model-response limitation for the repetitive passages and a separate
numerical failure in the Apple CPU execution path. They do not identify a
training defect or the precise failing Core ML operation.

Lowering confidence was ineffective.

## Separate sentence segmentation experiment

`segment_probe.mjs` compares the default full-input pipeline with calls on each
English sentence using `Intl.Segmenter`. It checks translated offsets against the
original input. Four passages contain 0, 5, 20 or 150 neutral repeated sentences
before the same name/city/email sentence (58 to 7,558 UTF-8 bytes).

On Linux CPU and Mac default, the full-input call finds the name and city only in
the shortest passage; segmented calls find both in all four. Mac CPU finds neither
with either method. Segmentation therefore mitigates these repetitive-context
misses on the functioning backends, but does not repair the numerical failure.

This is a diagnostic result only. Sentence splitting can remove useful context,
break multiline addresses and increase invocation cost. It was not tuned or
evaluated on the frozen test set, and is excluded from all stock accuracy and
workload results. No production workaround is claimed.

## Evidence

- `results/probe-macos-default.json`
- `results/probe-macos-cpu.json`
- `results/probe-linux-default.json`
- `results/tensors-macos-default.json`
- `results/tensors-macos-cpu.json`
- `results/tensors-linux-default.json`
- `results/tokenizer-parity.json`
- `results/coreml-array-observation.json`
- `results/segmentation-macos-default.json`, `results/segmentation-macos-cpu.json`
- `results/linux/segmentation-linux-cpu.json`
- `model-manifest.json`, `diagnostic-manifest.json`, npm and Swift lockfiles.

See [ACCURACY.md](ACCURACY.md) for the completed independent synthetic comparison.
See [WORKLOAD_RESULTS.md](WORKLOAD_RESULTS.md) for the complete operational matrix
and [REPORT.md](REPORT.md) for the recommendation.
