# Presidio compatibility Evaluation Report

- Run ID: presidio_compatibility_nemotron_pii_test_subset_deterministic_plus_full_authoritative_common_r1
- Adapter: Obscura.Fixtures.ObscuraAnalyzerAdapter+DeterministicPlus
- Profile: deterministic_plus
- Dataset: nemotron_pii_test_subset
- Samples: 500

## Metrics

### Exact Span Metrics

| Metric | Value |
| --- | ---: |
| Precision | 0.8037 |
| Recall | 0.2729 |
| F1 | 0.4074 |
| F2 | 0.3144 |
| True positives | 438 |
| False positives | 107 |
| False negatives | 1167 |
| Offset mismatches | 101 |
| Wrong entity type | 19 |
| Unsupported expected spans | 2361 |



### IoU Span Metrics

| Metric | Value |
| --- | ---: |
| IoU threshold | 0.9000 |
| Precision | 0.7579 |
| Recall | 0.2922 |
| F1 | 0.4218 |
| F2 | 0.3331 |
| True positives | 504 |
| False positives | 161 |
| False negatives | 1221 |
| Wrong entity type | 0 |


### Normalized Span Diagnostics

| Metric | Value |
| --- | ---: |
| Mode | skip_word_adjacent |
| Expected adjacent merges | 297 |
| Predicted adjacent merges | 1 |
| Normalized IoU precision | 0.7741 |
| Normalized IoU recall | 0.3599 |
| Normalized IoU F1 | 0.4914 |


### Error Buckets

#### False positives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| phone | 85 | false_positive: 85 |
| person | 18 | false_positive: 18 |
| credit_card | 2 | false_positive: 2 |
| us_ssn | 2 | false_positive: 2 |

#### False negatives

| Entity | Count | Likely causes |
| --- | ---: | --- |
| person | 635 | open_class_model_recall_gap: 635 |
| location | 403 | open_class_model_recall_gap: 403 |
| credit_card | 98 | recognizer_recall_gap: 98 |
| url | 24 | recognizer_recall_gap: 24 |
| ip_address | 4 | recognizer_recall_gap: 4 |
| email | 2 | recognizer_recall_gap: 2 |
| phone | 1 | phone_pattern_gap: 1 |

#### Wrong entity type

| Entity | Count | Likely causes |
| --- | ---: | --- |
| url | 18 | recognizer_label_confusion: 18 |
| person | 1 | recognizer_label_confusion: 1 |

#### Wrong Entity Matrix

| Expected | Predicted | Count |
| --- | --- | ---: |
| url | ip_address | 18 |
| person | location | 1 |



### Top Sanitized Error Signatures

#### False positives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| phone | PHONE_NUMBER | unknown | none | test:Advertising:biometric phenotyping data file:structured:us | 6-10 | false_positive | 3 |
| phone | PHONE_NUMBER | unknown | none | test:Brokerage:Investment Process:structured:us | 6-10 | false_positive | 3 |
| person | PERSON | unknown | none | test:Environmental:Environmental Impact Analysis:structured:us | 21+ | false_positive | 2 |
| person | PERSON | unknown | none | test:Marketing:User Agreement:structured:us | 21+ | false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Banking:Investment Strategy:structured:us | 6-10 | false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Banking:Loan Servicing:structured:us | 6-10 | false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Banking:Mortgage Solutions:unstructured:us | 6-10 | false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Banking:Security Agreement:structured:us | 11-20 | false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Banking:Transaction Record:structured:us | 6-10 | false_positive | 2 |
| phone | PHONE_NUMBER | unknown | none | test:Brokerage:Account Closing Form:unstructured:us | 6-10 | false_positive | 2 |

#### False negatives

| Entity | Source entity | Recognizer | Model label | Template | Length | Likely cause | Count |
| --- | --- | --- | --- | --- | --- | --- | ---: |
| person | first_name | unknown | none | test:Disability:Disability Insurance Guidance:unstructured:us | 3-5 | open_class_model_recall_gap | 10 |
| person | first_name | unknown | none | test:Health:COPD Management Plan:unstructured:us | 6-10 | open_class_model_recall_gap | 10 |
| location | coordinate | unknown | none | test:Environmental:Environmental Impact Survey:structured:us | 11-20 | open_class_model_recall_gap | 7 |
| location | country | unknown | none | test:Environmental:Environmental Impact Survey:structured:us | 3-5 | open_class_model_recall_gap | 7 |
| location | state | unknown | none | test:Environmental:Environmental Impact Survey:structured:us | 11-20 | open_class_model_recall_gap | 7 |
| person | first_name | unknown | none | test:Health:Asthma Action Plan:unstructured:us | 3-5 | open_class_model_recall_gap | 7 |
| person | first_name | unknown | none | test:Sports:Coach Biography:structured:us | 3-5 | open_class_model_recall_gap | 7 |
| location | city | unknown | none | test:Social Science:Ethnic Group Analysis:structured:us | 6-10 | open_class_model_recall_gap | 6 |
| location | county | unknown | none | test:Social Science:Ethnic Integration Study:structured:us | 11-20 | open_class_model_recall_gap | 6 |
| location | state | unknown | none | test:Social Science:Ethnic Integration Study:structured:us | 0-2 | open_class_model_recall_gap | 6 |



### Model Label Error Analysis

#### False positives by model label

No entries.

#### False negatives by expected entity

| Label | Count | Entities | Top templates |
| --- | ---: | --- | --- |
| person | 635 | person: 635 | test:Disability:Disability Insurance Guidance:unstructured:us: 11, test:Health:COPD Management Plan:unstructured:us: 10, test:Public Safety:Court Order:unstructured:us: 10, test:Casualty:Claim Reopen Request:structured:us: 9, test:Sports:Coach Biography:structured:us: 9 |
| location | 403 | location: 403 | test:Environmental:Environmental Impact Survey:structured:us: 30, test:Social Science:Ethnic Integration Study:structured:us: 15, test:Social Science:Ethnic Group Analysis:structured:us: 11, test:Elections:Voter Outreach Materials:structured:us: 8, test:Environmental:Environmental Impact Analysis:structured:us: 8 |
| credit_card | 98 | credit_card: 98 | test:Credit:Credit Card Agreement:structured:us: 4, test:Credit:Debit Card Policy:unstructured:us: 4, test:Credit:Loan Agreement:structured:us: 3, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us: 3, test:Banking:Debit Authorization:structured:us: 2 |
| url | 24 | url: 24 | test:Access Control Systems:Biometric Border Screening Document:unstructured:us: 1, test:Advertising:Ad Content Guidelines:structured:us: 1, test:Advertising:Customer Engagement Plan:unstructured:us: 1, test:Advertising:Video Ad Script:structured:us: 1, test:Advertising:biometric phenotyping data file:structured:us: 1 |
| ip_address | 4 | ip_address: 4 | test:Consulting:Regulatory Report:unstructured:us: 1, test:Information Technology:Installation Guide:unstructured:us: 1, test:Marketing:Website Usability:structured:us: 1, test:User Account and Transaction Services:Network Configuration File:unstructured:us: 1 |
| email | 2 | email: 2 | test:Life:Claim Investigation Report:structured:us: 1, test:Product:Customer Service Policy:unstructured:us: 1 |
| phone | 1 | phone: 1 | test:Health:Health Education Brochure:unstructured:us: 1 |

#### Offset mismatches by model label

No entries.

#### Wrong entity type by model label

No entries.



### Actionable Error Rows

Values are sanitized; token shapes and length buckets are shown instead of raw detected text.

#### Top false positives by model label

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| PHONE_NUMBER | PHONE_NUMBER | phone | 9999999999 | 0.70-0.79 | not_required | n/a | 28421c6a3ff044d5ae8632d415f0a834, 3d3e6147005c497ba0a6cd5c98da34a9, 19c97a07796948049d30a2bfffc7429c, a66998681d814cf49048f8d9a699ff43, eb8733ff06d943e5b776450e346a653f | test:Access Control Systems:User Credential Sheet:unstructured:us, test:Access Control Systems:Background Check Authorization Form:unstructured:us, test:Insurance:Insurance Policy Statement:structured:us, test:Insurance:Disability Claim:structured:us, test:Health:Health Insurance Card:unstructured:us | 76 |
| PHONE_NUMBER | PHONE_NUMBER | phone | 999-999-9999 | 0.70-0.79 | not_required | n/a | e62dd241eb8b43d9a8d75aeba044794c, b8a8cffb4ad5431ab22f5b93b5a82dfb, d58bfb8dd2d4437fb90947d780ecb85e | test:Investment:consumer lending profile:unstructured:us, test:User Account and Transaction Services:Payment Confirmation Receipt:unstructured:us, test:Banking:Security Agreement:structured:us | 4 |
| CREDIT_CARD | CREDIT_CARD | credit_card | 999999999999999 | 0.90-0.94 | not_required | n/a | 268a089496324991acb18723861d0595, 29fd925e18b74031a0bf78b698203d31 | test:Information Technology:User Guide:unstructured:us, test:Information Technology:Audit Log:unstructured:us | 2 |
| PERSON | PERSON | person | AAAAAAAAA AAAAAAAAA AAAAA | 0.70-0.79 | not_required | n/a | d4ba708662174b989667a4ca2989eab3 | test:Marketing:User Agreement:structured:us | 2 |
| PERSON | PERSON | person | AAAAAAAAA AAAAAAAAAAAAA AAAAAAAA | 0.70-0.79 | not_required | n/a | 81289070e36d4b87b6c85d6a4bba6805 | test:Environmental:Environmental Impact Analysis:structured:us | 2 |
| PHONE_NUMBER | PHONE_NUMBER | phone | (999) 999-9999 | 0.70-0.79 | not_required | n/a | 0f695fac2a8e4eea9439afb067450fe5 | test:Healthcare Providers:Health Insurance Plan:structured:us | 2 |
| PERSON | PERSON | person | AA | 0.70-0.79 | not_required | n/a | 152708427e174751b3af47805fd1861c | test:Marketing:Newsletter:unstructured:us | 1 |
| PERSON | PERSON | person | AAA | 0.70-0.79 | not_required | n/a | 38aca0ab3e7846c5bf72074e7db2e168 | test:Disability:Disability Insurance Form:unstructured:us | 1 |
| PERSON | PERSON | person | AAA AAAAAAAAA | 0.70-0.79 | not_required | n/a | f4b61a575ad4468e82ca19ec57ca8d50 | test:User Account and Transaction Services:Customer Payment Information Sheet:structured:us | 1 |
| PERSON | PERSON | person | AAAA AAAAAA | 0.70-0.79 | not_required | n/a | b94e19764de34cc0aa0dc91f2425bf1e | test:Healthcare Providers:Health Assessment:structured:us | 1 |

#### Top false negatives by expected entity

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| person | first_name | person | AAAAA | n/a | not_required | n/a | ebd01589fd75420da79eea362ce54e2c, 55438376d6b04fcb919a9646e34d2b6c, dd41dc0342dd46b9a689c92ae47dee1a, c18b4ae5c7d44763afd3ca5f3d79588a, 618e7ed00b7f44709fc4e9f7866924ca | test:Life:visa application (e.g., F-1, H-1B):unstructured:us, test:Access Control Systems:Health Insurance Enrollment Form:unstructured:us, test:Life:Claim Evidence Submission Form:unstructured:us, test:Access Control Systems:Health Insurance Enrollment Form:structured:us, test:User Account and Transaction Services:Temporary Password Notification:unstructured:us | 110 |
| location | country | location | AAA | n/a | not_required | n/a | ebd01589fd75420da79eea362ce54e2c, 05744eeb0a084b068d649aeb4a369923, 65ce4f25738f471b861805f2f58d547f, 412e61065c8747d194daaee665d2193d, 8819a31fde2a4da89c0939388a1d7e2b | test:Life:visa application (e.g., F-1, H-1B):unstructured:us, test:Life:Death Certificate:unstructured:us, test:Banking:Mortgage Loan:unstructured:us, test:Consulting:Vendor Performance Report:unstructured:us, test:Elections:Election Rules Handbook:unstructured:us | 103 |
| person | first_name | person | AAAAAAA | n/a | not_required | n/a | bde4585a9dea42cdaf8a881ef3e69167, eb8733ff06d943e5b776450e346a653f, 1fc2b7f98c7549a18605a252870ba3cd, 65d858ec97a64750a8afcad122e3c854, ea0aa01e00d24b08962d253e50b0b336 | test:Property:Rental Application:structured:us, test:Health:Health Insurance Card:unstructured:us, test:Life:Claim Reconsideration Form:unstructured:us, test:Sports:Training Log:unstructured:us, test:Social Science:Gender Discrimination Report:unstructured:us | 91 |
| person | first_name | person | AAAAAA | n/a | not_required | n/a | 3e3f8e5a1e064d5ba44271375c59f1cb, 3d3e6147005c497ba0a6cd5c98da34a9, 65ce4f25738f471b861805f2f58d547f, 19c97a07796948049d30a2bfffc7429c, d78b185b9aaa4ea2bc67ad18a75aed51 | test:Travel:Ticket:structured:us, test:Access Control Systems:Background Check Authorization Form:unstructured:us, test:Banking:Mortgage Loan:unstructured:us, test:Insurance:Insurance Policy Statement:structured:us, test:Property:Property Maintenance Request Form:structured:us | 80 |
| person | last_name | person | AAAAAA | n/a | not_required | n/a | 3e3f8e5a1e064d5ba44271375c59f1cb, 05744eeb0a084b068d649aeb4a369923, d78b185b9aaa4ea2bc67ad18a75aed51, 0e0b2612b96746d188056d4139a9f32a, 56d78a7582d446cb9b3b8d33e8883a9e | test:Travel:Ticket:structured:us, test:Life:Death Certificate:unstructured:us, test:Property:Property Maintenance Request Form:structured:us, test:Travel:Passport:structured:us, test:Travel:Travel Medical Certificate:unstructured:us | 65 |
| person | first_name | person | AAAA | n/a | not_required | n/a | 05744eeb0a084b068d649aeb4a369923, d9bb6eac69f2483f958080776014e216, 0e0b2612b96746d188056d4139a9f32a, 327e531341284d2889c54186d6baf79b, 56e0c0ce6f36461f861ad54cd85ad743 | test:Life:Death Certificate:unstructured:us, test:Credit:Debit Authorization:unstructured:us, test:Travel:Passport:structured:us, test:Sports:Player Biography:structured:us, test:Elections:Voter Absentee Ballot Request:unstructured:us | 58 |
| credit_card | credit_debit_card | credit_card | 9999 9999 9999 9999 | n/a | not_required | n/a | ebd01589fd75420da79eea362ce54e2c, f23d1f9e2f624a9f896ac1b0cdd57c32, 24ad19b70a0f48479db07e858e710078, bd532dffa4a041ddbb1d246bda8811ea, e62dd241eb8b43d9a8d75aeba044794c | test:Life:visa application (e.g., F-1, H-1B):unstructured:us, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us, test:Insurance:Insurance Policy Summary:structured:us, test:Brokerage:Market Trends:unstructured:us, test:Investment:consumer lending profile:unstructured:us | 53 |
| person | last_name | person | AAAAA | n/a | not_required | n/a | d9771b676af34ed98f9a887fb7a3fefe, ea0aa01e00d24b08962d253e50b0b336, 508654010c3644d7a21879a73b0cba81, 14820489e76a404c9db067af677f1383, 12910aa433dc41d99d97e290cc1287b0 | test:Casualty:Settlement Agreement:unstructured:us, test:Social Science:Gender Discrimination Report:unstructured:us, test:Elections:Candidate Platform Document:unstructured:us, test:Disability:Disability Insurance Guidance:unstructured:us, test:Product:Author Interview:unstructured:us | 43 |
| location | state | location | AA | n/a | not_required | n/a | c29847f3ea1f48808321c51ebf7fccd4, 8819a31fde2a4da89c0939388a1d7e2b, 182da25c05734624ad7367ed3adc75fa, d9771b676af34ed98f9a887fb7a3fefe, 255d4da2aa65479b942d74d4a660e771 | test:Mortgage:Flood Insurance Certificate:unstructured:us, test:Elections:Election Rules Handbook:unstructured:us, test:Life:Beneficiary Consent Form:unstructured:us, test:Casualty:Settlement Agreement:unstructured:us, test:Elections:Election Day Schedule:unstructured:us | 42 |
| credit_card | cvv | credit_card | 999 | n/a | not_required | n/a | d9bb6eac69f2483f958080776014e216, f23d1f9e2f624a9f896ac1b0cdd57c32, 880ad92f659d4b05b5144595fc2673f5, d9771b676af34ed98f9a887fb7a3fefe, e62dd241eb8b43d9a8d75aeba044794c | test:Credit:Debit Authorization:unstructured:us, test:User Account and Transaction Services:Credit Card Authorization Form:unstructured:us, test:Banking:Mortgage Solutions:unstructured:us, test:Casualty:Settlement Agreement:unstructured:us, test:Investment:consumer lending profile:unstructured:us | 31 |

#### Location false positives by GPE/FAC/LOC model label

No entries.

#### Location false negatives by template/context

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| location | coordinate | location | 99.9999, -99.9999 | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 7 |
| location | country | location | AAA | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 7 |
| location | state | location | AAAAAAAAAAA | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 7 |
| location | city | location | AAAAAAA | n/a | not_required | n/a | da4312cecf02457b8d1cab22d560b0a2 | test:Social Science:Ethnic Group Analysis:structured:us | 6 |
| location | county | location | AAAA AAAAAA | n/a | not_required | n/a | 6305a4e1c2b447d0b272ae720722feda | test:Social Science:Ethnic Integration Study:structured:us | 6 |
| location | state | location | AA | n/a | not_required | n/a | 6305a4e1c2b447d0b272ae720722feda | test:Social Science:Ethnic Integration Study:structured:us | 6 |
| location | county | location | AAAAA AAAAAA | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 5 |
| location | city | location | AAAAA AAAA | n/a | not_required | n/a | 46ea9e1e1b43431b828ee71ba41258e2 | test:Environmental:Environmental Impact Survey:structured:us | 4 |
| location | country | location | AAA | n/a | not_required | n/a | 16e4a0fa6e324971b7ebd93dcaee80fa | test:Travel:Travel Brochure:structured:us | 4 |
| location | county | location | AAAAAAAAAAAA AAAAAA | n/a | not_required | n/a | 327e531341284d2889c54186d6baf79b | test:Sports:Player Biography:structured:us | 4 |

#### Organization false negatives by template/context

No entries.

#### Offset mismatch rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| URL | URL | url | AAAA://AAAAAAAAAAAAAA.AAA | 0.80-0.89 | not_required | n/a | 412e61065c8747d194daaee665d2193d, 29d61889dcb9491db8144b7e33146865, be9ad33d08cd48aaa1e7c520d8da6b8b, da3dd78685364e429be3705caff99abe | test:Consulting:Vendor Performance Report:unstructured:us, test:Consulting:Technical Report:unstructured:us, test:Investment:Audit Report:structured:us, test:Consulting:Performance Report:unstructured:us | 5 |
| URL | URL | url | AAAA://AAAAAAAAA.AAA | 0.80-0.89 | not_required | n/a | 6305a4e1c2b447d0b272ae720722feda | test:Social Science:Ethnic Integration Study:structured:us | 4 |
| URL | URL | url | AAAAA://AAA.AAA/AAAAAAAAAAAAAAAA | 0.80-0.89 | not_required | n/a | 81289070e36d4b87b6c85d6a4bba6805 | test:Environmental:Environmental Impact Analysis:structured:us | 4 |
| PERSON | PERSON | person | AAAAA AAAA | 0.70-0.79 | not_required | n/a | 95edd74a4f014ef38f329d1ab0117a1c, 9cd54625bc14481a8e0f62e6732b4796, d22298b4ac254835946cd92a578ed572 | test:Healthcare Providers:Referral Letter:unstructured:us, test:Automobile:Insurance Policy:unstructured:us, test:Disability:Disability Income Statement:unstructured:us | 3 |
| PERSON | PERSON | person | AAAAAA AAAAAA | 0.70-0.79 | not_required | n/a | 1dc91a0f6765487aa2bafcf06c243c74, 778c0ec00e044e0f937f00a0d78b8d36, edbd621e87ad474da1d8bc7c48ccf62b | test:Human Resources:Training Workshop Materials:unstructured:us, test:Human Resources:Training Workshop Agenda:unstructured:us, test:Human Resources:Employee Feedback Form:unstructured:us | 3 |
| PERSON | PERSON | person | AAAA AAAAA | 0.70-0.79 | not_required | n/a | 997aead7f98c4330873909c7cf18ed03, 0f695fac2a8e4eea9439afb067450fe5 | test:Property:Property Transfer Agreement:structured:us, test:Healthcare Providers:Health Insurance Plan:structured:us | 2 |
| PERSON | PERSON | person | AAAAA AAAAAA | 0.70-0.79 | not_required | n/a | 56d78a7582d446cb9b3b8d33e8883a9e, 5800eeaf76574b62833a1b39fbc2a353 | test:Travel:Travel Medical Certificate:unstructured:us, test:Disability:Disability Verification Form:unstructured:us | 2 |
| URL | URL | url | AAAA://AAAAAAAAA.AAAAAA | 0.80-0.89 | not_required | n/a | 5a05564eb80346ae97cf9ab6d5b5d1d2 | test:Marketing:Brand Guidelines:unstructured:us | 2 |
| URL | URL | url | AAAA://AAAAAAAAAAAAAAA.AAA | 0.80-0.89 | not_required | n/a | 3f5d8c92da9341e0b326ad5b31965142 | test:Product:Author Whitepaper:structured:us | 2 |
| URL | URL | url | AAAAA://AAA.AAA/AAAAAAAAA-AAAAA. | 0.80-0.89 | not_required | n/a | 0cece405fd1747c794a012cf8aa62c05 | test:Environmental:Hazardous Material Report:structured:us | 2 |

#### Wrong entity type rows

| Label | Source label | Entity | Token shape | Score bucket | Context | Boundary | Samples | Templates | Count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| IP_ADDRESS | IP_ADDRESS | ip_address | 999.999.9.999 | 0.80-0.89 | not_required | n/a | 26415ba38ddb453fa1450e95ddca37d2, 26ba4c1235eb4b62aff4fab5bd48ad87, 5a72a283aa3540c5afbb54e28b144305, 3d571355981141b7bae790ed69694bbd, 8d31bc978db04652b8869def8ca9b057 | test:Environmental:Environmental Health Risk Assessment:structured:us, test:Casualty:Damage Assessment:unstructured:us, test:Consulting:Regulatory Report:unstructured:us, test:Consulting:Compliance Checklist:unstructured:us, test:Social Science:Language Access Study:unstructured:us | 10 |
| IP_ADDRESS | IP_ADDRESS | ip_address | 999.999.9.99 | 0.80-0.89 | not_required | n/a | 9a4e7e98daab4d45ac13b06816faa0e4, f46a8d0f8ea94e9990501e965153416f, 9da41bf24df54a3bb5337a65b058b067, ee4aa0e2c09043f8891d53d4d78fa3cc, 0e56f41bf26044aaa7b1d21bf47ad624 | test:Public Safety:Health and Safety Guidelines:unstructured:us, test:Brokerage:Investment Strategy:unstructured:us, test:Advertising:Video Production Brief:unstructured:us, test:Investment:Compliance Document:unstructured:us, test:Advertising:Email Campaign:unstructured:us | 6 |
| IP_ADDRESS | IP_ADDRESS | ip_address | 999.9.9.9 | 0.80-0.89 | not_required | n/a | 891e7263e8eb4bce85aaa17ee6342e19 | test:Product:Author Article:unstructured:us | 1 |
| IP_ADDRESS | IP_ADDRESS | ip_address | 999.999.9.9 | 0.80-0.89 | not_required | n/a | ea6dc0c5b2434f82baf44120b60fca52 | test:Brokerage:Market Analysis Report:unstructured:us | 1 |
| LOCATION | LOCATION | location | AAA AAAAAAAA AA AA AAAAAAAA AAAA | 0.70-0.79 | not_required | n/a | 070a0bd4fe9f4925bf5b9ecc732e683c | test:Casualty:Claim Reopen Request:structured:us | 1 |



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
| test:Advertising:Ad Creative Brief:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |
| test:Advertising:biometric phenotyping data file:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 3 | 1 |
| test:Banking:Investment Strategy:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 2 |
| test:Banking:Mortgage Solutions:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 2 |
| test:Banking:Security Agreement:structured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 1 |
| test:Brokerage:Account Closing Form:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 4 |
| test:Brokerage:Account Statement:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 2 |
| test:Brokerage:Compliance Certificate:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 1 |
| test:Brokerage:Market Analysis:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |
| test:Casualty:Insurance Certificate:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 2 | 2 |
| test:Casualty:Pre-Loss Documentation:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 2 |
| test:Credit:Credit Approval Letter:unstructured:us | 2 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 6 |
| test:Credit:Debit Authorization:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 4 |
| test:Credit:Refinance Agreement:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 4 |
| test:Disability:Disability Insurance Form:unstructured:us | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0 | 1 | 1 |




### Example Errors

#### False positives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| phone | 205 | 215 | n/a | PHONE_NUMBER |
| phone | 252 | 262 | n/a | PHONE_NUMBER |
| phone | 81 | 91 | n/a | PHONE_NUMBER |
| phone | 358 | 368 | n/a | PHONE_NUMBER |
| phone | 615 | 625 | n/a | PHONE_NUMBER |

#### False negatives

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| person | 0 | 5 | n/a | first_name |
| location | 58 | 69 | n/a | county |
| location | 71 | 74 | n/a | country |
| credit_card | 200 | 219 | n/a | credit_debit_card |
| credit_card | 186 | 203 | n/a | credit_debit_card |

#### Offset mismatches

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| url/url | 116/116 | 173/141 | n/a | url/URL |
| url/url | 99/99 | 145/146 | n/a | url/URL |
| url/url | 245/245 | 301/303 | n/a | url/URL |
| url/url | 394/394 | 435/436 | n/a | url/URL |
| url/url | 275/275 | 379/380 | n/a | url/URL |

#### Wrong entity type

| Entity | Start | End | Recognizer | Source entity |
| --- | ---: | ---: | --- | --- |
| url/ip_address | 86/93 | 149/106 | n/a | url/IP_ADDRESS |
| url/ip_address | 1067/1074 | 1130/1087 | n/a | url/IP_ADDRESS |
| url/ip_address | 116/123 | 147/134 | n/a | url/IP_ADDRESS |
| url/ip_address | 412/419 | 462/432 | n/a | url/IP_ADDRESS |
| url/ip_address | 223/230 | 272/242 | n/a | url/IP_ADDRESS |



## Limitations

- Presidio-Research full compatibility report using deterministic local recognizers.
- Person and location recognizers are context-limited and are not broad NER replacements.
- Address recognition is limited to explicit generated Presidio-Research address contexts.
- Unsupported entities remain separate from analyzer failures.
