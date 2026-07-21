# Authoritative Presidio External Baseline

- Run ID: presidio_authoritative_nemotron_pii_test_subset_r1
- Dataset: nemotron_pii_test_subset
- Samples: 500
- Protocol: presidio_obscura_common_v1
- Sample ID fingerprint: `14206c51fbdafb0c28331bd07e74a26a6beede594c3edf4246163df32844972c`
- Entity policy fingerprint: `b2e8b8b3263f50cb187319ebb90532df2b154ec536558326029556921e6a2405`
- Scoring fingerprint: `5cfd212921e345a7410c68dec31fbc6355ed7bc7b4a4221caa495c51c6b0ffaf`

## Accuracy

| Metric | Value |
| --- | ---: |
| Precision | 0.5970 |
| Recall | 0.6565 |
| F1 | 0.6254 |
| F2 | 0.6437 |
| True positives | 883 |
| False positives | 596 |
| False negatives | 462 |
| Wrong entity type | 51 |
| Offset mismatches | 329 |
| Unsupported expected spans | 2361 |
| IoU F1 | 0.5402 |

## Latency

| Metric | Value |
| --- | ---: |
| Mean | 24.4653ms |
| Median | 20.7062ms |
| P95 | 57.9023ms |
| Throughput | 40.8742 samples/s |

## Limitations

- Real Presidio AnalyzerEngine run using local spaCy en_core_web_lg.
- Python metrics are diagnostic only; authoritative metrics are recomputed by Obscura.Eval.Metrics.
- Unsupported gold entities are counted separately from false negatives.
- Raw text and detected values are omitted from reports and from the local JSONL prediction export.
- Presidio runs on CPU. Latency is not directly comparable to Obscura GPU profiles.
