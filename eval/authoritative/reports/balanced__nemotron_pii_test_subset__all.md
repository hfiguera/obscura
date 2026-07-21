# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_nemotron_pii_test_subset_hybrid_ner_tner_conservative_full_authoritative_common_r1
- Adapter: Obscura.Deterministic+Obscura.Recognizer.NER.Serving
- Profile: hybrid_ner_tner_conservative
- Dataset: nemotron_pii_test_subset
- Samples: 500

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.8703 |
| Recall | 0.5790 |
| F1 | 0.6954 |
| F2 | 0.6206 |
| True positives | 839 |
| False positives | 125 |
| False negatives | 610 |
| Offset mismatches | 258 |
| Wrong entity type | 18 |
| Unsupported expected spans | 2361 |



### IoU Span Metrics

| Metric | Value |
| --- | ---: |
| IoU threshold | 0.9000 |
| Precision | 0.7298 |
| Recall | 0.5246 |
| F1 | 0.6105 |
| F2 | 0.5559 |
| True positives | 905 |
| False positives | 335 |
| False negatives | 820 |
| Wrong entity type | 0 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 297 |
| Predicted adjacent merges | 65 |
| Normalized IoU precision | 0.8349 |
| Normalized IoU recall | 0.6870 |
| Normalized IoU F1 | 0.7537 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| phone | 85 | false_positive: 85 |
| person | 31 | model_open_class_false_positive: 29, model_boundary_fragment: 2 |
| location | 5 | model_open_class_false_positive: 5 |
| credit_card | 2 | false_positive: 2 |
| us_ssn | 2 | false_positive: 2 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| person | 289 | open_class_model_recall_gap: 289 |
| location | 192 | open_class_model_recall_gap: 192 |
| credit_card | 98 | recognizer_recall_gap: 98 |
| url | 24 | recognizer_recall_gap: 24 |
| ip_address | 4 | recognizer_recall_gap: 4 |
| email | 2 | recognizer_recall_gap: 2 |
| phone | 1 | phone_pattern_gap: 1 |

#### Wrong entity type

| Entity | Count | Likely causes |
| --- | ---: | --- |
| url | 18 | recognizer_label_confusion: 18 |

#### Wrong Entity Matrix

| Expected | Predicted | Count |
| --- | --- | ---: |
| url | ip_address | 18 |



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | PERSON | unknown | PERSON | test:User Account and Transaction Services:Credit Card Authorization Form:structured:us | 11-20 | model_open_class_false_positive | 3 |
| phone | PHONE_NUMBER | unknown | none | test:Advertising:biometric phenotyping data file:structured:us | 6-10 | false_positive | 3 |
| phone | PHONE_NUMBER | unknown | none | test:Brokerage:Investment Process:structured:us | 6-10 | false_positive | 3 |
| person | PERSON | unknown | PERSON | test:Access Control Systems:Medical History Form:structured:us | 11-20 | model_open_class_false_positive | 2 |
| person | PERSON | unknown | PERSON | test:Advertising:Influencer Agreement:unstructured:us | 11-20 | model_open_class_false_positive | 2 |
| person | PERSON | unknown | PERSON | test:Advertising:biometric phenotyping data file:structured:us | 11-20 | model_open_class_false_positive | 2 |
| person | PERSON | unknown | PERSON | test:Fitness:Fitness Check-in:unstructured:us | 11-20 | model_open_class_false_positive | 2 |
| person | PERSON | unknown | PERSON | test:User Account and Transaction Services:Temporary Password Notification:unstructured:us | 11-20 | model_open_class_false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Banking:Investment Strategy:structured:us | 6-10 | false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Banking:Loan Servicing:structured:us | 6-10 | false_positive | 2 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| location | coordinate | unknown | none | test:Environmental:Environmental Impact Survey:structured:us | 11-20 | open_class_model_recall_gap | 7 |
| person | first_name | unknown | none | test:Health:COPD Management Plan:unstructured:us | 6-10 | open_class_model_recall_gap | 6 |
| person | last_name | unknown | none | test:Public Safety:Court Order:unstructured:us | 3-5 | open_class_model_recall_gap | 6 |
| person | first_name | unknown | none | test:Casualty:Claim Reopen Request:structured:us | 3-5 | open_class_model_recall_gap | 5 |
| person | first_name | unknown | none | test:Sports:Coach Biography:structured:us | 3-5 | open_class_model_recall_gap | 5 |
| location | country | unknown | none | test:Environmental:Environmental Impact Survey:structured:us | 3-5 | open_class_model_recall_gap | 4 |
| location | county | unknown | none | test:Social Science:Ethnic Integration Study:structured:us | 11-20 | open_class_model_recall_gap | 4 |
| location | county | unknown | none | test:Sports:Player Biography:structured:us | 11-20 | open_class_model_recall_gap | 4 |
| location | state | unknown | none | test:Environmental:Environmental Impact Survey:structured:us | 11-20 | open_class_model_recall_gap | 4 |
| location | state | unknown | none | test:Social Science:Ethnic Integration Study:structured:us | 0-2 | open_class_model_recall_gap | 4 |



### Model Label Error Analysis

#### False positives by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| PERSON | 31 | person: 31 | test:Advertising:biometric phenotyping data file:structured:us: 3, test:User Account and Transaction Services:Credit Card Authorization Form:structured:us: 3, test:Access Control Systems:Medical History Form:structured:us: 2, test:Advertising:Influencer Agreement:unstructured:us: 2, test:Fitness:Fitness Check-in:unstructured:us: 2 |
| FAC | 4 | location: 4 | test:Access Control Systems:Social Security Card Application:structured:us: 1, test:Automobile:Registration Form:unstructured:us: 1, test:Banking:Mortgage Loan:unstructured:us: 1, test:Property:Tenant Agreement:unstructured:us: 1 |
| LOC | 1 | location: 1 | test:Environmental:Resource Management Plan:unstructured:us: 1 |

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| person | 289 | person: 289 | test:Sports:Coach Biography:structured:us: 14, test:Casualty:Claim Reopen Request:structured:us: 9, test:Public Safety:Court Order:unstructured:us: 8, test:Health:COPD Management Plan:unstructured:us: 6, test:Public Safety:Search Warrant:structured:us: 6 |
| location | 192 | location: 192 | test:Environmental:Environmental Impact Survey:structured:us: 20, test:Social Science:Ethnic Integration Study:structured:us: 10, test:Environmental:Environmental Impact Analysis:structured:us: 8, test:Social Science:Ethnic Group Analysis:structured:us: 6, test:Travel:Travel Safety Notification:structured:us: 5 |
| credit_card | 98 | credit_card: 98 | test:Credit:Credit Card Agreement:structured:us: 4, test:Credit:Debit Card Policy:unstructured:us: 4, test:Credit:Loan Agreement:structured:us: 3, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us: 3, test:Banking:Debit Authorization:structured:us: 2 |
| url | 24 | url: 24 | test:Access Control Systems:Biometric Border Screening Document:unstructured:us: 1, test:Advertising:Ad Content Guidelines:structured:us: 1, test:Advertising:Customer Engagement Plan:unstructured:us: 1, test:Advertising:Video Ad Script:structured:us: 1, test:Advertising:biometric phenotyping data file:structured:us: 1 |
| ip_address | 4 | ip_address: 4 | test:Consulting:Regulatory Report:unstructured:us: 1, test:Information Technology:Installation Guide:unstructured:us: 1, test:Marketing:Website Usability:structured:us: 1, test:User Account and Transaction Services:Network Configuration File:unstructured:us: 1 |
| email | 2 | email: 2 | test:Life:Claim Investigation Report:structured:us: 1, test:Product:Customer Service Policy:unstructured:us: 1 |
| phone | 1 | phone: 1 | test:Health:Health Education Brochure:unstructured:us: 1 |

#### Offset mismatches by model label

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| PERSON | 172 | person: 172 | test:Brokerage:Investment Agreement:unstructured:us: 4, test:Health:Asthma Action Plan:unstructured:us: 4, test:Casualty:Follow-Up Letter:structured:us: 3, test:Casualty:Incident Report:unstructured:us: 3, test:Casualty:Medical Authorization:unstructured:us: 3 |
| GPE | 1 | location: 1 | test:Casualty:Claim Form:structured:us: 1 |

#### Wrong entity type by model label

No entries.



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PHONE_NUMBER | PHONE_NUMBER | phone | omitted:6-10 | 0.70-0.79 | not_required | n/a | 28421c6a3ff044d5ae8632d415f0a834, 3d3e6147005c497ba0a6cd5c98da34a9, 19c97a07796948049d30a2bfffc7429c, a66998681d814cf49048f8d9a699ff43, eb8733ff06d943e5b776450e346a653f | test:Access Control Systems:User Credential Sheet:unstructured:us, test:Access Control Systems:Background Check Authorization Form:unstructured:us, test:Insurance:Insurance Policy Statement:structured:us, test:Insurance:Disability Claim:structured:us, test:Health:Health Insurance Card:unstructured:us | 76 |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 3b72836091d44a9aa22546ab0ba879ea, 18632692c45c4ec197258b82c6f0bfb9, dcb9dbaefe6049749f256d654576aa77, c433e34674e543bbb119cafcf369b567, 3f340b3943b8447794e599dfba7c1e10 | test:Access Control Systems:Medical History Form:structured:us, test:User Account and Transaction Services:Temporary Password Notification:unstructured:us, test:Advertising:biometric phenotyping data file:structured:us, test:Advertising:Ad Content Guidelines:structured:us, test:Advertising:Influencer Agreement:unstructured:us | 14 |
| PHONE_NUMBER | PHONE_NUMBER | phone | omitted:11-20 | 0.70-0.79 | not_required | n/a | e62dd241eb8b43d9a8d75aeba044794c, b8a8cffb4ad5431ab22f5b93b5a82dfb, d58bfb8dd2d4437fb90947d780ecb85e, 3c9cc31408014c2b8e45962b4dbb6f82, 0f695fac2a8e4eea9439afb067450fe5 | test:Investment:consumer lending profile:unstructured:us, test:User Account and Transaction Services:Payment Confirmation Receipt:unstructured:us, test:Banking:Security Agreement:structured:us, test:User Account and Transaction Services:Credit Card Authorization Form:structured:us, test:Healthcare Providers:Health Insurance Plan:structured:us | 8 |
| FAC | FAC | location | omitted:11-20 | 0.95-1.00 | matched | not_adjusted | 65ce4f25738f471b861805f2f58d547f, 75e761101e564d02a41f6cdc85a89dd3, e3a73bd2d2a74d82ba1c54ebbb28be78 | test:Banking:Mortgage Loan:unstructured:us, test:Automobile:Registration Form:unstructured:us, test:Property:Tenant Agreement:unstructured:us | 3 |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | aligned | dde3b7f1a9c44fb19beb5ea2af04778b, 4c4fe2c3219a44d0bb7f1221f71a2fc5, f7e8d3df6379434699e12666f45aa0d8 | test:Fitness:Fitness Program:unstructured:us, test:Mortgage:Affidavit of No Unpaid Property Taxes:unstructured:us, test:Consulting:User Guide:unstructured:us | 3 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 28421c6a3ff044d5ae8632d415f0a834, 5977ed9892694dc08d9d37678b3fc168, dcb9dbaefe6049749f256d654576aa77 | test:Access Control Systems:User Credential Sheet:unstructured:us, test:User Account and Transaction Services:Frontend Error Log:structured:us, test:Advertising:biometric phenotyping data file:structured:us | 3 |
| CREDIT_CARD | CREDIT_CARD | credit_card | omitted:11-20 | 0.90-0.94 | not_required | n/a | 268a089496324991acb18723861d0595, 29fd925e18b74031a0bf78b698203d31 | test:Information Technology:User Guide:unstructured:us, test:Information Technology:Audit Log:unstructured:us | 2 |
| FAC | FAC | location | omitted:21+ | 0.95-1.00 | matched | not_adjusted | 4114605c092f44fb96bbeef4ce5e3dc1 | test:Access Control Systems:Social Security Card Application:structured:us | 1 |
| LOC | LOC | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | d2d0d6d88bc840239d88a45695baeb1d | test:Environmental:Resource Management Plan:unstructured:us | 1 |
| PERSON | PERSON | person | omitted:0-2 | 0.70-0.79 | not_required | not_adjusted | d7260bbcbc0847f4a31c27421227b9f8 | test:Product:User Workflow Diagram:structured:us | 1 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| person | last_name | person | AAAAAA | n/a | not_required | n/a | 05744eeb0a084b068d649aeb4a369923, 0e0b2612b96746d188056d4139a9f32a, 56d78a7582d446cb9b3b8d33e8883a9e, 1dc91a0f6765487aa2bafcf06c243c74, 5800eeaf76574b62833a1b39fbc2a353 | test:Life:Death Certificate:unstructured:us, test:Travel:Passport:structured:us, test:Travel:Travel Medical Certificate:unstructured:us, test:Human Resources:Training Workshop Materials:unstructured:us, test:Disability:Disability Verification Form:unstructured:us | 56 |
| credit_card | credit_debit_card | credit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | ebd01589fd75420da79eea362ce54e2c, f23d1f9e2f624a9f896ac1b0cdd57c32, 24ad19b70a0f48479db07e858e710078, bd532dffa4a041ddbb1d246bda8811ea, e62dd241eb8b43d9a8d75aeba044794c | test:Life:visa application (e.g., F-1, H-1B):unstructured:us, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us, test:Insurance:Insurance Policy Summary:structured:us, test:Brokerage:Market Trends:unstructured:us, test:Investment:consumer lending profile:unstructured:us | 53 |
| location | country | location | AAA | n/a | not_required | n/a | c18b4ae5c7d44763afd3ca5f3d79588a, 16e4a0fa6e324971b7ebd93dcaee80fa, b3b547e4a20040519994a602fd0eb627, b1d014b75aca44749e5b23c83b08fcba, 658e8e9de3de4c18a21ff23a71b156e5 | test:Access Control Systems:Health Insurance Enrollment Form:structured:us, test:Travel:Travel Brochure:structured:us, test:Elections:Voter Registration Form:structured:us, test:Credit:Payment Schedule:structured:us, test:Insurance:Customer Feedback Form:structured:us | 49 |
| person | last_name | person | AAAAAAA | n/a | not_required | n/a | d9bb6eac69f2483f958080776014e216, f23d1f9e2f624a9f896ac1b0cdd57c32, eab491119b7142da86b27f0dcdfa681b, f135c3c8d94f46ef8832b20d773c88eb, e6029665cd4f4580b502b9a015c22401 | test:Credit:Debit Authorization:unstructured:us, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us, test:Banking:Debit Authorization:structured:us, test:Casualty:Underwriting Form:structured:us, test:Elections:Voter Outreach Plan:unstructured:us | 39 |
| person | last_name | person | AAAAA | n/a | not_required | n/a | 182da25c05734624ad7367ed3adc75fa, d9771b676af34ed98f9a887fb7a3fefe, ea0aa01e00d24b08962d253e50b0b336, 508654010c3644d7a21879a73b0cba81, 14820489e76a404c9db067af677f1383 | test:Life:Beneficiary Consent Form:unstructured:us, test:Casualty:Settlement Agreement:unstructured:us, test:Social Science:Gender Discrimination Report:unstructured:us, test:Elections:Candidate Platform Document:unstructured:us, test:Disability:Disability Insurance Guidance:unstructured:us | 38 |
| credit_card | cvv | credit_card | 999 | n/a | not_required | n/a | d9bb6eac69f2483f958080776014e216, f23d1f9e2f624a9f896ac1b0cdd57c32, 880ad92f659d4b05b5144595fc2673f5, d9771b676af34ed98f9a887fb7a3fefe, e62dd241eb8b43d9a8d75aeba044794c | test:Credit:Debit Authorization:unstructured:us, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us, test:Banking:Mortgage Solutions:unstructured:us, test:Casualty:Settlement Agreement:unstructured:us, test:Investment:consumer lending profile:unstructured:us | 31 |
| person | first_name | person | AAAAA | n/a | not_required | n/a | 9328b235f6214a6c9243574031c1585e, 95edd74a4f014ef38f329d1ab0117a1c, 0b7684c53c834ca594085c013df3a15b, 5c2850221e474a06a4ae13344c33f5d9, 070a0bd4fe9f4925bf5b9ecc732e683c | test:Public Safety:Witness Statement:structured:us, test:Healthcare Providers:Referral Letter:unstructured:us, test:Health:Health Screening Form:structured:us, test:Life:Claim Investigation Report:structured:us, test:Casualty:Claim Reopen Request:structured:us | 21 |
| person | first_name | person | AAAAAAA | n/a | not_required | n/a | 0cd060eecc534390a87c2dcf9e276a9b, c89ce67aaf4e48749758f95e2fcec9ef, 12910aa433dc41d99d97e290cc1287b0, 6c5413856e7d4590b773b66b5e774b88, f4d97caed3db49d9a9aec14731fde2fe | test:Casualty:Claim Form:structured:us, test:Casualty:Follow-Up Letter:structured:us, test:Product:Author Interview:unstructured:us, test:Life:Beneficiary Release Form:structured:us, test:Fitness:Nutrition Guide:unstructured:us | 19 |
| person | first_name | person | AAAAAA | n/a | not_required | n/a | 19c97a07796948049d30a2bfffc7429c, b3b547e4a20040519994a602fd0eb627, 7fb659eb8f8a49f6b77020c564f4fe12, 9290c46079314379b9ab41687420ab5e, c3066c6dd7654224a95e4d579b310463 | test:Insurance:Insurance Policy Statement:structured:us, test:Elections:Voter Registration Form:structured:us, test:Property:Tenant Agreement:structured:us, test:Services:Support Ticket:unstructured:us, test:Sports:Player Loan Agreement:unstructured:us | 18 |
| person | last_name | person | AAAAAAAAA | n/a | not_required | n/a | eb8733ff06d943e5b776450e346a653f, 0f95188b0b26430e9bf243ff3d7ce095, 9179275a56154824a36257eb5181b88c, c89ce67aaf4e48749758f95e2fcec9ef, 3398749495e34fe4a625b3cc5b56f8fd | test:Health:Health Insurance Card:unstructured:us, test:Brokerage:Account Statement:unstructured:us, test:Property:Warranty Claim Form:unstructured:us, test:Casualty:Follow-Up Letter:structured:us, test:Travel:Travel Health Insurance Policy:unstructured:us | 18 |

#### Location false positives by GPE/FAC/LOC model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| FAC | FAC | location | omitted:11-20 | 0.95-1.00 | matched | not_adjusted | 65ce4f25738f471b861805f2f58d547f, 75e761101e564d02a41f6cdc85a89dd3, e3a73bd2d2a74d82ba1c54ebbb28be78 | test:Banking:Mortgage Loan:unstructured:us, test:Automobile:Registration Form:unstructured:us, test:Property:Tenant Agreement:unstructured:us | 3 |
| FAC | FAC | location | omitted:21+ | 0.95-1.00 | matched | not_adjusted | 4114605c092f44fb96bbeef4ce5e3dc1 | test:Access Control Systems:Social Security Card Application:structured:us | 1 |
| LOC | LOC | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | d2d0d6d88bc840239d88a45695baeb1d | test:Environmental:Resource Management Plan:unstructured:us | 1 |

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | coordinate | location | 99.9999, -99.9999 | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 7 |
| location | country | location | AAA | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 4 |
| location | county | location | AAAA AAAAAA | n/a | not_required | n/a | 6305a4e1c2b447d0b272ae720722feda | test:Social Science:Ethnic Integration Study:structured:us | 4 |
| location | county | location | AAAAAAAAAAAA AAAAAA | n/a | not_required | n/a | 327e531341284d2889c54186d6baf79b | test:Sports:Player Biography:structured:us | 4 |
| location | state | location | AA | n/a | not_required | n/a | 6305a4e1c2b447d0b272ae720722feda | test:Social Science:Ethnic Integration Study:structured:us | 4 |
| location | state | location | AAAAAAAAAAA | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 4 |
| location | city | location | AAAAAAA | n/a | not_required | n/a | da4312cecf02457b8d1cab22d560b0a2 | test:Social Science:Ethnic Group Analysis:structured:us | 3 |
| location | coordinate | location | 99.9999, -99.9999 | n/a | not_required | n/a | 81289070e36d4b87b6c85d6a4bba6805 | test:Environmental:Environmental Impact Analysis:structured:us | 3 |
| location | country | location | AAA | n/a | not_required | n/a | 81289070e36d4b87b6c85d6a4bba6805 | test:Environmental:Environmental Impact Analysis:structured:us | 3 |
| location | country | location | AAA | n/a | not_required | n/a | d7260bbcbc0847f4a31c27421227b9f8 | test:Product:User Workflow Diagram:structured:us | 3 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PERSON | PERSON | person | omitted:11-20 | 0.95-1.00 | not_required | not_adjusted | 05744eeb0a084b068d649aeb4a369923, eb8733ff06d943e5b776450e346a653f, 182da25c05734624ad7367ed3adc75fa, d9bb6eac69f2483f958080776014e216, f23d1f9e2f624a9f896ac1b0cdd57c32 | test:Life:Death Certificate:unstructured:us, test:Health:Health Insurance Card:unstructured:us, test:Life:Beneficiary Consent Form:unstructured:us, test:Credit:Debit Authorization:unstructured:us, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us | 123 |
| URL | URL | url | omitted:21+ | 0.80-0.89 | not_required | n/a | 412e61065c8747d194daaee665d2193d, 8819a31fde2a4da89c0939388a1d7e2b, 7333a52ab6c64e709d3b0e3cecfd24db, 10c47784f85c423281050c17960fd5c3, 618e7ed00b7f44709fc4e9f7866924ca | test:Consulting:Vendor Performance Report:unstructured:us, test:Elections:Election Rules Handbook:unstructured:us, test:User Account and Transaction Services:Browser Session Report:structured:us, test:Automobile:Vehicle Maintenance Checklist:unstructured:us, test:User Account and Transaction Services:Temporary Password Notification:unstructured:us | 80 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | aligned | d9771b676af34ed98f9a887fb7a3fefe, 14820489e76a404c9db067af677f1383, 12910aa433dc41d99d97e290cc1287b0, 1bcfd8e8025c4162a0d749575b3927d5, f4d97caed3db49d9a9aec14731fde2fe | test:Casualty:Settlement Agreement:unstructured:us, test:Disability:Disability Insurance Guidance:unstructured:us, test:Product:Author Interview:unstructured:us, test:Credit:Debt Settlement Plan:unstructured:us, test:Fitness:Nutrition Guide:unstructured:us | 22 |
| PERSON | PERSON | person | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 14820489e76a404c9db067af677f1383, ba991857bd174b14a6aa370a77d7f653, 9cd54625bc14481a8e0f62e6732b4796, a8c7f930f6dc429a93367402d5627287, 5f3cb1995f2b4bc19c0fbee546c86e11 | test:Disability:Disability Insurance Guidance:unstructured:us, test:Human Resources:Training Workshop Evaluation:structured:us, test:Automobile:Insurance Policy:unstructured:us, test:Disability:Disability Insurance Change:structured:us, test:Product:Author Article:unstructured:us | 17 |
| URL | URL | url | omitted:11-20 | 0.80-0.89 | not_required | n/a | dfb4c16ed5a640bc917ebbd91f97e1a3, 6305a4e1c2b447d0b272ae720722feda | test:Elections:Election Day Voter Information:unstructured:us, test:Social Science:Ethnic Integration Study:structured:us | 5 |
| PERSON | PERSON | person | omitted:11-20 | 0.80-0.89 | not_required | aligned | 0e0b2612b96746d188056d4139a9f32a, ff8c6f36206d47e68b3c3fbd6fbf1c34, 907640105c35401ab48e651fddc6c400 | test:Travel:Passport:structured:us, test:Public Safety:Safety Training Materials:structured:us, test:Life:Policy Cancellation Notice:structured:us | 3 |
| PERSON | PERSON | person | omitted:11-20 | 0.90-0.94 | not_required | not_adjusted | 7fb659eb8f8a49f6b77020c564f4fe12, f7ae1906ab834840b30d79070cedb769 | test:Property:Tenant Agreement:structured:us, test:Sports:Emergency Contact List:structured:us | 2 |
| GPE | GPE | location | omitted:6-10 | 0.95-1.00 | not_required | not_adjusted | 0cd060eecc534390a87c2dcf9e276a9b | test:Casualty:Claim Form:structured:us | 1 |
| PERSON | PERSON | person | omitted:11-20 | 0.90-0.94 | not_required | aligned | f4a3529b950a4328a994f9aa7857e56f | test:Sports:Coach Biography:structured:us | 1 |
| PERSON | PERSON | person | omitted:11-20 | 0.80-0.89 | not_required | not_adjusted | 9da41bf24df54a3bb5337a65b058b067 | test:Advertising:Video Production Brief:unstructured:us | 1 |

#### Wrong entity type rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| IP_ADDRESS | IP_ADDRESS | ip_address | omitted:11-20 | 0.80-0.89 | not_required | n/a | 26415ba38ddb453fa1450e95ddca37d2, ea6dc0c5b2434f82baf44120b60fca52, 26ba4c1235eb4b62aff4fab5bd48ad87, 9a4e7e98daab4d45ac13b06816faa0e4, 5a72a283aa3540c5afbb54e28b144305 | test:Environmental:Environmental Health Risk Assessment:structured:us, test:Brokerage:Market Analysis Report:unstructured:us, test:Casualty:Damage Assessment:unstructured:us, test:Public Safety:Health and Safety Guidelines:unstructured:us, test:Consulting:Regulatory Report:unstructured:us | 17 |
| IP_ADDRESS | IP_ADDRESS | ip_address | omitted:6-10 | 0.80-0.89 | not_required | n/a | 891e7263e8eb4bce85aaa17ee6342e19 | test:Product:Author Article:unstructured:us | 1 |



### Structured Model Error Rows

Values are sanitized; rows include Presidio-Research-style error context for tuning.

| Type | Expected | Predicted | Entity | Model label | Token shape | Score | Context | Boundary | Parser | Conflict | Sample | Template | IoU | Explanation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 999999 99999 | n/a | not_required | n/a | n/a | n/a | 12910aa433dc41d99d97e290cc1287b0 | test:Product:Author Interview:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 140e8adc94f4466296843b31b921f493 | test:Casualty:Post-Loss Documentation:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 187dd62289934e44be4df205de3030dc | test:Consulting:Regulatory Compliance Report:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 1bcfd8e8025c4162a0d749575b3927d5 | test:Credit:Debt Settlement Plan:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 237a73a626674574adad6de12d30ce7a | test:Marketing:Website Content:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 999999 99999 | n/a | not_required | n/a | n/a | n/a | 23b7e26abec34fc596c14f617f375944 | test:Marketing:Event Invitation:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 24ad19b70a0f48479db07e858e710078 | test:Insurance:Insurance Policy Summary:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 24ad19b70a0f48479db07e858e710078 | test:Insurance:Insurance Policy Summary:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 255d4da2aa65479b942d74d4a660e771 | test:Elections:Election Day Schedule:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 26aae84f0d3141228f14c2dac062fe30 | test:Credit:Refinance Agreement:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 2aff10775aa2422abaf74801f0c03920 | test:Investment:Investment Universe:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 3c9cc31408014c2b8e45962b4dbb6f82 | test:User Account and Transaction Services:Credit Card Authorization Form:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 999999 99999 | n/a | not_required | n/a | n/a | n/a | 3e2e180ceae04f08a8c7c58d3a1398db | test:Fitness:Exercise Diary:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 42516e25039049fdb1b2eb22d69bc0ad | test:Automobile:Recall Notice:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 4fbb22818bb94b348e1005ddfdf54547 | test:Credit:Debit Card Upgrade Form:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 579ddf19015949538fa1e66b056b2f6a | test:Credit:Loan Agreement:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 579ddf19015949538fa1e66b056b2f6a | test:Credit:Loan Agreement:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 579ddf19015949538fa1e66b056b2f6a | test:Credit:Loan Agreement:structured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 5ae338b2adee4937a0d79b8fb4bda5b1 | test:Investment:consumer lending profile:unstructured:us | 0.0000 | credit_card not detected |
| FN | credit_card | O | credit_card | credit_debit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | n/a | n/a | 6423e1efe62b4b20b6b5bd9cf8536fb4 | test:Services:transcribed phone order:unstructured:us | 0.0000 | credit_card not detected |



### Worst Per-Template Metrics

| Template | Samples | Precision | Recall | F1 | F2 | TP | FP | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| test:Advertising:biometric phenotyping data file:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 6 | 1 |
| test:Banking:Investment Strategy:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 2 |
| test:Banking:Mortgage Solutions:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 2 |
| test:Banking:Security Agreement:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 1 |
| test:Brokerage:Account Closing Form:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 3 |
| test:Brokerage:Account Statement:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |
| test:Brokerage:Market Analysis:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |
| test:Credit:Credit Approval Letter:unstructured:us | 2 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 4 |
| test:Credit:Debit Authorization:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 3 |
| test:Credit:Refinance Agreement:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 3 |
| test:Elections:Voter Registration Verification Form:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 4 |
| test:Health:Cancer Screening Report:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |
| test:Healthcare Providers:Health Insurance Plan:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 2 |
| test:Insurance:Insurance Policy Statement:structured:us | 2 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |
| test:Insurance:patient biometric ID record:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person | 89 | 99 | n/a | PERSON |
| phone | 205 | 215 | n/a | PHONE_NUMBER |
| phone | 252 | 262 | n/a | PHONE_NUMBER |
| location | 166 | 179 | n/a | FAC |
| person | 64 | 79 | n/a | PERSON |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| credit_card | 200 | 219 | n/a | credit_debit_card |
| credit_card | 186 | 203 | n/a | credit_debit_card |
| location | 136 | 151 | n/a | county |
| person | 42 | 48 | n/a | last_name |
| person | 116 | 122 | n/a | last_name |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person/person | 37/37 | 41/48 | n/a | first_name/PERSON |
| person/person | 111/111 | 115/122 | n/a | first_name/PERSON |
| person/person | 40/40 | 47/57 | n/a | first_name/PERSON |
| url/url | 116/116 | 173/141 | n/a | url/URL |
| url/url | 99/99 | 145/146 | n/a | url/URL |

#### Wrong entity type

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| url/ip_address | 86/93 | 149/106 | n/a | url/IP_ADDRESS |
| url/ip_address | 1067/1074 | 1130/1087 | n/a | url/IP_ADDRESS |
| url/ip_address | 116/123 | 147/134 | n/a | url/IP_ADDRESS |
| url/ip_address | 412/419 | 462/432 | n/a | url/IP_ADDRESS |
| url/ip_address | 223/230 | 272/242 | n/a | url/IP_ADDRESS |



## Limitations

- Presidio-Research full compatibility report using deterministic recognizers plus tner/roberta-large-ontonotes5 with conservative model-specific policy.
- The TNER model card reports strong OntoNotes5 results but warns that plain Transformers usage is not recommended because the CRF layer is unsupported; Bumblebee/Nx output must therefore be treated as experimental until measured.
- DATE/TIME and noisy non-PII OntoNotes labels are ignored by default; organization is allowed only behind higher threshold and context gating.
