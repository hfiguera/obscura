# spaCy hybrid benchmark results

Branch: `benchmark-spacy-hybrid`. Base commit: `3bc74140801b83bc2a66882b2dbdf208796be771`.

Exploratory results; no native implementation or stable-profile change is included.

## Shared benchmark F1

These use the existing evaluator's historical ratios. See strict-span results below.

| Dataset | Samples | Fast | Presidio | Hybrid full | Hybrid NER-only | Balanced¹ | Accurate¹ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| generated_large | 648 | 0.6684 | 0.6809 | 0.7838 | 0.7838 | 0.7878 | 0.8024 |
| synth_dataset_v2 | 1500 | 0.6382 | 0.7211 | 0.7910 | 0.7907 | 0.8388 | 0.8423 |
| nemotron_pii_test_subset | 500 | 0.4074 | 0.6254 | 0.6940 | 0.6938 | 0.6954 | 0.6973 |

¹ Existing hash-verified authoritative GPU runs, used for accuracy comparison only.

Fast above uses normal production conflict resolution. An additional `fast_reference` control disables conflicts, matching the historical fixture adapter; its counts exactly reproduce the authoritative baseline. The production default removes four additional false positives on generated heldout (F1 0.6684 versus 0.6667); the other datasets are unchanged.

## Conventional strict-span F1

Boundary errors and wrong types count as both false positives and false negatives.

| Dataset | Fast | Presidio | Hybrid full | Hybrid NER-only | Balanced | Accurate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| generated_large | 0.6395 | 0.6162 | 0.7190 | 0.7190 | 0.7388 | 0.7531 |
| synth_dataset_v2 | 0.6207 | 0.6570 | 0.7316 | 0.7315 | 0.7992 | 0.8024 |
| nemotron_pii_test_subset | 0.3665 | 0.4927 | 0.5404 | 0.5403 | 0.5659 | 0.5676 |

## Primary hybrid precision and recall

| Dataset | Shared precision | Shared recall | Shared F2 | Strict precision | Strict recall | Boundary errors | Wrong types |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| generated_large | 0.7500 | 0.8208 | 0.8056 | 0.6904 | 0.7500 | 70 | 18 |
| synth_dataset_v2 | 0.7415 | 0.8475 | 0.8239 | 0.6891 | 0.7797 | 87 | 39 |
| nemotron_pii_test_subset | 0.7752 | 0.6283 | 0.6530 | 0.5884 | 0.4997 | 323 | 30 |

## CPU component cost

Mean milliseconds, averaged over two repetitions. Hybrid values add Python processing and actual Obscura analysis; IPC, serialization, disk reads, startup and loading are excluded. These are not native or production latency measurements.

| Dataset | Fast | Presidio | Hybrid full | Hybrid NER-only | Full hybrid Obscura portion |
| --- | ---: | ---: | ---: | ---: | ---: |
| generated_large | 0.0986 | 3.7805 | 3.5300 | 1.6555 | 0.1192 |
| synth_dataset_v2 | 0.0953 | 3.9623 | 3.8211 | 1.7596 | 0.1174 |
| nemotron_pii_test_subset | 0.3225 | 26.0420 | 25.3117 | 11.6392 | 0.7537 |

## Person and location results

Shared per-entity F1 (boundary errors reported separately by this evaluator).

| Dataset | Entity | Fast | Presidio | Hybrid full | Balanced | Accurate |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| generated_large | person | 0.5906 | 0.7712 | 0.7894 | 0.9211 | 0.9211 |
| generated_large | location | 0.7264 | 0.4071 | 0.7442 | 0.6341 | 0.6754 |
| synth_dataset_v2 | person | 0.5862 | 0.7795 | 0.8204 | 0.9506 | 0.9512 |
| synth_dataset_v2 | location | 0.5552 | 0.4554 | 0.6394 | 0.6267 | 0.6445 |
| nemotron_pii_test_subset | person | 0.0210 | 0.4799 | 0.4675 | 0.5531 | 0.5538 |
| nemotron_pii_test_subset | location | 0.0049 | 0.7165 | 0.7268 | 0.6817 | 0.6881 |

## Integrity checks

| Dataset | Reference controls match | Changed structured outputs (full / NER-only) | Full vs NER-only changed documents |
| --- | --- | ---: | ---: |
| generated_large | Yes | 0 / 0 | 0 |
| synth_dataset_v2 | Yes | 0 / 0 | 7 |
| nemotron_pii_test_subset | Yes | 0 / 0 | 1 |

All five measured profiles reproduced accuracy and prediction fingerprints in both repetitions. Dataset bytes, ordered sample IDs, entity policy, UTF-8 offsets, model hashes, and reference report hashes were checked. See `comparison.json` for counts, per-entity metrics, IoU, repetition timings, fingerprints, and environment evidence.

## Reproduce

```sh
.presidio-authoritative-venv/bin/python eval/spacy_hybrid/benchmark.py
.presidio-authoritative-venv/bin/python eval/spacy_hybrid/report.py --results PATH_TO_RESULTS_JSON --out-dir PATH_TO_REVIEW_REPORT
```

The datasets are synthetic and the shared taxonomy excludes organizations, dates, and other PII categories. The NER-only result is diagnostic; selecting it for a product would require validation on untouched deployment-representative data.
