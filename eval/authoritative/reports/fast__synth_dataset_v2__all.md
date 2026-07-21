# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_synth_dataset_v2_deterministic_plus_full_authoritative_common_r1
- Adapter: Obscura.Fixtures.ObscuraAnalyzerAdapter+DeterministicPlus
- Profile: deterministic_plus
- Dataset: synth_dataset_v2
- Samples: 1500

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.9349 |
| Recall | 0.4844 |
| F1 | 0.6382 |
| F2 | 0.5361 |
| True positives | 747 |
| False positives | 52 |
| False negatives | 795 |
| Offset mismatches | 33 |
| Wrong entity type | 0 |
| Unsupported expected spans | 1288 |



### IoU Span Metrics

| Metric | Value |
| --- | ---: |
| IoU threshold | 0.9000 |
| Precision | 0.8978 |
| Recall | 0.4743 |
| F1 | 0.6207 |
| F2 | 0.5237 |
| True positives | 747 |
| False positives | 85 |
| False negatives | 828 |
| Wrong entity type | 0 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 119 |
| Predicted adjacent merges | 30 |
| Normalized IoU precision | 0.8953 |
| Normalized IoU recall | 0.4931 |
| Normalized IoU F1 | 0.6360 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| url | 37 | false_positive: 37 |
| person | 8 | false_positive: 8 |
| location | 4 | false_positive: 4 |
| credit_card | 3 | false_positive: 3 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| person | 489 | open_class_model_recall_gap: 489 |
| location | 246 | open_class_model_recall_gap: 246 |
| phone | 50 | phone_pattern_gap: 50 |
| credit_card | 10 | recognizer_recall_gap: 10 |

#### Wrong entity type

No entries.

#### Wrong Entity Matrix

No entries.



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| url | URL | unknown | none | 188 | 21+ | false_positive | 13 |
| url | URL | unknown | none | 81 | 21+ | false_positive | 10 |
| url | URL | unknown | none | 80 | 21+ | false_positive | 7 |
| url | URL | unknown | none | 83 | 21+ | false_positive | 7 |
| location | LOCATION | unknown | none | 147 | 11-20 | false_positive | 2 |
| person | PERSON | unknown | none | 147 | 21+ | false_positive | 2 |
| person | PERSON | unknown | none | 194 | 0-2 | false_positive | 2 |
| credit_card | CREDIT_CARD | unknown | none | 5 | 11-20 | false_positive | 1 |
| credit_card | CREDIT_CARD | unknown | none | 82 | 11-20 | false_positive | 1 |
| credit_card | CREDIT_CARD | unknown | none | 128 | 11-20 | false_positive | 1 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | PERSON | unknown | none | 159 | 6-10 | open_class_model_recall_gap | 26 |
| person | PERSON | unknown | none | 120 | 6-10 | open_class_model_recall_gap | 21 |
| person | PERSON | unknown | none | 159 | 3-5 | open_class_model_recall_gap | 20 |
| person | PERSON | unknown | none | 167 | 11-20 | open_class_model_recall_gap | 15 |
| person | PERSON | unknown | none | 101 | 6-10 | open_class_model_recall_gap | 14 |
| person | PERSON | unknown | none | 200 | 3-5 | open_class_model_recall_gap | 14 |
| person | PERSON | unknown | none | 200 | 6-10 | open_class_model_recall_gap | 12 |
| person | PERSON | unknown | none | 197 | 11-20 | open_class_model_recall_gap | 9 |
| location | GPE | unknown | none | 22 | 6-10 | open_class_model_recall_gap | 8 |
| location | GPE | unknown | none | 153 | 11-20 | open_class_model_recall_gap | 5 |



### Model Label Error Analysis

#### False positives by model label

No entries.

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| person | 489 | person: 489 | 159: 48, 200: 28, 120: 27, 101: 22, 197: 17 |
| location | 246 | location: 246 | 153: 20, 118: 12, 151: 12, 111: 8, 131: 8 |
| phone | 50 | phone: 50 | 150: 11, 149: 7, 164: 7, 172: 5, 143: 2 |
| credit_card | 10 | credit_card: 10 | 13: 2, 56: 2, 0: 1, 2: 1, 25: 1 |

#### Offset mismatches by model label

No entries.

#### Wrong entity type by model label

No entries.



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| CREDIT_CARD | CREDIT_CARD | credit_card | 99999999999999 | 0.90-0.94 | not_required | n/a | 648, 1037, 1187 | 5, 82, 128 | 3 |
| PERSON | PERSON | person | AA | 0.70-0.79 | not_required | n/a | 178, 838 | 194 | 2 |
| URL | URL | url | AAAAA://AAA.AAAAAA.AA/ | 0.80-0.89 | not_required | n/a | 49, 335 | 188, 83 | 2 |
| LOCATION | LOCATION | location | AAAAA AAAAAA. | 0.70-0.79 | not_required | n/a | 1481 | 188 | 1 |
| LOCATION | LOCATION | location | AAAAAAAAAAA | 0.70-0.79 | not_required | n/a | 266 | 147 | 1 |
| LOCATION | LOCATION | location | AAAAAAAAAAA 99999. | 0.70-0.79 | not_required | n/a | 566 | 188 | 1 |
| LOCATION | LOCATION | location | AAAAAAAAAAAAA | 0.70-0.79 | not_required | n/a | 266 | 147 | 1 |
| PERSON | PERSON | person | AAAA AAAAAAAAAAA | 0.70-0.79 | not_required | n/a | 390 | 147 | 1 |
| PERSON | PERSON | person | AAAAA, AAAAA AAA AAAAA | 0.70-0.79 | not_required | n/a | 360 | 147 | 1 |
| PERSON | PERSON | person | AAAAAA | 0.70-0.79 | not_required | n/a | 1441 | 147 | 1 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | location | AAAAAAA | n/a | not_required | n/a | 3, 48, 73, 139, 159 | 118, 24, 111, 209, 131 | 60 |
| person | PERSON | person | AAAAAA | n/a | not_required | n/a | 4, 15, 19, 23, 25 | 58, 200, 99, 120, 159 | 46 |
| person | PERSON | person | AAAAAAA | n/a | not_required | n/a | 23, 25, 43, 79, 85 | 120, 92, 159, 101, 200 | 46 |
| person | PERSON | person | AAAAA | n/a | not_required | n/a | 21, 23, 25, 42, 79 | 58, 120, 102, 159, 200 | 45 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 11, 39, 41, 89, 156 | 22, 202, 112, 209, 111 | 41 |
| person | PERSON | person | AAAA | n/a | not_required | n/a | 15, 41, 79, 93, 151 | 200, 112, 159, 120, 102 | 29 |
| location | GPE | location | AAAAA | n/a | not_required | n/a | 52, 81, 100, 167, 239 | 30, 118, 179, 191, 189 | 17 |
| location | GPE | location | AAAAAAAA | n/a | not_required | n/a | 37, 53, 54, 61, 289 | 30, 179, 151, 110, 153 | 17 |
| location | GPE | location | AAAAAAAAA | n/a | not_required | n/a | 117, 135, 180, 402, 407 | 126, 209, 119, 100, 115 | 16 |
| person | PERSON | person | AAAAA AAAAA | n/a | not_required | n/a | 51, 361, 365, 619, 668 | 139, 188, 94, 48, 150 | 16 |

#### Location false positives by GPE/FAC/LOC model label

No entries.

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | location | AA | n/a | not_required | n/a | 14, 839, 1236 | 151 | 3 |
| location | GPE | location | AAA | n/a | not_required | n/a | 504, 693, 877 | 131 | 3 |
| location | GPE | location | AAA | n/a | not_required | n/a | 54, 451, 516 | 151 | 3 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 11, 202, 1240 | 22 | 3 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 1203, 1419 | 153 | 3 |
| location | GPE | location | AAA AAAAAAA | n/a | not_required | n/a | 302, 340 | 153 | 2 |
| location | GPE | location | AAAAA | n/a | not_required | n/a | 52, 239 | 30 | 2 |
| location | GPE | location | AA | n/a | not_required | n/a | 159 | 131 | 1 |
| location | GPE | location | AAA AAAA | n/a | not_required | n/a | 1435 | 179 | 1 |
| location | GPE | location | AAA AAAAAAA | n/a | not_required | n/a | 486 | 154 | 1 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PHONE_NUMBER | PHONE_NUMBER | phone | 99 999 99 99 | 0.70-0.79 | not_required | n/a | 355, 780, 857, 1005, 1234 | 150, 143 | 5 |
| LOCATION | LOCATION | location | AAA | 0.70-0.79 | not_required | n/a | 275, 749, 906 | 178, 142 | 3 |
| PERSON | PERSON | person | AAAAA | 0.70-0.79 | not_required | n/a | 140, 514, 1125 | 115 | 3 |
| LOCATION | LOCATION | location | AAAA | 0.70-0.79 | not_required | n/a | 575, 627 | 157, 141 | 2 |
| LOCATION | LOCATION | location | AAAAA | 0.70-0.79 | not_required | n/a | 38, 1160 | 157, 178 | 2 |
| PERSON | PERSON | person | AAAAAA | 0.70-0.79 | not_required | n/a | 192, 435 | 115 | 2 |
| LOCATION | LOCATION | location | AAAAAA | 0.70-0.79 | not_required | n/a | 292 | 142 | 1 |
| LOCATION | LOCATION | location | AAAAAAAAAA | 0.70-0.79 | not_required | n/a | 378 | 157 | 1 |
| PERSON | PERSON | person | AA | 0.70-0.79 | not_required | n/a | 1355 | 181 | 1 |
| PERSON | PERSON | person | AAAA | 0.70-0.79 | not_required | n/a | 1345 | 115 | 1 |

#### Wrong entity type rows

No entries.



### Structured Model Error Rows

Values are sanitized; rows include Presidio-Research-style error context for tuning.

| Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 37 | 30 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 267 | 56 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 558 | 25 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 573 | 26 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 718 | 13 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 921 | 56 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 932 | 2 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 1056 | 8 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 1191 | 13 | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | CREDIT_CARD | 999999999999 | n/a | not_required | n/a | n/a | n/a | 1245 | 0 | 0.0000 | credit_card not detected |
| FN | location | O | location | GPE | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 3 | 118 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 11 | 22 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AA | n/a | not_required | n/a | n/a | n/a | 14 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 14 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 37 | 30 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 39 | 202 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 41 | 112 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 48 | 24 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAA | n/a | not_required | n/a | n/a | n/a | 52 | 30 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 53 | 179 | 0.0000 | location not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 164 | 9 | 1.0000 | 0.2222 | 0.3636 | 0.2632 | 2 | 0 | 7 |
| 172 | 9 | 1.0000 | 0.2222 | 0.3636 | 0.2632 | 4 | 0 | 14 |
| 112 | 2 | 1.0000 | 0.2500 | 0.4000 | 0.2941 | 2 | 0 | 6 |
| 57 | 4 | 1.0000 | 0.2500 | 0.4000 | 0.2941 | 1 | 0 | 3 |
| 151 | 6 | 1.0000 | 0.2778 | 0.4348 | 0.3247 | 5 | 0 | 13 |
| 93 | 6 | 1.0000 | 0.3333 | 0.5000 | 0.3846 | 2 | 0 | 4 |
| 188 | 13 | 0.5588 | 0.4872 | 0.5205 | 0.5000 | 19 | 15 | 20 |
| 149 | 4 | 1.0000 | 0.3571 | 0.5263 | 0.4098 | 5 | 0 | 9 |
| 44 | 7 | 1.0000 | 0.4286 | 0.6000 | 0.4839 | 3 | 0 | 4 |
| 150 | 8 | 1.0000 | 0.4444 | 0.6154 | 0.5000 | 12 | 0 | 15 |
| 30 | 9 | 1.0000 | 0.4444 | 0.6154 | 0.5000 | 8 | 0 | 10 |
| 209 | 14 | 1.0000 | 0.4643 | 0.6341 | 0.5200 | 13 | 0 | 15 |
| 119 | 5 | 1.0000 | 0.5000 | 0.6667 | 0.5556 | 5 | 0 | 5 |
| 12 | 4 | 1.0000 | 0.5000 | 0.6667 | 0.5556 | 2 | 0 | 2 |
| 36 | 2 | 1.0000 | 0.5000 | 0.6667 | 0.5556 | 2 | 0 | 2 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| url | 14 | 49 | n/a | URL |
| url | 27 | 54 | n/a | URL |
| url | 134 | 156 | n/a | URL |
| url | 14 | 44 | n/a | URL |
| url | 27 | 54 | n/a | URL |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person | 177 | 197 | n/a | PERSON |
| location | 158 | 165 | n/a | GPE |
| person | 11 | 17 | n/a | PERSON |
| person | 124 | 142 | n/a | PERSON |
| person | 89 | 104 | n/a | PERSON |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location/location | 33/33 | 48/38 | n/a | GPE/LOCATION |
| person/person | 256/256 | 270/261 | n/a | PERSON/PERSON |
| person/person | 5/5 | 19/23 | n/a | PERSON/PERSON |
| person/person | 272/272 | 287/278 | n/a | PERSON/PERSON |
| location/location | 59/59 | 70/62 | n/a | GPE/LOCATION |

#### Wrong entity type

No examples.



## Limitations

- Presidio-Research full compatibility report using deterministic local recognizers.
- Person and location recognizers are context-limited and are not broad NER replacements.
- Address recognition is limited to explicit generated Presidio-Research address contexts.
- Unsupported entities remain separate from analyzer failures.
