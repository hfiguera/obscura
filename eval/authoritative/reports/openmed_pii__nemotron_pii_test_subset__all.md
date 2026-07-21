# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_nemotron_pii_test_subset_privacy_filter_native_full_authoritative_openmed_final_common_default_r1
- Adapter: Obscura.Recognizer.PrivacyFilter.Native
- Profile: privacy_filter_native
- Dataset: nemotron_pii_test_subset
- Samples: 500

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.4928 |
| Recall | 0.9825 |
| F1 | 0.6564 |
| F2 | 0.8196 |
| True positives | 1680 |
| False positives | 1729 |
| False negatives | 30 |
| Offset mismatches | 13 |
| Wrong entity type | 2 |
| Unsupported expected spans | 2361 |



### IoU Span Metrics

| Metric | Value |
| --- | ---: |
| IoU threshold | 0.9000 |
| Precision | 0.4928 |
| Recall | 0.9785 |
| F1 | 0.6555 |
| F2 | 0.8174 |
| True positives | 1687 |
| False positives | 1736 |
| False negatives | 37 |
| Wrong entity type | 1 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 297 |
| Predicted adjacent merges | 314 |
| Normalized IoU precision | 0.4492 |
| Normalized IoU recall | 0.9790 |
| Normalized IoU F1 | 0.6158 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| date_time | 565 | model_false_positive: 565 |
| organization | 244 | model_open_class_false_positive: 244 |
| id | 176 | model_false_positive: 176 |
| secret | 102 | model_false_positive: 102 |
| account_number | 98 | model_false_positive: 98 |
| street_address | 95 | model_false_positive: 95 |
| financial_id | 86 | model_false_positive: 86 |
| handle | 67 | model_false_positive: 67 |
| patient_id | 52 | model_false_positive: 52 |
| age | 48 | model_boundary_fragment: 48 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| person | 16 | open_class_model_recall_gap: 16 |
| location | 10 | open_class_model_recall_gap: 10 |
| credit_card | 2 | recognizer_recall_gap: 2 |
| email | 2 | recognizer_recall_gap: 2 |

#### Wrong entity type

| Entity | Count | Likely causes |
| --- | ---: | --- |
| location | 1 | model_label_confusion: 1 |
| person | 1 | model_label_confusion: 1 |

#### Wrong Entity Matrix

| Expected | Predicted | Count |
| --- | --- | ---: |
| location | person | 1 |
| person | handle | 1 |



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| date_time | date | privacy_filter_native | date | test:Property:Property Improvement Plan:structured:us | 6-10 | model_false_positive | 12 |
| date_time | date | privacy_filter_native | date | test:Consulting:Service Proposal:structured:us | 6-10 | model_false_positive | 10 |
| date_time | time | privacy_filter_native | time | test:Human Resources:Training Workshop Agenda:unstructured:us | 11-20 | model_false_positive | 10 |
| organization | company_name | privacy_filter_native | company_name | test:Advertising:Ad Content Guidelines:structured:us | 6-10 | model_open_class_false_positive | 10 |
| date_time | date | privacy_filter_native | date | test:Human Resources:Performance Improvement Plan:structured:us | 6-10 | model_false_positive | 9 |
| date_time | date | privacy_filter_native | date | test:Public Safety:Emergency Medical Supplies Distribution:structured:us | 6-10 | model_false_positive | 9 |
| organization | company_name | privacy_filter_native | company_name | test:Marketing:User Agreement:structured:us | 21+ | model_open_class_false_positive | 9 |
| date_time | date | privacy_filter_native | date | test:Advertising:Campaign Strategy:structured:us | 6-10 | model_false_positive | 8 |
| date_time | date | privacy_filter_native | date | test:Marketing:Budget Proposal:structured:us | 6-10 | model_false_positive | 8 |
| organization | company_name | privacy_filter_native | company_name | test:Environmental:Environmental Compliance Audit:structured:us | 11-20 | model_open_class_false_positive | 8 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| credit_card | cvv | unknown | none | test:Insurance:Life Insurance Policy:structured:us | 3-5 | recognizer_recall_gap | 2 |
| location | country | unknown | none | test:Travel:Travel Safety Notification:structured:us | 3-5 | open_class_model_recall_gap | 2 |
| person | first_name | unknown | none | test:Information Technology:Support Ticket:unstructured:us | 0-2 | open_class_model_recall_gap | 2 |
| email | email | unknown | none | test:Life:Claim Investigation Report:structured:us | 6-10 | recognizer_recall_gap | 1 |
| email | email | unknown | none | test:Product:Customer Service Policy:unstructured:us | 6-10 | recognizer_recall_gap | 1 |
| location | city | unknown | none | test:Casualty:Damage Assessment:unstructured:us | 11-20 | open_class_model_recall_gap | 1 |
| location | city | unknown | none | test:Social Science:Social Cohesion Survey:unstructured:us | 6-10 | open_class_model_recall_gap | 1 |
| location | city | unknown | none | test:Sports:Event Planning Document:unstructured:us | 6-10 | open_class_model_recall_gap | 1 |
| location | city | unknown | none | test:Sports:Team Policy Manual:unstructured:us | 6-10 | open_class_model_recall_gap | 1 |
| location | county | unknown | none | test:Life:Beneficiary Release Form:structured:us | 6-10 | open_class_model_recall_gap | 1 |



### Model Label Error Analysis

#### False positives by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| date | 362 | date_time: 362 | test:Property:Property Improvement Plan:structured:us: 12, test:Consulting:Service Proposal:structured:us: 10, test:Human Resources:Performance Improvement Plan:structured:us: 9, test:Public Safety:Emergency Medical Supplies Distribution:structured:us: 9, test:Advertising:Campaign Strategy:structured:us: 8 |
| company_name | 244 | organization: 244 | test:Advertising:Ad Content Guidelines:structured:us: 10, test:Marketing:User Agreement:structured:us: 9, test:Environmental:Environmental Compliance Audit:structured:us: 8, test:Sports:Sponsorship Agreement:structured:us: 7, test:Environmental:Environmental Impact Analysis:structured:us: 6 |
| time | 101 | date_time: 101 | test:Human Resources:Training Workshop Agenda:unstructured:us: 11, test:Elections:Voter Outreach Materials:structured:us: 5, test:Fitness:Exercise Journal:structured:us: 4, test:Sports:Highlight Reels:structured:us: 3, test:Banking:Transaction Record:structured:us: 2 |
| account_number | 98 | account_number: 98 | test:User Account and Transaction Services:Security Audit Report:structured:us: 5, test:Credit:Credit Card Agreement:structured:us: 3, test:Banking:Debit Authorization:structured:us: 2, test:Banking:Financial Advice:structured:us: 2, test:Banking:Investment Agreement:unstructured:us: 2 |
| street_address | 95 | street_address: 95 | test:Access Control Systems:Background Check Authorization Form:structured:us: 2, test:Access Control Systems:Health Insurance Enrollment Form:unstructured:us: 2, test:Marketing:guest checkout record:structured:us: 2, test:Mortgage:Affidavit of No Prior Mortgage:structured:us: 2, test:Property:Property Improvement Plan:structured:us: 2 |
| customer_id | 79 | id: 79 | test:Brokerage:Investment Process:structured:us: 3, test:Banking:Debit Authorization:structured:us: 2, test:Life:Policy Cancellation Notice:structured:us: 2, test:Product:Customer FAQ:structured:us: 2, test:Services:transcribed phone order:structured:us: 2 |
| date_of_birth | 69 | date_time: 69 | test:Access Control Systems:Health Insurance Enrollment Form:unstructured:us: 2, test:Disability:Disability Income Statement:unstructured:us: 2, test:Elections:Voter Registration Form:structured:us: 2, test:Investment:consumer lending profile:unstructured:us: 2, test:Life:Beneficiary Release Form:structured:us: 2 |
| user_name | 67 | handle: 67 | test:User Account and Transaction Services:Security Audit Report:structured:us: 4, test:Advertising:Ad Content Guidelines:structured:us: 3, test:Advertising:biometric phenotyping data file:structured:us: 3, test:Product:User Workflow Diagram:structured:us: 3, test:User Account and Transaction Services:Credit Card Authorization Form:structured:us: 3 |
| bank_routing_number | 61 | financial_id: 61 | test:Social Science:Gender Equality Report:structured:us: 4, test:Insurance:Disability Claim:structured:us: 2, test:Insurance:Premium Invoice:structured:us: 2, test:Access Control Systems:Government Benefits Application:unstructured:us: 1, test:Banking:Budget Plan:structured:us: 1 |
| medical_record_number | 52 | patient_id: 52 | test:Access Control Systems:Medical History Form:structured:us: 3, test:Casualty:Claim Form:structured:us: 3, test:Life:Claim Investigation Report:structured:us: 3, test:Disability:Disability Claim Denial Letter:structured:us: 2, test:Disability:Disability Insurance Terms:structured:us: 2 |

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| person | 16 | person: 16 | test:Elections:Voter Outreach Materials:structured:us: 2, test:Information Technology:Support Ticket:unstructured:us: 2, test:Banking:Customer Agreement:unstructured:us: 1, test:Consulting:Data Analysis Report:structured:us: 1, test:Credit:Account Statement:structured:us: 1 |
| location | 10 | location: 10 | test:Travel:Travel Safety Notification:structured:us: 2, test:Casualty:Damage Assessment:structured:us: 1, test:Casualty:Damage Assessment:unstructured:us: 1, test:Life:Beneficiary Release Form:structured:us: 1, test:Mortgage:Affidavit of No Prior Mortgage:structured:us: 1 |
| credit_card | 2 | credit_card: 2 | test:Insurance:Life Insurance Policy:structured:us: 2 |
| email | 2 | email: 2 | test:Life:Claim Investigation Report:structured:us: 1, test:Product:Customer Service Policy:unstructured:us: 1 |

#### Offset mismatches by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| url | 5 | url: 5 | test:Brokerage:Market Analysis:unstructured:us: 1, test:Consulting:Data Analysis Report:structured:us: 1, test:Health:Health Education Brochure:structured:us: 1, test:Information Technology:Support Ticket:unstructured:us: 1, test:Investment:Compliance Document:unstructured:us: 1 |
| first_name | 3 | person: 3 | test:Credit:Account Statement:structured:us: 1, test:Disability:Insurance Application:unstructured:us: 1, test:Sports:Coach Biography:structured:us: 1 |
| coordinate | 2 | location: 2 | test:Access Control Systems:Biometric Border Screening Document:unstructured:us: 1, test:Insurance:Incident Report:unstructured:us: 1 |
| ipv6 | 1 | ip_address: 1 | test:Marketing:Website Usability:structured:us: 1 |
| last_name | 1 | person: 1 | test:Consulting:Data Analysis Report:structured:us: 1 |
| state | 1 | location: 1 | test:Life:Beneficiary Release Form:structured:us: 1 |

#### Wrong entity type by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| first_name | 1 | person: 1 | test:Social Science:Migration Patterns Study:unstructured:us: 1 |
| user_name | 1 | handle: 1 | test:Product:Author Interview:structured:us: 1 |



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| date | date | date_time | omitted:6-10 | 0.95-1.00 | not_required | n/a | 3e3f8e5a1e064d5ba44271375c59f1cb, 9181f53eb3f34f3cb0b5cbdec91c94e5, 05744eeb0a084b068d649aeb4a369923, 91060f2d1fab4793b062649755c02854, 16c97912f8414d2c9e6ffef23194144f | test:Travel:Ticket:structured:us, test:Investment:Tax Form:structured:us, test:Life:Death Certificate:unstructured:us, test:Brokerage:Account Activity Report:unstructured:us, test:User Account and Transaction Services:Temporary Password Notification:structured:us | 325 |
| company_name | company_name | organization | omitted:21+ | 0.95-1.00 | not_required | n/a | 81601f5b701344a4b7f6cccaf9ceea60, 24ad19b70a0f48479db07e858e710078, 0a415c7b971d42bbbb5d7deaf3553c57, 2aff10775aa2422abaf74801f0c03920, 7c90b4cb2cdd443ea964ab3e16706fdd | test:Advertising:Email Ad Script:unstructured:us, test:Insurance:Insurance Policy Summary:structured:us, test:Environmental:Environmental Compliance Checklist:unstructured:us, test:Investment:Investment Universe:unstructured:us, test:Investment:Investment Proposal:unstructured:us | 118 |
| company_name | company_name | organization | omitted:11-20 | 0.95-1.00 | not_required | n/a | 1214a8a775d74fa0bfb5d306390551b7, eb8733ff06d943e5b776450e346a653f, 309059894d1341a2ac525e91f328085f, 81601f5b701344a4b7f6cccaf9ceea60, b750573feb60456ea17c52ee9093b3f8 | test:User Account and Transaction Services:Legal Correspondence Cover Page:unstructured:us, test:Health:Health Insurance Card:unstructured:us, test:Sports:Season Summary:unstructured:us, test:Advertising:Email Ad Script:unstructured:us, test:Investment:Investment Terms:structured:us | 101 |
| street_address | street_address | street_address | omitted:11-20 | 0.95-1.00 | not_required | n/a | ebd01589fd75420da79eea362ce54e2c, 55438376d6b04fcb919a9646e34d2b6c, c29847f3ea1f48808321c51ebf7fccd4, 65ce4f25738f471b861805f2f58d547f, d78b185b9aaa4ea2bc67ad18a75aed51 | test:Life:visa application (e.g., F-1, H-1B):unstructured:us, test:Access Control Systems:Health Insurance Enrollment Form:unstructured:us, test:Mortgage:Flood Insurance Certificate:unstructured:us, test:Banking:Mortgage Loan:unstructured:us, test:Property:Property Maintenance Request Form:structured:us | 76 |
| date_of_birth | date_of_birth | date_time | omitted:6-10 | 0.95-1.00 | not_required | n/a | ebd01589fd75420da79eea362ce54e2c, 55438376d6b04fcb919a9646e34d2b6c, 05744eeb0a084b068d649aeb4a369923, 182da25c05734624ad7367ed3adc75fa, 71dfa7019c12481f82b4e86d6d261130 | test:Life:visa application (e.g., F-1, H-1B):unstructured:us, test:Access Control Systems:Health Insurance Enrollment Form:unstructured:us, test:Life:Death Certificate:unstructured:us, test:Life:Beneficiary Consent Form:unstructured:us, test:Elections:Ballot Request Form:structured:us | 69 |
| customer_id | customer_id | id | omitted:6-10 | 0.95-1.00 | not_required | n/a | 91060f2d1fab4793b062649755c02854, 19c97a07796948049d30a2bfffc7429c, 7333a52ab6c64e709d3b0e3cecfd24db, bd532dffa4a041ddbb1d246bda8811ea, 880ad92f659d4b05b5144595fc2673f5 | test:Brokerage:Account Activity Report:unstructured:us, test:Insurance:Insurance Policy Statement:structured:us, test:User Account and Transaction Services:Browser Session Report:structured:us, test:Brokerage:Market Trends:unstructured:us, test:Banking:Mortgage Solutions:unstructured:us | 64 |
| bank_routing_number | bank_routing_number | financial_id | omitted:6-10 | 0.95-1.00 | not_required | n/a | ebd01589fd75420da79eea362ce54e2c, a66998681d814cf49048f8d9a699ff43, 55e27db1144e40daab5a042df5bf08b1, 17276297f35343ea86cf6d98cc0d8cd8, 0f95188b0b26430e9bf243ff3d7ce095 | test:Life:visa application (e.g., F-1, H-1B):unstructured:us, test:Insurance:Disability Claim:structured:us, test:Banking:Investment Products:unstructured:us, test:Life:manual payment form:unstructured:us, test:Brokerage:Account Statement:unstructured:us | 61 |
| account_number | account_number | account_number | omitted:6-10 | 0.95-1.00 | not_required | n/a | db716ae2c78f485dadb9b87e2cd8110c, 91060f2d1fab4793b062649755c02854, 17276297f35343ea86cf6d98cc0d8cd8, b750573feb60456ea17c52ee9093b3f8, 96bd97e9769047ac8a1f9c2ca5af551f | test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us, test:Brokerage:Account Activity Report:unstructured:us, test:Life:manual payment form:unstructured:us, test:Investment:Investment Terms:structured:us, test:Credit:Payment Schedule:unstructured:us | 57 |
| age | age | age | omitted:0-2 | 0.95-1.00 | not_required | n/a | 9181f53eb3f34f3cb0b5cbdec91c94e5, 309059894d1341a2ac525e91f328085f, 96812e1ced134fd7abf78fb48b9649ae, c89ce67aaf4e48749758f95e2fcec9ef, 41f2f9f2de9e4b0d9853e7499ec3af68 | test:Investment:Tax Form:structured:us, test:Sports:Season Summary:unstructured:us, test:Public Safety:donor card or certificate:structured:us, test:Casualty:Follow-Up Letter:structured:us, test:Social Science:Gender Representation Report:unstructured:us | 48 |
| biometric_identifier | biometric_identifier | id | omitted:11-20 | 0.95-1.00 | not_required | n/a | 28421c6a3ff044d5ae8632d415f0a834, 91060f2d1fab4793b062649755c02854, 3d3e6147005c497ba0a6cd5c98da34a9, 16c97912f8414d2c9e6ffef23194144f, a66998681d814cf49048f8d9a699ff43 | test:Access Control Systems:User Credential Sheet:unstructured:us, test:Brokerage:Account Activity Report:unstructured:us, test:Access Control Systems:Background Check Authorization Form:unstructured:us, test:User Account and Transaction Services:Temporary Password Notification:structured:us, test:Insurance:Disability Claim:structured:us | 46 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| person | first_name | person | AAAA | n/a | not_required | n/a | 0e0b2612b96746d188056d4139a9f32a, 4be9e0885ba54ff7bd85f384d0f0d945, 07461020d2484810b20da3f499e3dc2e | test:Travel:Passport:structured:us, test:Elections:Voter Outreach Materials:structured:us, test:Public Safety:Search Warrant:structured:us | 3 |
| credit_card | cvv | credit_card | 999 | n/a | not_required | n/a | c0493a4055e84ac0a392c40895d4c26c | test:Insurance:Life Insurance Policy:structured:us | 2 |
| email | email | email | AAA AAAAA | n/a | not_required | n/a | 3ec50a141bb84cc0a11b111f943b71b7, 5c2850221e474a06a4ae13344c33f5d9 | test:Product:Customer Service Policy:unstructured:us, test:Life:Claim Investigation Report:structured:us | 2 |
| location | country | location | A.A. | n/a | not_required | n/a | f8830680ed7b4d468b1a127b0057a67f | test:Travel:Travel Safety Notification:structured:us | 2 |
| person | first_name | person | AA | n/a | not_required | n/a | 06327184123348e78db542beaca86cad | test:Information Technology:Support Ticket:unstructured:us | 2 |
| person | last_name | person | AAA | n/a | not_required | n/a | d81871bcb1fb4f0abce236b8a5aab580, 4be9e0885ba54ff7bd85f384d0f0d945 | test:Public Safety:Court Order:unstructured:us, test:Elections:Voter Outreach Materials:structured:us | 2 |
| person | last_name | person | AAAA | n/a | not_required | n/a | b94a58fcfb22459c83631531da8fd1c8, cef305b157744018b97fbfa90760b887 | test:Credit:Account Statement:structured:us, test:Consulting:Data Analysis Report:structured:us | 2 |
| location | city | location | AA AAAA | n/a | not_required | n/a | 0cb06715560a4eb89a34d4fef5f54462 | test:Social Science:Social Cohesion Survey:unstructured:us | 1 |
| location | city | location | AAAAAA AAAAAAA | n/a | not_required | n/a | 26ba4c1235eb4b62aff4fab5bd48ad87 | test:Casualty:Damage Assessment:unstructured:us | 1 |
| location | city | location | AAAAAAA | n/a | not_required | n/a | bb4bd6f1d34a4336a1fe422160a67905 | test:Sports:Team Policy Manual:unstructured:us | 1 |

#### Location false positives by GPE/FAC/LOC model label

No entries.

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | country | location | A.A. | n/a | not_required | n/a | f8830680ed7b4d468b1a127b0057a67f | test:Travel:Travel Safety Notification:structured:us | 2 |
| location | city | location | AA AAAA | n/a | not_required | n/a | 0cb06715560a4eb89a34d4fef5f54462 | test:Social Science:Social Cohesion Survey:unstructured:us | 1 |
| location | city | location | AAAAAA AAAAAAA | n/a | not_required | n/a | 26ba4c1235eb4b62aff4fab5bd48ad87 | test:Casualty:Damage Assessment:unstructured:us | 1 |
| location | city | location | AAAAAAA | n/a | not_required | n/a | bb4bd6f1d34a4336a1fe422160a67905 | test:Sports:Team Policy Manual:unstructured:us | 1 |
| location | city | location | AAAAAAAA | n/a | not_required | n/a | fb7ae8e86d74475fbd50e4e6d83eabc9 | test:Sports:Event Planning Document:unstructured:us | 1 |
| location | county | location | AAAAAA AA | n/a | not_required | n/a | eec3a2aba14f431880ce027c65946bde | test:Life:Beneficiary Release Form:structured:us | 1 |
| location | state | location | AA | n/a | not_required | n/a | d4ad70b31ee8438991043ae3ad210392 | test:Casualty:Damage Assessment:structured:us | 1 |
| location | state | location | AAAAA AA ________________ | n/a | not_required | n/a | 57e66de8327d4a329218f1c14e505384 | test:Mortgage:Affidavit of No Prior Mortgage:structured:us | 1 |
| location | state | location | AAAAAAA | n/a | not_required | n/a | d81871bcb1fb4f0abce236b8a5aab580 | test:Public Safety:Court Order:unstructured:us | 1 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| url | url | url | omitted:21+ | 0.95-1.00 | not_required | n/a | 006a250dfe7b4e6887c3b24ebba2c249, 4da478b6fa914915b4062984cebb30be, ee4aa0e2c09043f8891d53d4d78fa3cc, cef305b157744018b97fbfa90760b887, 06327184123348e78db542beaca86cad | test:Brokerage:Market Analysis:unstructured:us, test:Health:Health Education Brochure:structured:us, test:Investment:Compliance Document:unstructured:us, test:Consulting:Data Analysis Report:structured:us, test:Information Technology:Support Ticket:unstructured:us | 5 |
| coordinate | coordinate | location | omitted:11-20 | 0.95-1.00 | not_required | n/a | 7c24bee1d1964ce28a60168caac3faf1, 39792b3e93744002b5212218ea25fc22 | test:Access Control Systems:Biometric Border Screening Document:unstructured:us, test:Insurance:Incident Report:unstructured:us | 2 |
| first_name | first_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | b94a58fcfb22459c83631531da8fd1c8, 914a815202bf49aabf5fe0bac05bc771 | test:Credit:Account Statement:structured:us, test:Sports:Coach Biography:structured:us | 2 |
| first_name | first_name | person | omitted:11-20 | 0.95-1.00 | not_required | n/a | 78b709d11bb94a6fb1ea77411a6602d3 | test:Disability:Insurance Application:unstructured:us | 1 |
| ipv6 | ipv6 | ip_address | omitted:21+ | 0.95-1.00 | not_required | n/a | 374b15085626433fb5c46ad8fb14d090 | test:Marketing:Website Usability:structured:us | 1 |
| last_name | last_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | cef305b157744018b97fbfa90760b887 | test:Consulting:Data Analysis Report:structured:us | 1 |
| state | state | location | omitted:21+ | 0.95-1.00 | not_required | n/a | eec3a2aba14f431880ce027c65946bde | test:Life:Beneficiary Release Form:structured:us | 1 |

#### Wrong entity type rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| first_name | first_name | person | omitted:6-10 | 0.95-1.00 | not_required | n/a | ffdfb15aada049b4a29bcebfb4e83511 | test:Social Science:Migration Patterns Study:unstructured:us | 1 |
| user_name | user_name | handle | omitted:11-20 | 0.95-1.00 | not_required | n/a | dbf731e3412d473da7bd5a1e0b5df227 | test:Product:Author Interview:structured:us | 1 |



### Structured Model Error Rows

Values are sanitized; rows include Presidio-Research-style error context for tuning.

| Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| FN | credit_card | O | credit_card | cvv | 999 | n/a | not_required | n/a | n/a | n/a | c0493a4055e84ac0a392c40895d4c26c | test:Insurance:Life Insurance Policy:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | cvv | 999 | n/a | not_required | n/a | n/a | n/a | c0493a4055e84ac0a392c40895d4c26c | test:Insurance:Life Insurance Policy:structured:us | 0.0000 | credit_card not detected |
| FN | email | O | email | email | AAA AAAAA | n/a | not_required | n/a | n/a | n/a | 3ec50a141bb84cc0a11b111f943b71b7 | test:Product:Customer Service Policy:unstructured:us | 0.0000 | email not detected |
| FN | email | O | email | email | AAA AAAAA | n/a | not_required | n/a | n/a | n/a | 5c2850221e474a06a4ae13344c33f5d9 | test:Life:Claim Investigation Report:structured:us | 0.0000 | email not detected |
| FN | location | O | location | city | AA AAAA | n/a | not_required | n/a | n/a | n/a | 0cb06715560a4eb89a34d4fef5f54462 | test:Social Science:Social Cohesion Survey:unstructured:us | 0.0000 | location not detected |
| FN | location | O | location | city | AAAAAA AAAAAAA | n/a | not_required | n/a | n/a | n/a | 26ba4c1235eb4b62aff4fab5bd48ad87 | test:Casualty:Damage Assessment:unstructured:us | 0.0000 | location not detected |
| FN | location | O | location | city | AAAAAAA | n/a | not_required | n/a | n/a | n/a | bb4bd6f1d34a4336a1fe422160a67905 | test:Sports:Team Policy Manual:unstructured:us | 0.0000 | location not detected |
| FN | location | O | location | city | AAAAAAAA | n/a | not_required | n/a | n/a | n/a | fb7ae8e86d74475fbd50e4e6d83eabc9 | test:Sports:Event Planning Document:unstructured:us | 0.0000 | location not detected |
| FN | location | O | location | country | A.A. | n/a | not_required | n/a | n/a | n/a | f8830680ed7b4d468b1a127b0057a67f | test:Travel:Travel Safety Notification:structured:us | 0.0000 | location not detected |
| FN | location | O | location | country | A.A. | n/a | not_required | n/a | n/a | n/a | f8830680ed7b4d468b1a127b0057a67f | test:Travel:Travel Safety Notification:structured:us | 0.0000 | location not detected |
| FN | location | O | location | county | AAAAAA AA | n/a | not_required | n/a | n/a | n/a | eec3a2aba14f431880ce027c65946bde | test:Life:Beneficiary Release Form:structured:us | 0.0000 | location not detected |
| FN | location | O | location | state | AAAAA AA ________________ | n/a | not_required | n/a | n/a | n/a | 57e66de8327d4a329218f1c14e505384 | test:Mortgage:Affidavit of No Prior Mortgage:structured:us | 0.0000 | location not detected |
| FN | location | O | location | state | AA | n/a | not_required | n/a | n/a | n/a | d4ad70b31ee8438991043ae3ad210392 | test:Casualty:Damage Assessment:structured:us | 0.0000 | location not detected |
| FN | location | O | location | state | AAAAAAA | n/a | not_required | n/a | n/a | n/a | d81871bcb1fb4f0abce236b8a5aab580 | test:Public Safety:Court Order:unstructured:us | 0.0000 | location not detected |
| FN | person | O | person | first_name | AA | n/a | not_required | n/a | n/a | n/a | 06327184123348e78db542beaca86cad | test:Information Technology:Support Ticket:unstructured:us | 0.0000 | person not detected |
| FN | person | O | person | first_name | AA | n/a | not_required | n/a | n/a | n/a | 06327184123348e78db542beaca86cad | test:Information Technology:Support Ticket:unstructured:us | 0.0000 | person not detected |
| FN | person | O | person | first_name | AAAA | n/a | not_required | n/a | n/a | n/a | 07461020d2484810b20da3f499e3dc2e | test:Public Safety:Search Warrant:structured:us | 0.0000 | person not detected |
| FN | person | O | person | first_name | AAAA | n/a | not_required | n/a | n/a | n/a | 0e0b2612b96746d188056d4139a9f32a | test:Travel:Passport:structured:us | 0.0000 | person not detected |
| FN | person | O | person | first_name | AAAAAA | n/a | not_required | n/a | n/a | n/a | 4be527ecf50e45f09db40917e96a6ab9 | test:Fitness:Workout Recommendations:structured:us | 0.0000 | person not detected |
| FN | person | O | person | first_name | AAAA | n/a | not_required | n/a | n/a | n/a | 4be9e0885ba54ff7bd85f384d0f0d945 | test:Elections:Voter Outreach Materials:structured:us | 0.0000 | person not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| test:Credit:Account Statement:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 8 | 1 |
| test:Sports:Event Planning Document:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 3 | 1 |
| test:Sports:Sponsorship Agreement:structured:us | 1 | 0.0714 | 1.0000 | 0.1333 | 0.2778 | 1 | 13 | 0 |
| test:Marketing:Budget Proposal:structured:us | 1 | 0.0833 | 1.0000 | 0.1538 | 0.3125 | 1 | 11 | 0 |
| test:User Account and Transaction Services:Security Audit Report:structured:us | 1 | 0.0833 | 1.0000 | 0.1538 | 0.3125 | 1 | 11 | 0 |
| test:Insurance:Insurance Policy Statement:structured:us | 2 | 0.1000 | 1.0000 | 0.1818 | 0.3571 | 1 | 9 | 0 |
| test:Consulting:Regulatory Compliance Report:structured:us | 1 | 0.1111 | 1.0000 | 0.2000 | 0.3846 | 1 | 8 | 0 |
| test:Insurance:Disability Claim:structured:us | 1 | 0.1111 | 1.0000 | 0.2000 | 0.3846 | 1 | 8 | 0 |
| test:Investment:Audit Report:structured:us | 2 | 0.1111 | 1.0000 | 0.2000 | 0.3846 | 2 | 16 | 0 |
| test:Investment:Investment Agreement:structured:us | 1 | 0.1111 | 1.0000 | 0.2000 | 0.3846 | 1 | 8 | 0 |
| test:Brokerage:Compliance Certificate:unstructured:us | 1 | 0.1250 | 1.0000 | 0.2222 | 0.4167 | 1 | 7 | 0 |
| test:Brokerage:Market Commentary:structured:us | 1 | 0.1250 | 1.0000 | 0.2222 | 0.4167 | 1 | 7 | 0 |
| test:Consulting:Service Proposal:structured:us | 1 | 0.1250 | 1.0000 | 0.2222 | 0.4167 | 2 | 14 | 0 |
| test:Insurance:Risk Transfer Agreement:structured:us | 1 | 0.1250 | 1.0000 | 0.2222 | 0.4167 | 1 | 7 | 0 |
| test:Advertising:Social Media Ad Script:unstructured:us | 1 | 0.1429 | 1.0000 | 0.2500 | 0.4545 | 1 | 6 | 0 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| date_time | 15 | 25 | n/a | date_of_birth |
| street_address | 38 | 54 | n/a | street_address |
| financial_id | 167 | 176 | n/a | bank_routing_number |
| handle | 82 | 89 | n/a | user_name |
| account_number | 111 | 119 | n/a | account_number |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person | 67 | 89 | n/a | last_name |
| person | 478 | 482 | n/a | first_name |
| person | 410 | 418 | n/a | first_name |
| credit_card | 237 | 240 | n/a | cvv |
| credit_card | 716 | 719 | n/a | cvv |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/person | 67/67 | 68/73 | n/a | first_name/first_name |
| url/url | 144/144 | 198/199 | n/a | url/url |
| url/url | 574/574 | 619/620 | n/a | url/url |
| ip_address/ip_address | 459/459 | 490/491 | n/a | ipv6/ipv6 |
| url/url | 513/513 | 559/560 | n/a | url/url |

#### Wrong entity type

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/handle | 117/117 | 123/131 | n/a | first_name/user_name |
| location/person | 240/240 | 246/246 | n/a | city/first_name |



## Limitations

- Presidio-Research full compatibility report for the optional native privacy-filter adapter.
- This profile uses privacy-filter alone so it can be compared directly against a Python privacy-filter reference run.
- The profile is opt-in and experimental. It is not a default recognizer path.
