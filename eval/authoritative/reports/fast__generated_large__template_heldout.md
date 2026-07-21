# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_generated_large_deterministic_plus_template_heldout_full_authoritative_common_r1
- Adapter: Obscura.Fixtures.ObscuraAnalyzerAdapter+DeterministicPlus
- Profile: deterministic_plus
- Dataset: generated_large
- Samples: 648

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.9618 |
| Recall | 0.5101 |
| F1 | 0.6667 |
| F2 | 0.5630 |
| True positives | 503 |
| False positives | 20 |
| False negatives | 483 |
| Offset mismatches | 34 |
| Wrong entity type | 0 |
| Unsupported expected spans | 964 |

### Template Split

| Field | Value |
| --- | ---: |
| Split | template_heldout |
| Strategy | template_id |
| Train ratio | 0.7000 |
| Total templates | 127 |
| Selected templates | 39 |
| Heldout templates | 39 |


### IoU Span Metrics

| Metric | Value |
| --- | ---: |
| IoU threshold | 0.9000 |
| Precision | 0.9031 |
| Recall | 0.4931 |
| F1 | 0.6379 |
| F2 | 0.5424 |
| True positives | 503 |
| False positives | 54 |
| False negatives | 517 |
| Wrong entity type | 0 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 183 |
| Predicted adjacent merges | 52 |
| Normalized IoU precision | 0.8772 |
| Normalized IoU recall | 0.5293 |
| Normalized IoU F1 | 0.6602 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| person | 14 | false_positive: 14 |
| location | 6 | false_positive: 6 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| person | 277 | open_class_model_recall_gap: 277 |
| location | 162 | open_class_model_recall_gap: 162 |
| phone | 44 | phone_pattern_gap: 44 |

#### Wrong entity type

No entries.

#### Wrong Entity Matrix

No entries.



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | PERSON | unknown | none | 147 | 11-20 | false_positive | 5 |
| person | PERSON | unknown | none | 147 | 6-10 | false_positive | 4 |
| person | PERSON | unknown | none | 154 | 11-20 | false_positive | 3 |
| location | LOCATION | unknown | none | 169 | 11-20 | false_positive | 2 |
| location | LOCATION | unknown | none | 147 | 11-20 | false_positive | 1 |
| location | LOCATION | unknown | none | 147 | 6-10 | false_positive | 1 |
| location | LOCATION | unknown | none | 152 | 3-5 | false_positive | 1 |
| location | LOCATION | unknown | none | 152 | 6-10 | false_positive | 1 |
| person | PERSON | unknown | none | 130 | 11-20 | false_positive | 1 |
| person | PERSON | unknown | none | 147 | 21+ | false_positive | 1 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | PERSON | unknown | none | 159 | 6-10 | open_class_model_recall_gap | 84 |
| person | PERSON | unknown | none | 159 | 3-5 | open_class_model_recall_gap | 42 |
| person | PERSON | unknown | none | 153 | 11-20 | open_class_model_recall_gap | 30 |
| location | LOCATION | unknown | none | 153 | 6-10 | open_class_model_recall_gap | 19 |
| person | PERSON | unknown | none | 169 | 11-20 | open_class_model_recall_gap | 15 |
| person | PERSON | unknown | none | 171 | 3-5 | open_class_model_recall_gap | 13 |
| person | PERSON | unknown | none | 144 | 11-20 | open_class_model_recall_gap | 11 |
| location | LOCATION | unknown | none | 153 | 11-20 | open_class_model_recall_gap | 8 |
| phone | PHONE_NUMBER | unknown | none | 149 | 11-20 | phone_pattern_gap | 5 |
| location | LOCATION | unknown | none | 132 | 11-20 | open_class_model_recall_gap | 4 |



### Model Label Error Analysis

#### False positives by model label

No entries.

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| person | 277 | person: 277 | 159: 126, 153: 32, 171: 17, 169: 16, 144: 11 |
| location | 162 | location: 162 | 153: 32, 132: 16, 131: 13, 178: 12, 135: 11 |
| phone | 44 | phone: 44 | 164: 14, 149: 12, 143: 11, 172: 7 |

#### Offset mismatches by model label

No entries.

#### Wrong entity type by model label

No entries.



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PERSON | PERSON | person | AAAAAA | 0.70-0.79 | not_required | n/a | 704, 940 | 147 | 2 |
| LOCATION | LOCATION | location | AAAAA | 0.70-0.79 | not_required | n/a | 2047 | 152 | 1 |
| LOCATION | LOCATION | location | AAAAAAA | 0.70-0.79 | not_required | n/a | 940 | 147 | 1 |
| LOCATION | LOCATION | location | AAAAAAA AAAAAAA | 0.70-0.79 | not_required | n/a | 570 | 169 | 1 |
| LOCATION | LOCATION | location | AAAAAAAA 99999 | 0.70-0.79 | not_required | n/a | 712 | 169 | 1 |
| LOCATION | LOCATION | location | AAAAAAAAA | 0.70-0.79 | not_required | n/a | 2047 | 152 | 1 |
| LOCATION | LOCATION | location | AAAAAAAAAA AAAAA | 0.70-0.79 | not_required | n/a | 940 | 147 | 1 |
| PERSON | PERSON | person | AAAA AAAA AAAAAA | 0.70-0.79 | not_required | n/a | 101 | 147 | 1 |
| PERSON | PERSON | person | AAAAA AAAAAA | 0.70-0.79 | not_required | n/a | 579 | 130 | 1 |
| PERSON | PERSON | person | AAAAAA AAAAA | 0.70-0.79 | not_required | n/a | 1326 | 147 | 1 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| person | PERSON | person | AAAAAA | n/a | not_required | n/a | 15, 18, 28, 30, 90 | 159, 168, 171, 173 | 41 |
| person | PERSON | person | AAAAAAA | n/a | not_required | n/a | 28, 30, 58, 100, 159 | 159, 171, 168, 173, 181 | 40 |
| person | PERSON | person | AAAAA | n/a | not_required | n/a | 15, 28, 30, 58, 100 | 159, 171, 168, 173, 181 | 31 |
| person | PERSON | person | AAAA | n/a | not_required | n/a | 8, 15, 30, 100, 166 | 173, 159, 168 | 27 |
| location | LOCATION | location | AAAAAAA | n/a | not_required | n/a | 1, 290, 586, 686, 738 | 178, 153, 154, 160, 131 | 20 |
| person | PERSON | person | AA. | n/a | not_required | n/a | 34, 90, 147, 196, 254 | 171 | 14 |
| location | LOCATION | location | AAAAA | n/a | not_required | n/a | 1, 421, 572, 675, 701 | 178, 181, 153, 158, 179 | 13 |
| location | LOCATION | location | AAAAAA | n/a | not_required | n/a | 43, 135, 762, 943, 950 | 153, 131, 179, 178, 132 | 13 |
| location | LOCATION | location | AAAAAAAAAA | n/a | not_required | n/a | 56, 144, 226, 267, 604 | 135, 160, 179, 158, 153 | 12 |
| person | PERSON | person | AAAAAAAA | n/a | not_required | n/a | 1081, 1178, 1438, 1628, 1630 | 159, 168, 173 | 12 |

#### Location false positives by GPE/FAC/LOC model label

No entries.

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | LOCATION | location | AAAAA | n/a | not_required | n/a | 572, 798, 2025 | 153 | 3 |
| location | LOCATION | location | AAAAAAA | n/a | not_required | n/a | 686, 738 | 153 | 3 |
| location | LOCATION | location | AAAAAAAA | n/a | not_required | n/a | 1375, 1932 | 153 | 3 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 1943, 2077 | 143 | 2 |
| location | LOCATION | location | AAAAA | n/a | not_required | n/a | 675, 758 | 158 | 2 |
| location | LOCATION | location | AAAAAAAAA | n/a | not_required | n/a | 38, 290 | 153 | 2 |
| location | LOCATION | location | AA AAAAAAAA | n/a | not_required | n/a | 892 | 181 | 1 |
| location | LOCATION | location | AAA AAAA | n/a | not_required | n/a | 604 | 153 | 1 |
| location | LOCATION | location | AAA AAAAAA | n/a | not_required | n/a | 108 | 179 | 1 |
| location | LOCATION | location | AAA AAAAAAAA AAAAAAAAA | n/a | not_required | n/a | 1459 | 135 | 1 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| LOCATION | LOCATION | location | AAAAAA | 0.70-0.79 | not_required | n/a | 300, 1129, 2003 | 178, 141 | 3 |
| LOCATION | LOCATION | location | AAAAAAAA | 0.70-0.79 | not_required | n/a | 366, 986, 1134 | 157, 178 | 3 |
| PHONE_NUMBER | PHONE_NUMBER | phone | 999-999-9999 | 0.70-0.79 | not_required | n/a | 323, 493, 2053 | 143 | 3 |
| LOCATION | LOCATION | location | AAAA | 0.70-0.79 | not_required | n/a | 435, 1485 | 141, 157 | 2 |
| LOCATION | LOCATION | location | AAAAAAA | 0.70-0.79 | not_required | n/a | 1509, 1524 | 141 | 2 |
| LOCATION | LOCATION | location | AAAAAAAAA | 0.70-0.79 | not_required | n/a | 1353, 1786 | 178, 157 | 2 |
| PERSON | PERSON | person | AAAAA AAAAAAAAAAA AAAAA | 0.70-0.79 | not_required | n/a | 861, 1839 | 131 | 2 |
| PHONE_NUMBER | PHONE_NUMBER | phone | 999-999-9999 | 0.90-0.94 | matched | n/a | 662, 936 | 149 | 2 |
| LOCATION | LOCATION | location | AA | 0.70-0.79 | not_required | n/a | 416 | 157 | 1 |
| LOCATION | LOCATION | location | AAAAA'A | 0.70-0.79 | not_required | n/a | 1491 | 178 | 1 |

#### Wrong entity type rows

No entries.



### Structured Model Error Rows

Values are sanitized; rows include Presidio-Research-style error context for tuning.

| Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 1 | 178 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAA | n/a | not_required | n/a | n/a | n/a | 1 | 178 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 38 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 38 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 43 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAA AAAA | n/a | not_required | n/a | n/a | n/a | 43 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 56 | 135 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 102 | 158 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAA AAAAAA | n/a | not_required | n/a | n/a | n/a | 108 | 179 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAA | n/a | not_required | n/a | n/a | n/a | 125 | 160 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 135 | 131 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 144 | 160 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAA AAAAAA | n/a | not_required | n/a | n/a | n/a | 145 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA AAA | n/a | not_required | n/a | n/a | n/a | 145 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 226 | 179 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 267 | 158 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 290 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 290 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 303 | 178 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 303 | 178 | 0.0000 | location not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 169 | 16 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 16 |
| 172 | 14 | 1.0000 | 0.2500 | 0.4000 | 0.2941 | 7 | 0 | 21 |
| 164 | 25 | 1.0000 | 0.4400 | 0.6111 | 0.4955 | 11 | 0 | 14 |
| 173 | 12 | 1.0000 | 0.5000 | 0.6667 | 0.5556 | 18 | 0 | 18 |
| 171 | 14 | 1.0000 | 0.5714 | 0.7273 | 0.6250 | 24 | 0 | 18 |
| 178 | 17 | 1.0000 | 0.5862 | 0.7391 | 0.6391 | 17 | 0 | 12 |
| 181 | 12 | 1.0000 | 0.6250 | 0.7692 | 0.6757 | 15 | 0 | 9 |
| 132 | 27 | 1.0000 | 0.7037 | 0.8261 | 0.7480 | 38 | 0 | 16 |
| 149 | 15 | 1.0000 | 0.7500 | 0.8571 | 0.7895 | 39 | 0 | 13 |
| 170 | 16 | 1.0000 | 0.7500 | 0.8571 | 0.7895 | 12 | 0 | 4 |
| 141 | 13 | 1.0000 | 0.7778 | 0.8750 | 0.8140 | 7 | 0 | 2 |
| 154 | 23 | 0.9500 | 0.8261 | 0.8837 | 0.8482 | 57 | 3 | 12 |
| 143 | 19 | 1.0000 | 0.7935 | 0.8848 | 0.8277 | 73 | 0 | 19 |
| 157 | 17 | 1.0000 | 0.8333 | 0.9091 | 0.8621 | 10 | 0 | 2 |
| 152 | 19 | 0.9048 | 1.0000 | 0.9500 | 0.9794 | 19 | 2 | 0 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person | 0 | 8 | n/a | PERSON |
| person | 0 | 16 | n/a | PERSON |
| person | 8 | 26 | n/a | PERSON |
| location | 67 | 82 | n/a | LOCATION |
| person | 4 | 16 | n/a | PERSON |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location | 54 | 61 | n/a | LOCATION |
| location | 30 | 35 | n/a | LOCATION |
| person | 39 | 43 | n/a | PERSON |
| person | 52 | 60 | n/a | PERSON |
| person | 41 | 47 | n/a | PERSON |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/person | 5/5 | 18/22 | n/a | PERSON/PERSON |
| person/person | 0/4 | 20/30 | n/a | PERSON/PERSON |
| location/location | 30/30 | 44/36 | n/a | LOCATION/LOCATION |
| phone/phone | 86/90 | 102/102 | n/a | PHONE_NUMBER/PHONE_NUMBER |
| location/location | 33/33 | 49/42 | n/a | LOCATION/LOCATION |

#### Wrong entity type

No examples.



## Limitations

- Presidio-Research template_heldout_full compatibility report using deterministic local recognizers.
- Person and location recognizers are context-limited and are not broad NER replacements.
- Address recognition is limited to explicit generated Presidio-Research address contexts.
- Unsupported entities remain separate from analyzer failures.
