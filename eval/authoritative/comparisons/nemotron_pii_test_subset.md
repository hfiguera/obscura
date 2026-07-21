# Presidio vs Obscura Comparison Report

- Run ID: authoritative_presidio_vs_obscura_nemotron_pii_test_subset
- Same sample IDs: true
- Same protocol fingerprints: true

## Sample Identity

- presidio_spacy: 500 ordered IDs; SHA-256 `14206c51fbdafb0c28331bd07e74a26a6beede594c3edf4246163df32844972c`
- obscura_fast: 500 ordered IDs; SHA-256 `14206c51fbdafb0c28331bd07e74a26a6beede594c3edf4246163df32844972c`
- obscura_balanced: 500 ordered IDs; SHA-256 `14206c51fbdafb0c28331bd07e74a26a6beede594c3edf4246163df32844972c`
- obscura_accurate: 500 ordered IDs; SHA-256 `14206c51fbdafb0c28331bd07e74a26a6beede594c3edf4246163df32844972c`
- obscura_openmed_pii: 500 ordered IDs; SHA-256 `14206c51fbdafb0c28331bd07e74a26a6beede594c3edf4246163df32844972c`

## Metrics

| Entry | Profile | Scope | Split | Precision | Recall | F1 | F2 | IoU F1 | TP | FP | FN | Offset mismatches | Wrong type | Unsupported |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| presidio_spacy | presidio_spacy_en_core_web_lg | n/a | all | 0.5970 | 0.6565 | 0.6254 | 0.6437 | 0.5402 | 883 | 596 | 462 | 329 | 51 | 2361 |
| obscura_fast | deterministic_plus | full | all | 0.8037 | 0.2729 | 0.4074 | 0.3144 | 0.4218 | 438 | 107 | 1167 | 101 | 19 | 2361 |
| obscura_balanced | hybrid_ner_tner_conservative | full | all | 0.8703 | 0.5790 | 0.6954 | 0.6206 | 0.6105 | 839 | 125 | 610 | 258 | 18 | 2361 |
| obscura_accurate | hybrid_ner_tner_jean_location | full | all | 0.7327 | 0.5481 | 0.6271 | 0.5772 | 0.5564 | 792 | 289 | 653 | 257 | 23 | 2361 |
| obscura_openmed_pii | privacy_filter_native | full | all | 0.4928 | 0.9825 | 0.6564 | 0.8196 | 0.6555 | 1680 | 1729 | 30 | 13 | 2 | 2361 |

## Latency

| Entry | Mean | Median | P95 | Throughput | Runs | Comparison |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| presidio_spacy | 24.4653ms | 20.7062ms | 57.9023ms | 40.8742 samples/s | 2 | comparable: same physical machine and CPU device |
| obscura_fast | 0.3189ms | 0.2410ms | 0.6170ms | 3136.2120 samples/s | 2 | comparable: same physical machine and CPU device |
| obscura_balanced | 24.3216ms | 23.9910ms | 26.7610ms | 41.1157 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |
| obscura_accurate | 52.0591ms | 52.5030ms | 56.3230ms | 19.2089 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |
| obscura_openmed_pii | 840.0037ms | 717.3150ms | 1718.2790ms | 1.1905 samples/s | 2 | not comparable: different or unproven execution device/backend conditions |

## Limitations

- All entries are loaded from generated JSON reports.
- same_samples is true only when every report declares the same dataset.sample_ids list.
- Obscura deterministic_plus uses context-limited local recognizers; it is not broad NER parity.
