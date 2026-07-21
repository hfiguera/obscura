# Presidio-Research Benchmark Snapshots

This directory contains pinned evaluation-only snapshots from
[data-privacy-stack/presidio-research](https://github.com/data-privacy-stack/presidio-research).
They make Obscura's dependency-light smoke and compatibility evaluations
reproducible from a fresh clone without Python or network access.

## Provenance

- Upstream repository: `https://github.com/data-privacy-stack/presidio-research.git`
- Snapshot revision: `2e9741154a3857712307b776cc2cd5f13c95c34b`
- Snapshot date: `2026-06-30`

| File | Upstream path | SHA-256 |
| --- | --- | --- |
| `synth_dataset_v2.json` | `data/synth_dataset_v2.json` | `ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012` |
| `generated_small.json` | `tests/data/generated_small.json` | `b40cfe75e5f0799b1c8054d91cbaafd92a7a34b425c1416cdf70ad5ff961fb5d` |
| `generated_large.json` | `tests/data/generated_large.json` | `b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26` |
| `mock_input_samples.json` | `tests/data/mock_input_samples.json` | `3b039c471ce9ec6c5372ba27108dde21af33cab88e8d9ce70bc957dbaa4e5ac6` |

`Obscura.Eval.PresidioResearchLoader` verifies the checksum when it loads one
of these default snapshots. Changes require an explicit provenance update and
fresh benchmark evidence; do not silently regenerate or normalize these files.

## Distribution

These files are development and evaluation assets. They are not runtime assets
and are not included in the published Hex package.

See `NOTICE.md` and `LICENSE-PRESIDIO-RESEARCH` for attribution and applicable
upstream terms.
