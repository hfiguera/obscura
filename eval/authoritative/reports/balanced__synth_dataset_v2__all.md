# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_synth_dataset_v2_hybrid_ner_tner_conservative_full_authoritative_common_r1
- Adapter: Obscura.Deterministic+Obscura.Recognizer.NER.Serving
- Profile: hybrid_ner_tner_conservative
- Dataset: synth_dataset_v2
- Samples: 1500

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.8297 |
| Recall | 0.8480 |
| F1 | 0.8388 |
| F2 | 0.8443 |
| True positives | 1272 |
| False positives | 261 |
| False negatives | 228 |
| Offset mismatches | 75 |
| Wrong entity type | 0 |
| Unsupported expected spans | 1288 |



### IoU Span Metrics

| Metric | Value |
| --- | ---: |
| IoU threshold | 0.9000 |
| Precision | 0.7935 |
| Recall | 0.8102 |
| F1 | 0.8018 |
| F2 | 0.8068 |
| True positives | 1276 |
| False positives | 332 |
| False negatives | 299 |
| Wrong entity type | 0 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 119 |
| Predicted adjacent merges | 150 |
| Normalized IoU precision | 0.8059 |
| Normalized IoU recall | 0.8070 |
| Normalized IoU F1 | 0.8065 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 170 | model_open_class_false_positive: 169, model_boundary_fragment: 1 |
| person | 51 | model_open_class_false_positive: 45, model_boundary_fragment: 6 |
| url | 37 | false_positive: 37 |
| credit_card | 3 | false_positive: 3 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 135 | open_class_model_recall_gap: 135 |
| phone | 53 | phone_pattern_gap: 53 |
| person | 30 | open_class_model_recall_gap: 30 |
| credit_card | 10 | recognizer_recall_gap: 10 |

#### Wrong entity type

No entries.

#### Wrong Entity Matrix

No entries.



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| url | URL | unknown | none | 81 | 21+ | false_positive | 10 |
| location | GPE | unknown | GPE | 177 | 6-10 | model_open_class_false_positive | 9 |
| url | URL | unknown | none | 83 | 21+ | false_positive | 7 |
| location | GPE | unknown | GPE | 188 | 6-10 | model_open_class_false_positive | 6 |
| location | GPE | unknown | GPE | 3 | 6-10 | model_open_class_false_positive | 5 |
| location | GPE | unknown | GPE | 7 | 6-10 | model_open_class_false_positive | 4 |
| location | GPE | unknown | GPE | 8 | 6-10 | model_open_class_false_positive | 4 |
| location | GPE | unknown | GPE | 30 | 6-10 | model_open_class_false_positive | 4 |
| person | PERSON | unknown | PERSON | 116 | 6-10 | model_open_class_false_positive | 3 |
| location | FAC | unknown | FAC | 145 | 11-20 | model_open_class_false_positive | 2 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | unknown | none | 153 | 6-10 | open_class_model_recall_gap | 11 |
| phone | PHONE_NUMBER | unknown | none | 150 | 11-20 | phone_pattern_gap | 8 |
| location | GPE | unknown | none | 129 | 11-20 | open_class_model_recall_gap | 4 |
| location | GPE | unknown | none | 131 | 3-5 | open_class_model_recall_gap | 4 |
| phone | PHONE_NUMBER | unknown | none | 149 | 11-20 | phone_pattern_gap | 4 |
| location | GPE | unknown | none | 154 | 6-10 | open_class_model_recall_gap | 3 |
| credit_card | CREDIT_CARD | unknown | none | 13 | 11-20 | recognizer_recall_gap | 2 |
| credit_card | CREDIT_CARD | unknown | none | 56 | 11-20 | recognizer_recall_gap | 2 |
| location | GPE | unknown | none | 112 | 6-10 | open_class_model_recall_gap | 2 |
| person | PERSON | unknown | none | 153 | 11-20 | open_class_model_recall_gap | 2 |



### Model Label Error Analysis

#### False positives by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| GPE | 142 | location: 142 | 177: 12, 145: 10, 188: 10, 50: 5, 140: 2 |
| PERSON | 51 | person: 51 | 104: 5, 116: 5, 42: 3, 87: 3, 111: 2 |
| FAC | 23 | location: 23 | 140: 4, 138: 3, 145: 3, 148: 3, 49: 2 |
| LOC | 5 | location: 5 | 130: 1, 131: 1, 188: 1, 3: 1, 74: 1 |

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| location | 135 | location: 135 | 153: 17, 151: 11, 129: 7, 131: 6, 130: 5 |
| phone | 53 | phone: 53 | 150: 11, 149: 8, 164: 8, 188: 8, 143: 2 |
| person | 30 | person: 30 | 130: 3, 149: 3, 109: 2, 153: 2, 102: 1 |
| credit_card | 10 | credit_card: 10 | 13: 2, 56: 2, 0: 1, 2: 1, 25: 1 |

#### Offset mismatches by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| PERSON | 47 | person: 47 | 104: 9, 184: 7, 112: 2, 130: 1, 143: 1 |
| LOC | 11 | location: 11 | 118: 11 |
| GPE | 9 | location: 9 | 111: 1, 132: 1, 137: 1, 139: 1, 142: 1 |

#### Wrong entity type by model label

No entries.



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 37, 49, 131, 176, 206 | 30, 188, 87, 42, 145 | 76 |
| URL | URL | url | omitted:21+ | 0.80-0.89 | not_required | n/a | 27, 30, 49, 59, 103 | 81, 83, 188, 80 | 37 |
| GPE | GPE | location | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 119, 198, 230, 266, 313 | 50, 188, 147, 177, 3 | 34 |
| FAC | FAC | location | omitted:11-20 | 0.95-1.00 | matched | not_adjusted | 54, 201, 361, 369, 529 | 151, 73, 188, 140, 49 | 18 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 1122, 1150, 1201, 1206, 1208 | 116, 104, 87, 199, 140 | 10 |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 198, 275, 570, 705, 812 | 50, 178, 7 | 9 |
| GPE | GPE | location | omitted:3-5 | 0.95-1.00 | not_required | not_adjusted | 119, 355, 592, 1035, 1121 | 50, 150, 148, 177, 3 | 8 |
| PERSON | PERSON | person | omitted:3-5 | 0.95-1.00 | not_required | not_adjusted | 147, 209, 312, 576, 996 | 87, 42, 144, 146, 40 | 6 |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | aligned | 280, 585, 758, 1029, 1079 | 74, 72, 64, 169 | 5 |
| GPE | GPE | location | omitted:11-20 | 0.90-0.94 | not_required | not_adjusted | 164, 222, 1246, 1442 | 145, 72, 30, 63 | 4 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | location | AAAAAAA | n/a | not_required | n/a | 3, 82, 139, 297, 742 | 118, 143, 209, 189, 127 | 19 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 39, 41, 436, 597, 640 | 202, 112, 157, 209, 131 | 16 |
| location | GPE | location | AAAAA | n/a | not_required | n/a | 52, 91, 167, 504, 979 | 30, 137, 191, 131, 179 | 14 |
| credit_card | CREDIT_CARD | credit_card | 999999999999 | n/a | not_required | n/a | 37, 267, 558, 573, 718 | 30, 56, 25, 26, 13 | 10 |
| location | GPE | location | AAAAAAAA | n/a | not_required | n/a | 37, 54, 289, 510, 906 | 30, 151, 153, 129, 178 | 8 |
| location | GPE | location | AAA | n/a | not_required | n/a | 54, 451, 504, 516, 693 | 151, 131 | 6 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 110, 705, 759, 802, 836 | 171, 178, 154, 153, 189 | 6 |
| location | GPE | location | AA | n/a | not_required | n/a | 14, 159, 839, 1236 | 151, 131 | 4 |
| location | GPE | location | AAAA AAAAAAA | n/a | not_required | n/a | 157, 271, 839 | 137, 174, 151 | 3 |
| location | GPE | location | AAAA AAA AAAA | n/a | not_required | n/a | 92, 873 | 157, 153 | 2 |

#### Location false positives by GPE/FAC/LOC model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 37, 49, 131, 176, 206 | 30, 188, 87, 42, 145 | 76 |
| GPE | GPE | location | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 119, 198, 230, 266, 313 | 50, 188, 147, 177, 3 | 34 |
| FAC | FAC | location | omitted:11-20 | 0.95-1.00 | matched | not_adjusted | 54, 201, 361, 369, 529 | 151, 73, 188, 140, 49 | 18 |
| GPE | GPE | location | omitted:3-5 | 0.95-1.00 | not_required | not_adjusted | 119, 355, 592, 1035, 1121 | 50, 150, 148, 177, 3 | 8 |
| GPE | GPE | location | omitted:6-10 | 0.90-0.94 | not_required | not_adjusted | 221, 488, 502, 707, 729 | 39, 27, 177, 72, 3 | 6 |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | aligned | 280, 585, 758, 1029, 1079 | 74, 72, 64, 169 | 5 |
| GPE | GPE | location | omitted:11-20 | 0.90-0.94 | not_required | not_adjusted | 164, 222, 1246, 1442 | 145, 72, 30, 63 | 4 |
| FAC | FAC | location | omitted:21+ | 0.95-1.00 | matched | not_adjusted | 76, 1465 | 49, 188 | 2 |
| FAC | FAC | location | omitted:6-10 | 0.95-1.00 | matched | not_adjusted | 471, 915 | 140 | 2 |
| GPE | GPE | location | omitted:21+ | 0.95-1.00 | not_required | not_adjusted | 279, 1339 | 148 | 2 |

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | location | AA | n/a | not_required | n/a | 14, 839, 1236 | 151 | 3 |
| location | GPE | location | AAA | n/a | not_required | n/a | 504, 693, 877 | 131 | 3 |
| location | GPE | location | AAA | n/a | not_required | n/a | 54, 451, 516 | 151 | 3 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 1203, 1419 | 153 | 3 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 705, 931 | 178 | 2 |
| location | GPE | location | AA | n/a | not_required | n/a | 159 | 131 | 1 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 802 | 153 | 1 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 759 | 154 | 1 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 110 | 171 | 1 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 836 | 189 | 1 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 6, 50, 268, 343, 397 | 104, 184, 197, 167 | 16 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | aligned | 41, 172, 316, 332, 370 | 112, 152, 173, 175 | 10 |
| LOC | LOC | location | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 163, 234, 276, 534, 748 | 118 | 8 |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 51, 149, 292, 317, 826 | 139, 137, 142, 191, 196 | 7 |
| PHONE_NUMBER | PHONE_NUMBER | phone | omitted:11-20 | 0.70-0.79 | not_required | n/a | 355, 738, 780, 857, 1005 | 150, 143 | 6 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 289, 312, 701, 754, 996 | 153, 144, 170, 169, 40 | 5 |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | aligned | 311, 436, 878 | 175, 112, 173 | 3 |
| PERSON | PERSON | person | omitted:21+ | 0.95-1.00 | not_required | not_adjusted | 195, 203, 310 | 184 | 3 |
| LOC | LOC | location | omitted:11-20 | 0.90-0.94 | matched | not_adjusted | 81, 301 | 118 | 2 |
| PERSON | PERSON | person | omitted:6-10 | 0.70-0.79 | not_required | not_adjusted | 230, 857 | 188, 150 | 2 |

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
| FN | location | O | location | GPE | AA | n/a | not_required | n/a | n/a | n/a | 14 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 14 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 37 | 30 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAA AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 38 | 157 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 39 | 202 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 41 | 112 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAA | n/a | not_required | n/a | n/a | n/a | 52 | 30 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAA | n/a | not_required | n/a | n/a | n/a | 54 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 54 | 151 | 0.0000 | location not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 164 | 9 | 1.0000 | 0.1111 | 0.2000 | 0.1351 | 1 | 0 | 8 |
| 191 | 9 | 1.0000 | 0.1250 | 0.2222 | 0.1515 | 1 | 0 | 7 |
| 149 | 4 | 0.7500 | 0.2143 | 0.3333 | 0.2500 | 3 | 1 | 11 |
| 57 | 4 | 1.0000 | 0.2500 | 0.4000 | 0.2941 | 1 | 0 | 3 |
| 144 | 7 | 0.3750 | 0.5000 | 0.4286 | 0.4688 | 3 | 5 | 3 |
| 151 | 6 | 0.8571 | 0.3333 | 0.4800 | 0.3797 | 6 | 1 | 12 |
| 131 | 4 | 0.8333 | 0.4167 | 0.5556 | 0.4630 | 5 | 1 | 7 |
| 188 | 13 | 0.4808 | 0.7353 | 0.5814 | 0.6649 | 25 | 27 | 9 |
| 44 | 7 | 1.0000 | 0.4286 | 0.6000 | 0.4839 | 3 | 0 | 4 |
| 150 | 8 | 0.8000 | 0.4800 | 0.6000 | 0.5217 | 12 | 3 | 13 |
| 178 | 11 | 0.5769 | 0.6818 | 0.6250 | 0.6579 | 15 | 11 | 7 |
| 153 | 10 | 0.9500 | 0.4872 | 0.6441 | 0.5398 | 19 | 1 | 20 |
| 12 | 4 | 1.0000 | 0.5000 | 0.6667 | 0.5556 | 2 | 0 | 2 |
| 127 | 7 | 1.0000 | 0.5000 | 0.6667 | 0.5556 | 7 | 0 | 7 |
| 36 | 2 | 1.0000 | 0.5000 | 0.6667 | 0.5556 | 2 | 0 | 2 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person | 32 | 39 | n/a | PERSON |
| url | 14 | 49 | n/a | URL |
| url | 27 | 54 | n/a | URL |
| location | 101 | 109 | n/a | GPE |
| location | 111 | 117 | n/a | GPE |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location | 158 | 165 | n/a | GPE |
| location | 81 | 83 | n/a | GPE |
| location | 64 | 76 | n/a | GPE |
| person | 0 | 14 | n/a | PERSON |
| location | 133 | 150 | n/a | GPE |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/person | 124/124 | 142/144 | n/a | PERSON/PERSON |
| person/person | 157/157 | 161/163 | n/a | PERSON/PERSON |
| person/person | 0/0 | 15/5 | n/a | PERSON/PERSON |
| person/person | 0/0 | 13/15 | n/a | PERSON/PERSON |
| location/location | 72/72 | 84/82 | n/a | GPE/GPE |

#### Wrong entity type

No examples.



## Limitations

- Presidio-Research full compatibility report using deterministic recognizers plus tner/roberta-large-ontonotes5 with conservative model-specific policy.
- The TNER model card reports strong OntoNotes5 results but warns that plain Transformers usage is not recommended because the CRF layer is unsupported; Bumblebee/Nx output must therefore be treated as experimental until measured.
- DATE/TIME and noisy non-PII OntoNotes labels are ignored by default; organization is allowed only behind higher threshold and context gating.
