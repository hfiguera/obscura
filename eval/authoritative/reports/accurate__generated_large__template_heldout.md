# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_generated_large_hybrid_ner_tner_jean_location_cascade_template_heldout_full_accurate_cascade_r1
- Adapter: Obscura.Deterministic+TNER.Primary+OutputAwareJeanBaptiste.Location
- Profile: hybrid_ner_tner_jean_location_cascade
- Dataset: generated_large
- Samples: 648

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.8249 |
| Recall | 0.7810 |
| F1 | 0.8024 |
| F2 | 0.7894 |
| True positives | 749 |
| False positives | 159 |
| False negatives | 210 |
| Offset mismatches | 58 |
| Wrong entity type | 3 |
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
| Precision | 0.7764 |
| Recall | 0.7375 |
| F1 | 0.7564 |
| F2 | 0.7449 |
| True positives | 750 |
| False positives | 216 |
| False negatives | 267 |
| Wrong entity type | 3 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 183 |
| Predicted adjacent merges | 189 |
| Normalized IoU precision | 0.7314 |
| Normalized IoU recall | 0.6814 |
| Normalized IoU F1 | 0.7055 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 122 | model_open_class_false_positive: 121, model_boundary_fragment: 1 |
| person | 37 | model_open_class_false_positive: 36, model_boundary_fragment: 1 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 124 | open_class_model_recall_gap: 124 |
| phone | 53 | phone_pattern_gap: 53 |
| person | 33 | open_class_model_recall_gap: 33 |

#### Wrong entity type

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 3 | model_label_confusion: 3 |

#### Wrong Entity Matrix

| Expected | Predicted | Count |
| --- | --- | ---: |
| location | person | 3 |



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | unknown | GPE | 152 | 6-10 | model_open_class_false_positive | 12 |
| location | GPE | unknown | GPE | 148 | 6-10 | model_open_class_false_positive | 8 |
| location | GPE | unknown | GPE | 149 | 6-10 | model_open_class_false_positive | 8 |
| location | GPE | unknown | GPE | 147 | 6-10 | model_open_class_false_positive | 7 |
| location | FAC | unknown | FAC | 148 | 11-20 | model_open_class_false_positive | 6 |
| location | GPE | unknown | GPE | 148 | 11-20 | model_open_class_false_positive | 6 |
| location | FAC | unknown | FAC | 139 | 11-20 | model_open_class_false_positive | 4 |
| location | FAC | unknown | FAC | 169 | 11-20 | model_open_class_false_positive | 4 |
| person | PERSON | unknown | PERSON | 146 | 6-10 | model_open_class_false_positive | 4 |
| location | GPE | unknown | GPE | 144 | 11-20 | model_open_class_false_positive | 3 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| location | LOCATION | unknown | none | 154 | 6-10 | open_class_model_recall_gap | 17 |
| person | PERSON | unknown | none | 171 | 3-5 | open_class_model_recall_gap | 14 |
| location | LOCATION | unknown | none | 153 | 6-10 | open_class_model_recall_gap | 12 |
| location | LOCATION | unknown | none | 153 | 11-20 | open_class_model_recall_gap | 7 |
| phone | PHONE_NUMBER | unknown | none | 149 | 11-20 | phone_pattern_gap | 5 |
| location | LOCATION | unknown | none | 130 | 6-10 | open_class_model_recall_gap | 3 |
| location | LOCATION | unknown | none | 132 | 11-20 | open_class_model_recall_gap | 3 |
| person | PERSON | unknown | none | 130 | 11-20 | open_class_model_recall_gap | 3 |
| location | LOCATION | unknown | none | 130 | 11-20 | open_class_model_recall_gap | 2 |
| location | LOCATION | unknown | none | 132 | 6-10 | open_class_model_recall_gap | 2 |



### Model Label Error Analysis

#### False positives by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| GPE | 96 | location: 96 | 177: 19, 148: 17, 152: 16, 147: 12, 149: 12 |
| PERSON | 37 | person: 37 | 178: 10, 146: 8, 154: 3, 147: 2, 149: 2 |
| FAC | 20 | location: 20 | 148: 9, 139: 5, 169: 5, 152: 1 |
| LOC | 6 | location: 6 | 148: 2, 146: 1, 147: 1, 149: 1, 177: 1 |

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| location | 124 | location: 124 | 153: 23, 154: 23, 132: 10, 130: 8, 131: 8 |
| phone | 53 | phone: 53 | 164: 18, 143: 14, 149: 13, 172: 8 |
| person | 33 | person: 33 | 171: 14, 149: 4, 153: 4, 130: 3, 143: 2 |

#### Offset mismatches by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| PERSON | 40 | person: 40 | 152: 19, 143: 5, 154: 5, 153: 3, 130: 2 |
| FAC | 8 | location: 8 | 157: 8 |
| GPE | 5 | location: 5 | 141: 2, 137: 1, 143: 1, 178: 1 |

#### Wrong entity type by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| PERSON | 3 | person: 3 | 131: 1, 132: 1, 181: 1 |



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 23, 27, 54, 101, 193 | 177, 152, 147, 148, 149 | 47 |
| GPE | GPE | location | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 9, 101, 234, 268, 285 | 152, 147, 148, 169, 177 | 21 |
| FAC | FAC | location | omitted:11-20 | 0.95-1.00 | matched | not_adjusted | 241, 268, 285, 348, 612 | 148, 169, 152, 139 | 14 |
| GPE | GPE | location | omitted:3-5 | 0.95-1.00 | not_required | not_adjusted | 54, 803, 935, 954, 1528 | 147, 169, 148, 177 | 9 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 206, 222, 533, 1375, 1402 | 146, 154, 153, 177 | 8 |
| GPE | GPE | location | omitted:21+ | 0.95-1.00 | not_required | not_adjusted | 377, 936, 1093, 1787 | 149, 152 | 4 |
| GPE | GPE | location | omitted:6-10 | 0.90-0.94 | not_required | not_adjusted | 470, 1275, 1519, 2055 | 149, 148, 141 | 4 |
| FAC | FAC | location | omitted:21+ | 0.95-1.00 | matched | not_adjusted | 954, 1247, 1957 | 148, 169 | 3 |
| GPE | GPE | location | omitted:11-20 | 0.90-0.94 | not_required | not_adjusted | 546, 876, 1477 | 177, 130, 147 | 3 |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | aligned | 324, 500, 1276 | 177, 148, 169 | 3 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | LOCATION | location | AAAAAAA | n/a | not_required | n/a | 32, 89, 196, 362, 367 | 154, 171, 130, 153, 178 | 22 |
| person | PERSON | person | AA. | n/a | not_required | n/a | 34, 90, 147, 196, 254 | 171 | 14 |
| location | LOCATION | location | AAAAAA | n/a | not_required | n/a | 43, 112, 135, 222, 223 | 153, 143, 131, 154, 139 | 13 |
| location | LOCATION | location | AAAAAAAA | n/a | not_required | n/a | 147, 303, 678, 908, 923 | 171, 178, 153, 157, 131 | 9 |
| location | LOCATION | location | AAAAAAAAA | n/a | not_required | n/a | 172, 290, 432, 943, 1039 | 154, 153, 178, 139, 131 | 8 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 572, 1315, 1557, 1593, 1943 | 153, 143, 132 | 6 |
| location | LOCATION | location | AAAAA | n/a | not_required | n/a | 572, 633, 930, 1063, 1620 | 153, 137, 132, 143 | 6 |
| location | LOCATION | location | AAAAAAAAAAAA | n/a | not_required | n/a | 38, 138, 1340, 1357, 1932 | 153, 130, 171, 143, 131 | 6 |
| location | LOCATION | location | AAAA AAAAA | n/a | not_required | n/a | 594, 1243, 1648 | 132, 154 | 3 |
| location | LOCATION | location | AA AAAAAAAAA | n/a | not_required | n/a | 24, 416 | 132, 157 | 2 |

#### Location false positives by GPE/FAC/LOC model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 23, 27, 54, 101, 193 | 177, 152, 147, 148, 149 | 47 |
| GPE | GPE | location | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 9, 101, 234, 268, 285 | 152, 147, 148, 169, 177 | 21 |
| FAC | FAC | location | omitted:11-20 | 0.95-1.00 | matched | not_adjusted | 241, 268, 285, 348, 612 | 148, 169, 152, 139 | 14 |
| GPE | GPE | location | omitted:3-5 | 0.95-1.00 | not_required | not_adjusted | 54, 803, 935, 954, 1528 | 147, 169, 148, 177 | 9 |
| GPE | GPE | location | omitted:21+ | 0.95-1.00 | not_required | not_adjusted | 377, 936, 1093, 1787 | 149, 152 | 4 |
| GPE | GPE | location | omitted:6-10 | 0.90-0.94 | not_required | not_adjusted | 470, 1275, 1519, 2055 | 149, 148, 141 | 4 |
| FAC | FAC | location | omitted:21+ | 0.95-1.00 | matched | not_adjusted | 954, 1247, 1957 | 148, 169 | 3 |
| GPE | GPE | location | omitted:11-20 | 0.90-0.94 | not_required | not_adjusted | 546, 876, 1477 | 177, 130, 147 | 3 |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | aligned | 324, 500, 1276 | 177, 148, 169 | 3 |
| LOC | LOC | location | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 328, 1326 | 177, 147 | 2 |

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | LOCATION | location | AAAAAAA | n/a | not_required | n/a | 32, 89, 362, 367, 586 | 154 | 10 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 1315, 1943, 2053 | 143 | 3 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 1557, 1593 | 132 | 2 |
| location | LOCATION | location | AAAAAAA | n/a | not_required | n/a | 475, 560 | 130 | 2 |
| location | LOCATION | location | AAAAAAAA | n/a | not_required | n/a | 1375 | 153 | 2 |
| location | LOCATION | location | AA AAAAA | n/a | not_required | n/a | 1715 | 154 | 1 |
| location | LOCATION | location | AA AAAAAAAA | n/a | not_required | n/a | 892 | 181 | 1 |
| location | LOCATION | location | AA AAAAAAAAA | n/a | not_required | n/a | 24 | 132 | 1 |
| location | LOCATION | location | AA AAAAAAAAA | n/a | not_required | n/a | 416 | 157 | 1 |
| location | LOCATION | location | AAA | n/a | not_required | n/a | 1581 | 130 | 1 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | aligned | 9, 27, 413, 732, 1032 | 152 | 15 |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 172, 232, 362, 579, 700 | 154, 149, 130, 180, 143 | 9 |
| FAC | FAC | location | omitted:11-20 | 0.95-1.00 | matched | not_adjusted | 205, 1289, 1384, 1605 | 157 | 4 |
| FAC | FAC | location | omitted:21+ | 0.95-1.00 | matched | not_adjusted | 366, 782, 1485, 1722 | 157 | 4 |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 1523, 1827, 2003, 2055 | 178, 143, 141 | 4 |
| PERSON | PERSON | person | omitted:6-10 | 0.80-0.89 | not_required | not_adjusted | 43, 572, 1375, 1519 | 153, 149 | 4 |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | aligned | 455, 1349, 1835 | 152 | 3 |
| PHONE_NUMBER | PHONE_NUMBER | phone | omitted:11-20 | 0.70-0.79 | not_required | n/a | 323, 493, 2053 | 143 | 3 |
| PERSON | PERSON | person | omitted:6-10 | 0.70-0.79 | not_required | not_adjusted | 384, 1827 | 143 | 2 |
| PHONE_NUMBER | PHONE_NUMBER | phone | omitted:11-20 | 0.90-0.94 | matched | n/a | 662, 936 | 149 | 2 |

#### Wrong entity type rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PERSON | PERSON | person | omitted:11-20 | 0.70-0.79 | not_required | not_adjusted | 1695 | 131 | 1 |
| PERSON | PERSON | person | omitted:3-5 | 0.95-1.00 | not_required | not_adjusted | 2101 | 181 | 1 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | aligned | 1139 | 132 | 1 |



### Structured Model Error Rows

Values are sanitized; rows include Presidio-Research-style error context for tuning.

| Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| FN | location | O | location | LOCATION | AA AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 24 | 132 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 32 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 38 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 43 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAA AAAA | n/a | not_required | n/a | n/a | n/a | 43 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAA-AAAAAA | n/a | not_required | n/a | n/a | n/a | 46 | 157 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 89 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 112 | 143 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 135 | 131 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 138 | 130 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA AAA | n/a | not_required | n/a | n/a | n/a | 145 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 147 | 171 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 172 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 196 | 171 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 222 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 223 | 139 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 290 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA AAAAAAA | n/a | not_required | n/a | n/a | n/a | 300 | 178 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 303 | 178 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA AAAA | n/a | not_required | n/a | n/a | n/a | 306 | 132 | 0.0000 | location not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 164 | 25 | 1.0000 | 0.2800 | 0.4375 | 0.3271 | 7 | 0 | 18 |
| 169 | 16 | 0.5000 | 1.0000 | 0.6667 | 0.8333 | 16 | 16 | 0 |
| 171 | 14 | 1.0000 | 0.5238 | 0.6875 | 0.5789 | 22 | 0 | 20 |
| 178 | 17 | 0.6970 | 0.6970 | 0.6970 | 0.6970 | 23 | 10 | 10 |
| 149 | 15 | 0.7037 | 0.6909 | 0.6972 | 0.6934 | 38 | 16 | 17 |
| 153 | 16 | 0.9444 | 0.5574 | 0.7010 | 0.6071 | 34 | 2 | 27 |
| 144 | 11 | 0.6429 | 0.9000 | 0.7500 | 0.8333 | 9 | 5 | 1 |
| 154 | 23 | 0.9318 | 0.6406 | 0.7593 | 0.6833 | 41 | 3 | 23 |
| 141 | 13 | 0.8000 | 0.7273 | 0.7619 | 0.7407 | 8 | 2 | 3 |
| 143 | 19 | 0.9825 | 0.6512 | 0.7832 | 0.6983 | 56 | 1 | 30 |
| 131 | 13 | 0.9444 | 0.6800 | 0.7907 | 0.7203 | 17 | 1 | 8 |
| 172 | 14 | 1.0000 | 0.7143 | 0.8333 | 0.7576 | 20 | 0 | 8 |
| 130 | 18 | 0.9535 | 0.7885 | 0.8632 | 0.8167 | 41 | 2 | 11 |
| 168 | 17 | 1.0000 | 0.7647 | 0.8667 | 0.8025 | 13 | 0 | 4 |
| 132 | 27 | 0.9773 | 0.8113 | 0.8866 | 0.8398 | 43 | 1 | 10 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location | 88 | 101 | n/a | GPE |
| location | 52 | 59 | n/a | GPE |
| location | 63 | 73 | n/a | GPE |
| location | 54 | 69 | n/a | FAC |
| person | 8 | 13 | n/a | PERSON |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person | 14 | 20 | n/a | PERSON |
| location | 32 | 44 | n/a | LOCATION |
| location | 102 | 109 | n/a | LOCATION |
| person | 0 | 3 | n/a | PERSON |
| location | 93 | 105 | n/a | LOCATION |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/person | 20/20 | 27/29 | n/a | PERSON/PERSON |
| person/person | 20/20 | 24/26 | n/a | PERSON/PERSON |
| person/person | 1/1 | 13/7 | n/a | PERSON/PERSON |
| person/person | 4/8 | 26/26 | n/a | PERSON/PERSON |
| location/location | 33/33 | 39/52 | n/a | LOCATION/FAC |

#### Wrong entity type

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location/person | 25/25 | 34/34 | n/a | LOCATION/PERSON |
| location/person | 39/39 | 52/52 | n/a | LOCATION/PERSON |
| location/person | 25/25 | 29/29 | n/a | LOCATION/PERSON |



## Limitations

- Presidio-Research template_heldout_full compatibility report using deterministic recognizers and an output-aware two-model local NER cascade.
- TNER remains primary for person, organization, and location; Jean-Baptiste contributes only policy-selected location recovery spans.
- The cascade policy must be selected only on template_train and evaluated unchanged on heldout datasets.
- This profile is experimental and cannot replace :balanced unless fresh accuracy, latency, and reproducibility gates pass.
