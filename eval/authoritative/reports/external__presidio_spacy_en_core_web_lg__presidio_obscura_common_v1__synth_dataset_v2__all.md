# Authoritative Presidio External Baseline

- Run ID: presidio_authoritative_synth_dataset_v2_r1
- Dataset: synth_dataset_v2
- Samples: 1500
- Protocol: presidio_obscura_common_v1
- Sample ID fingerprint: `4ae1a24321c77e5ec34560cfa25b5cecd3381f50fe4d69e5fc0ac69d0646b07c`
- Entity policy fingerprint: `b2e8b8b3263f50cb187319ebb90532df2b154ec536558326029556921e6a2405`
- Scoring fingerprint: `5cfd212921e345a7410c68dec31fbc6355ed7bc7b4a4221caa495c51c6b0ffaf`

## Accuracy

| Metric | Value |
| --- | ---: |
| Precision | 0.6993 |
| Recall | 0.7442 |
| F1 | 0.7211 |
| F2 | 0.7348 |
| True positives | 1065 |
| False positives | 458 |
| False negatives | 366 |
| Wrong entity type | 71 |
| Offset mismatches | 73 |
| Unsupported expected spans | 1288 |
| IoU F1 | 0.6874 |

## Latency

| Metric | Value |
| --- | ---: |
| Mean | 3.7588ms |
| Median | 3.1656ms |
| P95 | 7.0820ms |
| Throughput | 266.0436 samples/s |

## Limitations

- Real Presidio AnalyzerEngine run using local spaCy en_core_web_lg.
- Python metrics are diagnostic only; authoritative metrics are recomputed by Obscura.Eval.Metrics.
- Unsupported gold entities are counted separately from false negatives.
- Raw text and detected values are omitted from reports and from the local JSONL prediction export.
- Presidio runs on CPU. Latency is not directly comparable to Obscura GPU profiles.
