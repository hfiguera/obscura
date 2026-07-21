# Authoritative Presidio External Baseline

- Run ID: presidio_authoritative_generated_large_r1
- Dataset: generated_large
- Samples: 648
- Protocol: presidio_obscura_common_v1
- Sample ID fingerprint: `abd254573ceacfd0a8472a48633db7a98e134c1be9e1c9301dda4e22ee372018`
- Entity policy fingerprint: `b2e8b8b3263f50cb187319ebb90532df2b154ec536558326029556921e6a2405`
- Scoring fingerprint: `5cfd212921e345a7410c68dec31fbc6355ed7bc7b4a4221caa495c51c6b0ffaf`

## Accuracy

| Metric | Value |
| --- | ---: |
| Precision | 0.7338 |
| Recall | 0.6351 |
| F1 | 0.6809 |
| F2 | 0.6527 |
| True positives | 590 |
| False positives | 214 |
| False negatives | 339 |
| Wrong entity type | 48 |
| Offset mismatches | 43 |
| Unsupported expected spans | 964 |
| IoU F1 | 0.6445 |

## Latency

| Metric | Value |
| --- | ---: |
| Mean | 3.4169ms |
| Median | 3.2025ms |
| P95 | 6.2047ms |
| Throughput | 292.6647 samples/s |

## Limitations

- Real Presidio AnalyzerEngine run using local spaCy en_core_web_lg.
- Python metrics are diagnostic only; authoritative metrics are recomputed by Obscura.Eval.Metrics.
- Unsupported gold entities are counted separately from false negatives.
- Raw text and detected values are omitted from reports and from the local JSONL prediction export.
- Presidio runs on CPU. Latency is not directly comparable to Obscura GPU profiles.
