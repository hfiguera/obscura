# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_generated_large_privacy_filter_native_template_heldout_full_authoritative_openmed_final_common_default_r1
- Adapter: Obscura.Recognizer.PrivacyFilter.Native
- Profile: privacy_filter_native
- Dataset: generated_large
- Samples: 648

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.3341 |
| Recall | 0.7826 |
| F1 | 0.4683 |
| F2 | 0.6170 |
| True positives | 594 |
| False positives | 1184 |
| False negatives | 165 |
| Offset mismatches | 203 |
| Wrong entity type | 58 |
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
| Precision | 0.3015 |
| Recall | 0.6138 |
| F1 | 0.4044 |
| F2 | 0.5085 |
| True positives | 604 |
| False positives | 1399 |
| False negatives | 380 |
| Wrong entity type | 36 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 183 |
| Predicted adjacent merges | 543 |
| Normalized IoU precision | 0.3980 |
| Normalized IoU recall | 0.7233 |
| Normalized IoU F1 | 0.5134 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| street_address | 561 | model_false_positive: 492, model_boundary_fragment: 69 |
| zip_code | 224 | model_false_positive: 224 |
| person | 189 | model_open_class_false_positive: 187, model_boundary_fragment: 2 |
| location | 131 | model_open_class_false_positive: 119, model_boundary_fragment: 12 |
| date_time | 32 | model_false_positive: 32 |
| age | 28 | model_boundary_fragment: 27, model_false_positive: 1 |
| organization | 12 | model_open_class_false_positive: 12 |
| id | 5 | model_false_positive: 5 |
| us_ssn | 2 | model_false_positive: 2 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 90 | open_class_model_recall_gap: 90 |
| person | 74 | open_class_model_recall_gap: 74 |
| phone | 1 | phone_pattern_gap: 1 |

#### Wrong entity type

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 29 | model_label_confusion: 29 |
| phone | 20 | model_label_confusion: 20 |
| person | 9 | model_label_confusion: 9 |

#### Wrong Entity Matrix

| Expected | Predicted | Count |
| --- | --- | ---: |
| location | street_address | 9 |
| location | id | 7 |
| location | person | 6 |
| phone | zip_code | 6 |
| phone | us_ssn | 5 |
| person | organization | 4 |
| person | street_address | 4 |
| location | organization | 3 |
| phone | id | 3 |
| phone | street_address | 3 |



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | last_name | privacy_filter_native | last_name | 153 | 6-10 | model_open_class_false_positive | 25 |
| age | age | privacy_filter_native | age | 171 | 0-2 | model_boundary_fragment | 14 |
| street_address | street_address | privacy_filter_native | street_address | 154 | 3-5 | model_false_positive | 13 |
| person | last_name | privacy_filter_native | last_name | 154 | 6-10 | model_open_class_false_positive | 11 |
| street_address | street_address | privacy_filter_native | street_address | 169 | 11-20 | model_false_positive | 10 |
| street_address | street_address | privacy_filter_native | street_address | 138 | 0-2 | model_boundary_fragment | 6 |
| location | city | privacy_filter_native | city | 148 | 11-20 | model_open_class_false_positive | 5 |
| age | age | privacy_filter_native | age | 154 | 0-2 | model_boundary_fragment | 4 |
| location | city | privacy_filter_native | city | 149 | 11-20 | model_open_class_false_positive | 4 |
| age | age | privacy_filter_native | age | 149 | 0-2 | model_boundary_fragment | 2 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| location | LOCATION | unknown | none | 154 | 6-10 | open_class_model_recall_gap | 18 |
| person | PERSON | unknown | none | 159 | 6-10 | open_class_model_recall_gap | 17 |
| person | PERSON | unknown | none | 171 | 3-5 | open_class_model_recall_gap | 14 |
| location | LOCATION | unknown | none | 132 | 6-10 | open_class_model_recall_gap | 9 |
| person | PERSON | unknown | none | 159 | 3-5 | open_class_model_recall_gap | 9 |
| location | LOCATION | unknown | none | 131 | 6-10 | open_class_model_recall_gap | 6 |
| person | PERSON | unknown | none | 173 | 3-5 | open_class_model_recall_gap | 4 |
| location | LOCATION | unknown | none | 143 | 6-10 | open_class_model_recall_gap | 3 |
| location | LOCATION | unknown | none | 153 | 6-10 | open_class_model_recall_gap | 3 |
| person | PERSON | unknown | none | 138 | 6-10 | open_class_model_recall_gap | 2 |



### Model Label Error Analysis

#### False positives by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| street_address | 561 | street_address: 561 | 154: 50, 153: 40, 130: 35, 152: 29, 169: 28 |
| postcode | 224 | zip_code: 224 | 132: 26, 131: 19, 130: 18, 153: 16, 143: 15 |
| last_name | 167 | person: 167 | 153: 30, 154: 16, 169: 14, 143: 12, 144: 9 |
| city | 90 | location: 90 | 152: 13, 169: 13, 148: 12, 177: 9, 149: 7 |
| age | 28 | age: 28 | 171: 14, 154: 4, 149: 2, 158: 2, 130: 1 |
| country | 26 | location: 26 | 149: 8, 148: 6, 144: 1, 146: 1, 147: 1 |
| first_name | 22 | person: 22 | 146: 3, 149: 3, 153: 3, 178: 3, 148: 2 |
| date_time | 21 | date_time: 21 | 172: 13, 157: 8 |
| state | 15 | location: 15 | 152: 4, 148: 3, 177: 3, 147: 2, 149: 2 |
| company_name | 12 | organization: 12 | 148: 7, 144: 1, 149: 1, 153: 1, 158: 1 |

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| location | 90 | location: 90 | 154: 27, 132: 11, 131: 6, 143: 6, 153: 5 |
| person | 74 | person: 74 | 159: 26, 171: 14, 173: 9, 131: 2, 138: 2 |
| phone | 1 | phone: 1 | 143: 1 |

#### Offset mismatches by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| first_name | 158 | person: 158 | 153: 27, 130: 15, 169: 14, 143: 13, 144: 9 |
| city | 22 | location: 22 | 153: 10, 131: 4, 154: 2, 135: 1, 139: 1 |
| phone_number | 13 | phone: 13 | 143: 13 |
| last_name | 8 | person: 8 | 130: 1, 137: 1, 143: 1, 144: 1, 149: 1 |
| country | 1 | location: 1 | 154: 1 |
| state | 1 | location: 1 | 135: 1 |

#### Wrong entity type by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| street_address | 16 | street_address: 16 | 131: 4, 154: 2, 137: 1, 143: 1, 149: 1 |
| postcode | 8 | zip_code: 8 | 143: 3, 149: 3, 139: 2 |
| certificate_license_number | 7 | id: 7 | 154: 2, 171: 2, 143: 1, 158: 1, 179: 1 |
| company_name | 7 | organization: 7 | 159: 4, 141: 2, 160: 1 |
| first_name | 6 | person: 6 | 157: 2, 130: 1, 141: 1, 158: 1, 181: 1 |
| ssn | 5 | us_ssn: 5 | 149: 3, 143: 2 |
| user_name | 3 | handle: 3 | 160: 1, 171: 1, 178: 1 |
| license_plate | 2 | vehicle_id: 2 | 143: 1, 164: 1 |
| customer_id | 1 | id: 1 | 143: 1 |
| date_of_birth | 1 | date_time: 1 | 164: 1 |



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| postcode | postcode | zip_code | omitted:3-5 | 0.95-1.00 | not_required | n/a | 24, 27, 32, 38, 43 | 132, 152, 154, 153, 144 | 214 |
| street_address | street_address | street_address | omitted:11-20 | 0.95-1.00 | not_required | n/a | 9, 24, 27, 32, 37 | 152, 132, 154, 169, 153 | 195 |
| last_name | last_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 32, 38, 43, 45, 53 | 154, 153, 144, 169, 143 | 115 |
| street_address | street_address | street_address | omitted:21+ | 0.95-1.00 | not_required | n/a | 9, 23, 43, 54, 78 | 152, 177, 153, 147, 149 | 106 |
| street_address | street_address | street_address | omitted:3-5 | 0.95-1.00 | not_required | n/a | 9, 24, 32, 38, 45 | 152, 132, 154, 153, 144 | 98 |
| street_address | street_address | street_address | omitted:6-10 | 0.95-1.00 | not_required | n/a | 27, 43, 52, 63, 89 | 152, 153, 130, 143, 154 | 93 |
| street_address | street_address | street_address | omitted:0-2 | 0.95-1.00 | not_required | n/a | 37, 64, 71, 78, 82 | 169, 138, 137, 149, 144 | 69 |
| city | city | location | omitted:6-10 | 0.95-1.00 | not_required | n/a | 27, 53, 78, 193, 253 | 152, 169, 149, 148, 147 | 52 |
| city | city | location | omitted:11-20 | 0.95-1.00 | not_required | n/a | 27, 54, 234, 285, 313 | 152, 147, 148, 169, 177 | 29 |
| age | age | age | omitted:0-2 | 0.95-1.00 | not_required | n/a | 34, 90, 147, 196, 232 | 171, 149, 170, 154, 158 | 27 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | LOCATION | location | AAAAAAA | n/a | not_required | n/a | 32, 89, 290, 362, 529 | 154, 153, 178, 160, 131 | 18 |
| location | LOCATION | location | AAAAAA | n/a | not_required | n/a | 135, 205, 306, 367, 493 | 131, 157, 132, 154, 143 | 14 |
| person | PERSON | person | AA. | n/a | not_required | n/a | 34, 90, 147, 196, 254 | 171 | 14 |
| person | PERSON | person | AAAAAA | n/a | not_required | n/a | 9, 15, 18, 28, 562 | 152, 159, 168, 173 | 13 |
| person | PERSON | person | AAAA | n/a | not_required | n/a | 15, 166, 632, 1039, 1221 | 159, 173, 139 | 10 |
| location | LOCATION | location | AAAAAAAA | n/a | not_required | n/a | 112, 147, 192, 303, 923 | 143, 171, 132, 178, 157 | 8 |
| location | LOCATION | location | AAAAAAAAA | n/a | not_required | n/a | 32, 290, 432, 943, 1039 | 154, 153, 178, 139, 131 | 8 |
| person | PERSON | person | AAAAA | n/a | not_required | n/a | 15, 28, 598, 632, 892 | 159, 173, 181, 168 | 7 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 125, 384, 432, 572, 1557 | 160, 143, 154, 153, 132 | 6 |
| location | LOCATION | location | AAAAA | n/a | not_required | n/a | 1, 421, 775, 1382, 1469 | 178, 181, 160, 154 | 6 |

#### Location false positives by GPE/FAC/LOC model label

No entries.

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | LOCATION | location | AAAAAAA | n/a | not_required | n/a | 32, 89, 362, 586, 1328 | 154 | 8 |
| location | LOCATION | location | AAAAAA | n/a | not_required | n/a | 135, 1106, 1839 | 131 | 3 |
| location | LOCATION | location | AAAA AAAAA | n/a | not_required | n/a | 594, 1648 | 132 | 2 |
| location | LOCATION | location | AAAAA | n/a | not_required | n/a | 1382, 1469 | 154 | 2 |
| location | LOCATION | location | AAAAA | n/a | not_required | n/a | 775, 1826 | 160 | 2 |
| location | LOCATION | location | AA AAAAAAAA | n/a | not_required | n/a | 892 | 181 | 1 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 1557 | 132 | 1 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 384 | 143 | 1 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 572 | 153 | 1 |
| location | LOCATION | location | AAAA | n/a | not_required | n/a | 432 | 154 | 1 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| first_name | first_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 32, 38, 43, 45, 63 | 154, 153, 144, 143, 137 | 92 |
| first_name | first_name | person | omitted:3-5 | 0.95-1.00 | not_required | n/a | 37, 43, 78, 82, 145 | 169, 153, 149, 144, 159 | 58 |
| phone_number | phone_number | phone | omitted:11-20 | 0.95-1.00 | not_required | n/a | 63, 112, 384, 655, 1063 | 143 | 11 |
| city | city | location | omitted:11-20 | 0.95-1.00 | not_required | n/a | 326, 367, 399, 738, 798 | 131, 154, 153, 139 | 10 |
| city | city | location | omitted:6-10 | 0.95-1.00 | not_required | n/a | 686, 908, 913, 922, 1114 | 153, 158, 131, 160 | 8 |
| first_name | first_name | person | omitted:11-20 | 0.95-1.00 | not_required | n/a | 53, 145, 172, 222, 399 | 169, 153, 154 | 5 |
| last_name | last_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 138, 586, 654, 1987, 2077 | 130, 154, 149, 144, 143 | 5 |
| city | city | location | omitted:3-5 | 0.95-1.00 | not_required | n/a | 43, 1554, 1743 | 153, 171, 135 | 3 |
| first_name | first_name | person | omitted:21+ | 0.95-1.00 | not_required | n/a | 716, 1237, 1839 | 131 | 3 |
| last_name | last_name | person | omitted:11-20 | 0.95-1.00 | not_required | n/a | 312, 1938 | 170, 153 | 2 |

#### Wrong entity type rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| postcode | postcode | zip_code | omitted:6-10 | 0.95-1.00 | not_required | n/a | 323, 377, 936, 1031, 1288 | 143, 149, 139 | 8 |
| street_address | street_address | street_address | omitted:11-20 | 0.95-1.00 | not_required | n/a | 716, 1123, 1243, 1410, 1523 | 131, 178, 154, 158 | 6 |
| street_address | street_address | street_address | omitted:21+ | 0.95-1.00 | not_required | n/a | 326, 511, 602, 1482, 1816 | 131, 137, 160, 158 | 6 |
| first_name | first_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 102, 574, 986, 2055, 2059 | 158, 181, 157, 141, 130 | 5 |
| certificate_license_number | certificate_license_number | id | omitted:11-20 | 0.95-1.00 | not_required | n/a | 1170, 1318, 1427, 1672 | 158, 154, 143, 171 | 4 |
| ssn | ssn | us_ssn | omitted:11-20 | 0.95-1.00 | not_required | n/a | 78, 165, 1073, 1943 | 149, 143 | 4 |
| certificate_license_number | certificate_license_number | id | omitted:6-10 | 0.95-1.00 | not_required | n/a | 362, 640, 2085 | 154, 179, 171 | 3 |
| company_name | company_name | organization | omitted:11-20 | 0.95-1.00 | not_required | n/a | 159, 368, 435 | 159, 160, 141 | 3 |
| company_name | company_name | organization | omitted:21+ | 0.95-1.00 | not_required | n/a | 15, 28, 938 | 159 | 3 |
| license_plate | license_plate | vehicle_id | omitted:11-20 | 0.95-1.00 | not_required | n/a | 859, 1827 | 164, 143 | 2 |



### Structured Model Error Rows

Values are sanitized; rows include Presidio-Research-style error context for tuning.

| Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| FN | location | O | location | LOCATION | AAAAA | n/a | not_required | n/a | n/a | n/a | 1 | 178 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 32 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 32 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAA-AAAAAA | n/a | not_required | n/a | n/a | n/a | 46 | 157 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 89 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 112 | 143 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAA | n/a | not_required | n/a | n/a | n/a | 125 | 160 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 135 | 131 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA AAA | n/a | not_required | n/a | n/a | n/a | 145 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 147 | 171 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 192 | 132 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 205 | 157 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 290 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 290 | 153 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 303 | 178 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 306 | 132 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 362 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAAA | n/a | not_required | n/a | n/a | n/a | 367 | 154 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAAA AAAA | n/a | not_required | n/a | n/a | n/a | 369 | 132 | 0.0000 | location not detected |
| FN | location | O | location | LOCATION | AAAA | n/a | not_required | n/a | n/a | n/a | 384 | 143 | 0.0000 | location not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 169 | 16 | 0.0137 | 0.5000 | 0.0267 | 0.0617 | 1 | 72 | 1 |
| 144 | 11 | 0.0222 | 1.0000 | 0.0435 | 0.1020 | 1 | 44 | 0 |
| 170 | 16 | 0.0714 | 0.3333 | 0.1176 | 0.1923 | 1 | 13 | 2 |
| 131 | 13 | 0.0851 | 0.3333 | 0.1356 | 0.2105 | 4 | 43 | 8 |
| 154 | 23 | 0.1271 | 0.3409 | 0.1852 | 0.2551 | 15 | 103 | 29 |
| 153 | 16 | 0.1892 | 0.8077 | 0.3066 | 0.4884 | 21 | 90 | 5 |
| 152 | 19 | 0.2195 | 0.9474 | 0.3564 | 0.5696 | 18 | 64 | 1 |
| 157 | 17 | 0.2963 | 0.5714 | 0.3902 | 0.4819 | 8 | 19 | 6 |
| 158 | 15 | 0.2500 | 1.0000 | 0.4000 | 0.6250 | 10 | 30 | 0 |
| 132 | 27 | 0.3258 | 0.7963 | 0.4624 | 0.6178 | 43 | 89 | 11 |
| 130 | 18 | 0.3241 | 0.9459 | 0.4828 | 0.6836 | 35 | 73 | 2 |
| 149 | 15 | 0.3362 | 0.9750 | 0.5000 | 0.7065 | 39 | 77 | 1 |
| 143 | 19 | 0.4000 | 0.8276 | 0.5393 | 0.6818 | 48 | 72 | 10 |
| 172 | 14 | 0.3721 | 1.0000 | 0.5424 | 0.7477 | 16 | 27 | 0 |
| 137 | 14 | 0.3778 | 1.0000 | 0.5484 | 0.7522 | 17 | 28 | 0 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| street_address | 40 | 64 | n/a | street_address |
| street_address | 65 | 68 | n/a | street_address |
| street_address | 74 | 77 | n/a | street_address |
| street_address | 78 | 94 | n/a | street_address |
| street_address | 22 | 62 | n/a | street_address |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location | 30 | 35 | n/a | LOCATION |
| person | 20 | 27 | n/a | PERSON |
| person | 41 | 47 | n/a | PERSON |
| person | 33 | 39 | n/a | PERSON |
| person | 25 | 31 | n/a | PERSON |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/person | 4/4 | 19/11 | n/a | PERSON/first_name |
| person/person | 9/9 | 26/14 | n/a | PERSON/first_name |
| person/person | 34/34 | 50/42 | n/a | PERSON/first_name |
| person/person | 1/0 | 20/10 | n/a | PERSON/first_name |
| location/location | 83/83 | 92/87 | n/a | LOCATION/city |

#### Wrong entity type

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location/handle | 54/54 | 61/61 | n/a | LOCATION/user_name |
| person/organization | 52/25 | 60/60 | n/a | PERSON/company_name |
| person/organization | 56/38 | 62/62 | n/a | PERSON/company_name |
| phone/us_ssn | 80/80 | 92/92 | n/a | PHONE_NUMBER/ssn |
| location/person | 62/62 | 71/71 | n/a | LOCATION/first_name |



## Limitations

- Presidio-Research template_heldout_full compatibility report for the optional native privacy-filter adapter.
- This profile uses privacy-filter alone so it can be compared directly against a Python privacy-filter reference run.
- The profile is opt-in and experimental. It is not a default recognizer path.
