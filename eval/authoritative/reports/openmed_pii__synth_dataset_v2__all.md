# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_synth_dataset_v2_privacy_filter_native_full_authoritative_openmed_final_common_default_r1
- Adapter: Obscura.Recognizer.PrivacyFilter.Native
- Profile: privacy_filter_native
- Dataset: synth_dataset_v2
- Samples: 1500

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.3306 |
| Recall | 0.7920 |
| F1 | 0.4665 |
| F2 | 0.6192 |
| True positives | 891 |
| False positives | 1804 |
| False negatives | 234 |
| Offset mismatches | 362 |
| Wrong entity type | 88 |
| Unsupported expected spans | 1288 |



### IoU Span Metrics

| Metric | Value |
| --- | ---: |
| IoU threshold | 0.9000 |
| Precision | 0.2912 |
| Recall | 0.5946 |
| F1 | 0.3909 |
| F2 | 0.4920 |
| True positives | 896 |
| False positives | 2181 |
| False negatives | 611 |
| Wrong entity type | 68 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 119 |
| Predicted adjacent merges | 742 |
| Normalized IoU precision | 0.4697 |
| Normalized IoU recall | 0.7889 |
| Normalized IoU F1 | 0.5888 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| street_address | 636 | model_false_positive: 587, model_boundary_fragment: 49 |
| person | 413 | model_open_class_false_positive: 407, model_boundary_fragment: 6 |
| location | 245 | model_open_class_false_positive: 224, model_boundary_fragment: 21 |
| zip_code | 238 | model_false_positive: 238 |
| age | 77 | model_boundary_fragment: 77 |
| organization | 68 | model_open_class_false_positive: 68 |
| date_time | 50 | model_false_positive: 50 |
| url | 37 | model_false_positive: 37 |
| id | 15 | model_false_positive: 15 |
| account_number | 12 | model_false_positive: 12 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 137 | open_class_model_recall_gap: 137 |
| person | 97 | open_class_model_recall_gap: 97 |

#### Wrong entity type

| Entity | Count | Likely causes |
| --- | ---: | --- |
| person | 34 | model_label_confusion: 34 |
| location | 32 | model_label_confusion: 32 |
| phone | 18 | model_label_confusion: 18 |
| email | 3 | model_label_confusion: 3 |
| credit_card | 1 | model_label_confusion: 1 |

#### Wrong Entity Matrix

| Expected | Predicted | Count |
| --- | --- | ---: |
| location | person | 14 |
| person | organization | 14 |
| phone | us_ssn | 13 |
| person | location | 12 |
| location | id | 7 |
| location | street_address | 6 |
| person | handle | 5 |
| location | organization | 4 |
| email | person | 3 |
| person | street_address | 3 |



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | last_name | privacy_filter_native | last_name | 106 | 6-10 | model_open_class_false_positive | 13 |
| age | age | privacy_filter_native | age | 201 | 0-2 | model_boundary_fragment | 10 |
| age | age | privacy_filter_native | age | 206 | 0-2 | model_boundary_fragment | 9 |
| organization | company_name | privacy_filter_native | company_name | 191 | 6-10 | model_open_class_false_positive | 9 |
| age | age | privacy_filter_native | age | 171 | 0-2 | model_boundary_fragment | 8 |
| street_address | street_address | privacy_filter_native | street_address | 49 | 3-5 | model_false_positive | 7 |
| street_address | street_address | privacy_filter_native | street_address | 169 | 3-5 | model_false_positive | 6 |
| street_address | street_address | privacy_filter_native | street_address | 50 | 11-20 | model_false_positive | 5 |
| street_address | street_address | privacy_filter_native | street_address | 87 | 3-5 | model_false_positive | 4 |
| person | last_name | privacy_filter_native | last_name | 197 | 11-20 | model_open_class_false_positive | 3 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | PERSON | unknown | none | 120 | 6-10 | open_class_model_recall_gap | 8 |
| location | GPE | unknown | none | 22 | 6-10 | open_class_model_recall_gap | 7 |
| location | GPE | unknown | none | 21 | 6-10 | open_class_model_recall_gap | 5 |
| person | PERSON | unknown | none | 159 | 3-5 | open_class_model_recall_gap | 5 |
| location | GPE | unknown | none | 118 | 6-10 | open_class_model_recall_gap | 4 |
| location | GPE | unknown | none | 131 | 3-5 | open_class_model_recall_gap | 4 |
| location | GPE | unknown | none | 154 | 6-10 | open_class_model_recall_gap | 4 |
| person | PERSON | unknown | none | 159 | 6-10 | open_class_model_recall_gap | 4 |
| location | GPE | unknown | none | 132 | 11-20 | open_class_model_recall_gap | 3 |
| location | GPE | unknown | none | 155 | 6-10 | open_class_model_recall_gap | 3 |



### Model Label Error Analysis

#### False positives by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| street_address | 636 | street_address: 636 | 130: 26, 49: 20, 137: 18, 139: 12, 148: 10 |
| last_name | 343 | person: 343 | 153: 16, 106: 15, 167: 15, 197: 9, 10: 4 |
| postcode | 238 | zip_code: 238 | 130: 12, 132: 12, 162: 10, 129: 7, 147: 7 |
| city | 167 | location: 167 | 115: 10, 145: 8, 30: 8, 147: 6, 87: 5 |
| age | 77 | age: 77 | 201: 10, 206: 9, 171: 8, 108: 3, 117: 2 |
| first_name | 70 | person: 70 | 109: 7, 116: 6, 106: 4, 115: 4, 126: 2 |
| company_name | 68 | organization: 68 | 191: 10, 121: 7, 115: 6, 118: 4, 120: 4 |
| country | 55 | location: 55 | 177: 5, 49: 5, 145: 3, 30: 3, 124: 2 |
| url | 37 | url: 37 | 188: 13, 81: 10, 80: 7, 83: 7 |
| date | 35 | date_time: 35 | 79: 11, 76: 10, 61: 7, 157: 5, 118: 1 |

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| location | 137 | location: 137 | 131: 6, 151: 6, 118: 5, 132: 4, 189: 4 |
| person | 97 | person: 97 | 120: 12, 159: 10, 173: 7, 101: 4, 104: 4 |

#### Offset mismatches by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| first_name | 337 | person: 337 | 153: 15, 167: 15, 197: 14, 106: 10, 10: 4 |
| city | 9 | location: 9 | 153: 5, 115: 1, 126: 1, 154: 1, 158: 1 |
| country | 7 | location: 7 | 118: 7 |
| phone_number | 5 | phone: 5 | 143: 4, 149: 1 |
| last_name | 3 | person: 3 | 154: 1, 173: 1, 197: 1 |
| email | 1 | email: 1 | 31: 1 |

#### Wrong entity type by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| company_name | 18 | organization: 18 | 120: 9, 126: 1, 141: 1, 174: 1, 181: 1 |
| first_name | 16 | person: 16 | 157: 2, 174: 2, 132: 1, 137: 1, 181: 1 |
| ssn | 14 | us_ssn: 14 | 150: 3, 164: 3, 44: 3, 12: 2, 149: 2 |
| city | 12 | location: 12 | 122: 4, 95: 3, 105: 1, 113: 1, 153: 1 |
| street_address | 9 | street_address: 9 | 191: 3, 159: 2, 126: 1, 155: 1, 158: 1 |
| certificate_license_number | 7 | id: 7 | 127: 2, 126: 1, 139: 1, 155: 1, 179: 1 |
| user_name | 5 | handle: 5 | 10: 1, 159: 1, 184: 1, 58: 1, 76: 1 |
| postcode | 3 | zip_code: 3 | 129: 1, 149: 1, 150: 1 |
| license_plate | 2 | vehicle_id: 2 | 149: 1, 164: 1 |
| customer_id | 1 | id: 1 | 143: 1 |



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| last_name | last_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 2, 6, 8, 9, 14 | 106, 104, 199, 43, 151 | 245 |
| postcode | postcode | zip_code | omitted:3-5 | 0.95-1.00 | not_required | n/a | 0, 14, 22, 33, 37 | 87, 151, 130, 148, 30 | 224 |
| street_address | street_address | street_address | omitted:11-20 | 0.95-1.00 | not_required | n/a | 22, 24, 51, 58, 61 | 130, 137, 139, 110, 49 | 180 |
| street_address | street_address | street_address | omitted:21+ | 0.95-1.00 | not_required | n/a | 0, 14, 29, 37, 49 | 87, 151, 148, 30, 188 | 160 |
| street_address | street_address | street_address | omitted:3-5 | 0.95-1.00 | not_required | n/a | 24, 33, 51, 56, 76 | 137, 148, 139, 49, 192 | 151 |
| street_address | street_address | street_address | omitted:6-10 | 0.95-1.00 | not_required | n/a | 22, 37, 49, 52, 77 | 130, 30, 188, 134, 143 | 96 |
| city | city | location | omitted:6-10 | 0.95-1.00 | not_required | n/a | 0, 33, 37, 49, 52 | 87, 148, 30, 188, 42 | 92 |
| age | age | age | omitted:0-2 | 0.95-1.00 | not_required | n/a | 13, 36, 39, 71, 105 | 206, 202, 208, 207, 171 | 77 |
| last_name | last_name | person | omitted:3-5 | 0.95-1.00 | not_required | n/a | 51, 126, 160, 225, 248 | 139, 78, 3, 113, 43 | 53 |
| city | city | location | omitted:11-20 | 0.95-1.00 | not_required | n/a | 266, 275, 322, 346, 369 | 147, 178, 3, 46, 140 | 51 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | location | AAAAAAA | n/a | not_required | n/a | 3, 242, 262, 273, 297 | 118, 23, 129, 22, 189 | 31 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 11, 39, 41, 89, 202 | 22, 202, 112, 209, 118 | 29 |
| person | PERSON | person | AAAAAAA | n/a | not_required | n/a | 79, 175, 315, 316, 344 | 159, 97, 101, 173, 125 | 19 |
| person | PERSON | person | AAAAAA | n/a | not_required | n/a | 19, 23, 93, 394, 560 | 99, 120, 159, 139, 98 | 15 |
| location | GPE | location | AAAAA | n/a | not_required | n/a | 81, 91, 100, 293, 487 | 118, 137, 179, 189, 115 | 14 |
| person | PERSON | person | AAAAA | n/a | not_required | n/a | 878, 900, 902, 905, 1043 | 173, 86, 136, 120, 138 | 13 |
| location | GPE | location | AAAAAAAAA | n/a | not_required | n/a | 117, 135, 402, 407, 469 | 126, 209, 119, 100, 155 | 9 |
| person | PERSON | person | AAAA | n/a | not_required | n/a | 15, 194, 308, 375, 672 | 200, 125, 102, 101, 38 | 9 |
| location | GPE | location | AAA | n/a | not_required | n/a | 54, 451, 504, 516, 693 | 151, 131 | 6 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 110, 528, 705, 836, 931 | 171, 174, 178, 189 | 5 |

#### Location false positives by GPE/FAC/LOC model label

No entries.

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 382, 423, 495, 1446 | 21 | 4 |
| location | GPE | location | AAA | n/a | not_required | n/a | 504, 693, 877 | 131 | 3 |
| location | GPE | location | AAA | n/a | not_required | n/a | 54, 451, 516 | 151 | 3 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 11, 202, 1240 | 22 | 3 |
| location | GPE | location | AAA AAAAAAA | n/a | not_required | n/a | 302, 340 | 153 | 2 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 705, 931 | 178 | 2 |
| location | GPE | location | AAAAAA | n/a | not_required | n/a | 41, 436 | 112 | 2 |
| location | GPE | location | AA | n/a | not_required | n/a | 159 | 131 | 1 |
| location | GPE | location | AA | n/a | not_required | n/a | 14 | 151 | 1 |
| location | GPE | location | AAAA | n/a | not_required | n/a | 110 | 171 | 1 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| first_name | first_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 2, 6, 8, 9, 16 | 106, 104, 199, 43, 29 | 196 |
| first_name | first_name | person | omitted:3-5 | 0.95-1.00 | not_required | n/a | 14, 17, 46, 50, 64 | 151, 29, 95, 184, 105 | 122 |
| first_name | first_name | person | omitted:11-20 | 0.95-1.00 | not_required | n/a | 159, 381, 498, 535, 572 | 131, 111, 28, 29, 116 | 16 |
| country | country | location | omitted:11-20 | 0.95-1.00 | not_required | n/a | 163, 234, 301, 748, 1351 | 118 | 6 |
| phone_number | phone_number | phone | omitted:11-20 | 0.95-1.00 | not_required | n/a | 82, 252, 396, 780, 1322 | 143, 149 | 5 |
| city | city | location | omitted:6-10 | 0.95-1.00 | not_required | n/a | 863, 873, 1126, 1203 | 153, 158 | 4 |
| city | city | location | omitted:11-20 | 0.95-1.00 | not_required | n/a | 302, 486, 873 | 153, 154 | 3 |
| first_name | first_name | person | omitted:21+ | 0.95-1.00 | not_required | n/a | 504, 1122 | 131, 116 | 2 |
| last_name | last_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 917, 1385 | 197, 173 | 2 |
| city | city | location | omitted:21+ | 0.95-1.00 | not_required | n/a | 192 | 115 | 1 |

#### Wrong entity type rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| company_name | company_name | organization | omitted:11-20 | 0.95-1.00 | not_required | n/a | 23, 93, 124, 271, 359 | 120, 93, 174, 126, 141 | 10 |
| first_name | first_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | 48, 157, 417, 470, 699 | 24, 137, 157, 174, 31 | 10 |
| ssn | ssn | us_ssn | omitted:11-20 | 0.95-1.00 | not_required | n/a | 223, 319, 573, 678, 886 | 44, 26, 150, 12, 164 | 10 |
| city | city | location | omitted:6-10 | 0.95-1.00 | not_required | n/a | 494, 526, 545, 954, 992 | 181, 122, 36 | 6 |
| street_address | street_address | street_address | omitted:11-20 | 0.95-1.00 | not_required | n/a | 130, 255, 387, 624, 783 | 209, 155, 126, 191, 159 | 6 |
| city | city | location | omitted:11-20 | 0.95-1.00 | not_required | n/a | 62, 205, 863, 1030, 1303 | 95, 153, 113 | 5 |
| certificate_license_number | certificate_license_number | id | omitted:11-20 | 0.95-1.00 | not_required | n/a | 278, 913, 1227, 1263 | 198, 179, 126, 127 | 4 |
| company_name | company_name | organization | omitted:21+ | 0.95-1.00 | not_required | n/a | 394, 735, 905, 1457 | 120 | 4 |
| ssn | ssn | us_ssn | omitted:6-10 | 0.95-1.00 | not_required | n/a | 241, 252, 738, 1130 | 164, 149, 150, 12 | 4 |
| certificate_license_number | certificate_license_number | id | omitted:6-10 | 0.95-1.00 | not_required | n/a | 58, 564, 742 | 139, 155, 127 | 3 |



### Structured Model Error Rows

Values are sanitized; rows include Presidio-Research-style error context for tuning.

| Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| FN | location | O | location | GPE | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 3 | 118 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 11 | 22 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AA | n/a | not_required | n/a | n/a | n/a | 14 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 14 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 39 | 202 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 41 | 112 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAA | n/a | not_required | n/a | n/a | n/a | 54 | 151 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAA | n/a | not_required | n/a | n/a | n/a | 81 | 118 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 89 | 209 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAA | n/a | not_required | n/a | n/a | n/a | 91 | 137 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAA AAA AAAA | n/a | not_required | n/a | n/a | n/a | 92 | 157 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAA | n/a | not_required | n/a | n/a | n/a | 100 | 179 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAA | n/a | not_required | n/a | n/a | n/a | 110 | 171 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 117 | 126 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAAA | n/a | not_required | n/a | n/a | n/a | 135 | 209 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAA AAAAAAAA | n/a | not_required | n/a | n/a | n/a | 141 | 23 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAAAA A | n/a | not_required | n/a | n/a | n/a | 149 | 137 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AA | n/a | not_required | n/a | n/a | n/a | 159 | 131 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAA | n/a | not_required | n/a | n/a | n/a | 202 | 22 | 0.0000 | location not detected |
| FN | location | O | location | GPE | AAAAAAA | n/a | not_required | n/a | n/a | n/a | 242 | 23 | 0.0000 | location not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 114 | 4 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 4 | 4 |
| 118 | 12 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 5 | 5 |
| 144 | 7 | 0.0690 | 0.5000 | 0.1212 | 0.2222 | 2 | 27 | 2 |
| 85 | 8 | 0.0769 | 1.0000 | 0.1429 | 0.2941 | 1 | 12 | 0 |
| 131 | 4 | 0.1250 | 0.2222 | 0.1600 | 0.1923 | 2 | 14 | 7 |
| 22 | 11 | 1.0000 | 0.0909 | 0.1667 | 0.1111 | 1 | 0 | 10 |
| 106 | 6 | 0.0952 | 1.0000 | 0.1739 | 0.3448 | 2 | 19 | 0 |
| 197 | 3 | 0.1000 | 0.6667 | 0.1739 | 0.3125 | 2 | 18 | 1 |
| 113 | 6 | 0.1429 | 0.2500 | 0.1818 | 0.2174 | 1 | 6 | 3 |
| 48 | 10 | 0.1000 | 1.0000 | 0.1818 | 0.3571 | 1 | 9 | 0 |
| 169 | 9 | 0.1081 | 0.8000 | 0.1905 | 0.3509 | 4 | 33 | 1 |
| 158 | 4 | 0.1250 | 0.5000 | 0.2000 | 0.3125 | 1 | 7 | 1 |
| 28 | 11 | 0.1250 | 1.0000 | 0.2222 | 0.4167 | 1 | 7 | 0 |
| 154 | 8 | 0.1489 | 0.4667 | 0.2258 | 0.3271 | 7 | 40 | 8 |
| 115 | 8 | 0.1471 | 0.6250 | 0.2381 | 0.3788 | 5 | 29 | 3 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| street_address | 26 | 52 | n/a | street_address |
| location | 53 | 63 | n/a | city |
| location | 66 | 68 | n/a | state |
| location | 70 | 77 | n/a | country |
| zip_code | 78 | 83 | n/a | postcode |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| location | 158 | 165 | n/a | GPE |
| person | 11 | 23 | n/a | PERSON |
| location | 24 | 30 | n/a | GPE |
| location | 81 | 83 | n/a | GPE |
| location | 64 | 76 | n/a | GPE |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/person | 177/177 | 197/184 | n/a | PERSON/first_name |
| person/person | 0/0 | 21/10 | n/a | PERSON/first_name |
| person/person | 124/124 | 142/132 | n/a | PERSON/first_name |
| person/person | 89/89 | 104/97 | n/a | PERSON/first_name |
| person/person | 43/43 | 58/50 | n/a | PERSON/first_name |

#### Wrong entity type

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/organization | 78/67 | 85/85 | n/a | PERSON/company_name |
| person/organization | 67/67 | 72/72 | n/a | PERSON/company_name |
| location/person | 33/33 | 48/38 | n/a | GPE/first_name |
| location/person | 0/0 | 7/7 | n/a | GPE/first_name |
| location/id | 53/53 | 63/63 | n/a | GPE/certificate_license_number |



## Limitations

- Presidio-Research full compatibility report for the optional native privacy-filter adapter.
- This profile uses privacy-filter alone so it can be compared directly against a Python privacy-filter reference run.
- The profile is opt-in and experimental. It is not a default recognizer path.
