# Evaluation Entity Taxonomy

This mapping is implemented in `Obscura.Eval.EntityMapping`.
Mapping an external label does not mean every profile recognizes it. Stable
profile coverage is defined by `Obscura.Profile` and enforced during evaluation
by `Obscura.Eval.Profile`.

| Presidio / Presidio-Research | Obscura | Stable profile coverage |
| --- | --- | --- |
| `EMAIL_ADDRESS` | `:email` | `:fast`, `:balanced`, `:accurate` |
| `PHONE_NUMBER` | `:phone` | `:fast`, `:balanced`, `:accurate` |
| `CREDIT_CARD` | `:credit_card` | `:fast`, `:balanced`, `:accurate` |
| `IBAN_CODE` | `:iban` | `:fast`, `:balanced`, `:accurate` |
| `US_SSN` | `:us_ssn` | `:fast`, `:balanced`, `:accurate` |
| `IP_ADDRESS` | `:ip_address` | `:fast`, `:balanced`, `:accurate` |
| `DOMAIN_NAME` | `:domain` | `:fast`, `:balanced`, `:accurate` |
| `URL` | `:url` | `:fast`, `:balanced`, `:accurate` |
| `PERSON` | `:person` | `:fast`, `:balanced`, `:accurate` |
| `ORGANIZATION` | `:organization` | `:balanced`, `:accurate` |
| `GPE` | `:location` | `:fast`, `:balanced`, `:accurate` |
| `LOCATION` | `:location` | `:fast`, `:balanced`, `:accurate` |
| `STREET_ADDRESS` / `ADDRESS` | `:street_address` | `:fast` |
| `DATE_TIME` | `:date_time` | `:fast` |
| `TITLE` | `:title` | `:fast` |
| `NRP` | `:nationality` | Mapped; no stable profile coverage |
| `AGE` | `:age` | Mapped; no stable profile coverage |
| `ZIP_CODE` | `:zip_code` | Mapped; no stable profile coverage |
| `US_DRIVER_LICENSE` | `:us_driver_license` | Mapped; no stable profile coverage |

The internal `:regex_only` compatibility profile scores the eight structured
entities at the top of the table. Every evaluation profile reports unsupported
entities separately instead of silently treating them as product failures.
