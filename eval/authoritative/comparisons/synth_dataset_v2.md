# Presidio vs Obscura Comparison Report

- Run ID: authoritative_presidio_vs_obscura_synth_dataset_v2
- Same sample IDs: true
- Same protocol fingerprints: true

## Sample Identity

- presidio_spacy: 1500 ordered IDs; SHA-256 `4ae1a24321c77e5ec34560cfa25b5cecd3381f50fe4d69e5fc0ac69d0646b07c`
- obscura_fast: 1500 ordered IDs; SHA-256 `4ae1a24321c77e5ec34560cfa25b5cecd3381f50fe4d69e5fc0ac69d0646b07c`
- obscura_balanced: 1500 ordered IDs; SHA-256 `4ae1a24321c77e5ec34560cfa25b5cecd3381f50fe4d69e5fc0ac69d0646b07c`
- obscura_accurate: 1500 ordered IDs; SHA-256 `4ae1a24321c77e5ec34560cfa25b5cecd3381f50fe4d69e5fc0ac69d0646b07c`
- obscura_openmed_pii: 1500 ordered IDs; SHA-256 `4ae1a24321c77e5ec34560cfa25b5cecd3381f50fe4d69e5fc0ac69d0646b07c`

## Metrics

| Entry | Profile | Scope | Split | Precision | Recall | F1 | F2 | IoU F1 | TP | FP | FN | Offset mismatches | Wrong type | Unsupported |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| presidio_spacy | presidio_spacy_en_core_web_lg | n/a | all | 0.6993 | 0.7442 | 0.7211 | 0.7348 | 0.6874 | 1065 | 458 | 366 | 73 | 71 | 1288 |
| obscura_fast | deterministic_plus | full | all | 0.9349 | 0.4844 | 0.6382 | 0.5361 | 0.6207 | 747 | 52 | 795 | 33 | 0 | 1288 |
| obscura_balanced | hybrid_ner_tner_conservative | full | all | 0.8297 | 0.8480 | 0.8388 | 0.8443 | 0.8018 | 1272 | 261 | 228 | 75 | 0 | 1288 |
| obscura_accurate | hybrid_ner_tner_jean_location | full | all | 0.7338 | 0.8527 | 0.7888 | 0.8259 | 0.7572 | 1279 | 464 | 221 | 62 | 13 | 1288 |
| obscura_openmed_pii | privacy_filter_native | full | all | 0.3306 | 0.7920 | 0.4665 | 0.6192 | 0.3909 | 891 | 1804 | 234 | 362 | 88 | 1288 |

## Latency

| Entry | Mean | Median | P95 | Throughput | Runs | Comparison |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| presidio_spacy | 3.7588ms | 3.1656ms | 7.0820ms | 266.0436 samples/s | 2 | comparable: same physical machine and CPU device |
| obscura_fast | 0.1208ms | 0.0690ms | 0.3960ms | 8276.9581 samples/s | 2 | comparable: same physical machine and CPU device |
| obscura_balanced | 22.3443ms | 21.9680ms | 24.7180ms | 44.7541 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |
| obscura_accurate | 47.4305ms | 47.1880ms | 51.3840ms | 21.0835 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |
| obscura_openmed_pii | 235.7856ms | 218.6530ms | 350.6690ms | 4.2411 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |

## Limitations

- All entries are loaded from generated JSON reports.
- same_samples is true only when every report declares the same dataset.sample_ids list.
- Obscura deterministic_plus uses context-limited local recognizers; it is not broad NER parity.
