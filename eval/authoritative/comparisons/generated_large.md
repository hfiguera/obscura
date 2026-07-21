# Presidio vs Obscura Comparison Report

- Run ID: authoritative_presidio_vs_obscura_generated_large
- Same sample IDs: true
- Same protocol fingerprints: true

## Sample Identity

- presidio_spacy: 648 ordered IDs; SHA-256 `abd254573ceacfd0a8472a48633db7a98e134c1be9e1c9301dda4e22ee372018`
- obscura_fast: 648 ordered IDs; SHA-256 `abd254573ceacfd0a8472a48633db7a98e134c1be9e1c9301dda4e22ee372018`
- obscura_balanced: 648 ordered IDs; SHA-256 `abd254573ceacfd0a8472a48633db7a98e134c1be9e1c9301dda4e22ee372018`
- obscura_accurate: 648 ordered IDs; SHA-256 `abd254573ceacfd0a8472a48633db7a98e134c1be9e1c9301dda4e22ee372018`
- obscura_openmed_pii: 648 ordered IDs; SHA-256 `abd254573ceacfd0a8472a48633db7a98e134c1be9e1c9301dda4e22ee372018`

## Metrics

| Entry | Profile | Scope | Split | Precision | Recall | F1 | F2 | IoU F1 | TP | FP | FN | Offset mismatches | Wrong type | Unsupported |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| presidio_spacy | presidio_spacy_en_core_web_lg | n/a | template_heldout | 0.7338 | 0.6351 | 0.6809 | 0.6527 | 0.6445 | 590 | 214 | 339 | 43 | 48 | 964 |
| obscura_fast | deterministic_plus | template_heldout_full | template_heldout | 0.9618 | 0.5101 | 0.6667 | 0.5630 | 0.6379 | 503 | 20 | 483 | 34 | 0 | 964 |
| obscura_balanced | hybrid_ner_tner_conservative | template_heldout_full | template_heldout | 0.8237 | 0.7550 | 0.7878 | 0.7678 | 0.7421 | 724 | 155 | 235 | 58 | 3 | 964 |
| obscura_accurate | hybrid_ner_tner_jean_location | template_heldout_full | template_heldout | 0.8069 | 0.7526 | 0.7788 | 0.7629 | 0.7395 | 727 | 174 | 239 | 50 | 4 | 964 |
| obscura_openmed_pii | privacy_filter_native | template_heldout_full | template_heldout | 0.3341 | 0.7826 | 0.4683 | 0.6170 | 0.4044 | 594 | 1184 | 165 | 203 | 58 | 964 |

## Latency

| Entry | Mean | Median | P95 | Throughput | Runs | Comparison |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| presidio_spacy | 3.4169ms | 3.2025ms | 6.2047ms | 292.6647 samples/s | 2 | comparable: same physical machine and CPU device |
| obscura_fast | 0.1338ms | 0.0710ms | 0.2970ms | 7473.4451 samples/s | 2 | comparable: same physical machine and CPU device |
| obscura_balanced | 21.4730ms | 21.0990ms | 23.6370ms | 46.5701 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |
| obscura_accurate | 44.5533ms | 44.6160ms | 48.8400ms | 22.4450 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |
| obscura_openmed_pii | 231.4819ms | 223.9180ms | 312.5250ms | 4.3200 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |

## Limitations

- All entries are loaded from generated JSON reports.
- same_samples is true only when every report declares the same dataset.sample_ids list.
- Obscura deterministic_plus uses context-limited local recognizers; it is not broad NER parity.
