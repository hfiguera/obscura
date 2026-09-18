# English accuracy evaluation

Redact's Linux pipeline covers more full addresses in this synthetic corpus,
while `:balanced` finds more exact person spans and all Obscura baselines handle
the tested phone boundaries better. This is evidence for specific tradeoffs,
not a general accuracy winner.

## Scope and audit

The corpus was newly authored for this evaluation, with 40 development rows from
20 families and 144 frozen test rows from 48 different families. No evaluated
model predictions were used to write labels or tune the test. There are 114 unique
test texts: several variants repeat text, so 144 is not an independent sample size.
The primary test has 132 rows from 44 families and 195 gold spans across nine types;
12 supplemental rows cover four other types. The 27 negative rows represent only
nine families. Test lengths range from 53 to 3,672 UTF-8 bytes.

Text and annotations were authored by the assistant, not independently collected
or reviewed by human annotators. The test uses different templates and name pools
from development, but common generation conventions remain. These are fresh,
application-like synthetic examples, not a probability sample of real traffic.
English-only scope does not test Redact's multilingual value. The declared Gretel
training source overlaps Obscura's previous evaluation source; no existing Gretel
score is presented as independent evidence for Redact.

[MAPPING.md](MAPPING.md) was frozen before test inference. All systems receive the
same text. Redact runs its default confidence 0.6, default labels and deterministic
recognizers. Name/address components are normalized to Obscura spans; exposure
uses the original components, so merging cannot conceal an unmasked gap.

`python3 eval/redact_english/analyze_accuracy.py` recomputes all 18 development/test
reports, verifies corpus/mapping/worker hashes, checks byte boundaries and confirms
zero reported inference errors. Obscura's three profiles produce identical raw
and normalized spans across both hosts for all 184 development and test rows.
An absent SDK error does not make Mac CPU Redact's neural output valid; see
[DIAGNOSIS.md](DIAGNOSIS.md).

## Exact primary spans

| System | TP | FP | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `:fast`, either host | 73 | 7 | 122 | 0.9125 | 0.3744 | 0.5309 |
| `:efficient`, either host | 153 | 29 | 42 | 0.8407 | 0.7846 | 0.8117 |
| `:balanced`, either host | 155 | 25 | 40 | 0.8611 | 0.7949 | 0.8267 |
| Redact Linux CPU | 161 | 19 | 34 | 0.8944 | 0.8256 | 0.8587 |
| Redact Mac default, acceleration unverified | 155 | 20 | 40 | 0.8857 | 0.7949 | 0.8378 |
| Redact Mac CPU, invalid neural output | 48 | 50 | 147 | 0.4898 | 0.2462 | 0.3276 |

The Linux lead over `:balanced` is 0.0320 F1. Resampling the 44 template families
jointly across systems (2,000 draws, seed 20260913) gives a central 95% difference
range of −0.0903 to +0.1591. Against `:efficient`, the observed +0.0470 has a range
of −0.0721 to +0.1629. These describe sensitivity to this synthetic family mix,
not population confidence intervals or evidence of general superiority.

## Per-entity exact F1 on Linux

| Entity | Gold | fast | efficient | balanced | Redact CPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| Person | 78 | 0.1149 | 0.8299 | 0.9467 | 0.9241 |
| Location, including full address | 42 | 0.0000 | 0.5714 | 0.4051 | 0.9524 |
| Email | 27 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
| Phone | 15 | 1.0000 | 1.0000 | 1.0000 | 0.0000 |
| US SSN | 6 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
| Credit card | 9 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
| IP address | 6 | 0.9091 | 0.9091 | 0.9091 | 0.0000 |
| URL | 6 | 0.5000 | 0.5000 | 0.5000 | 1.0000 |
| IBAN | 6 | 0.6667 | 0.6667 | 0.6667 | 1.0000 |

Each type has few templates. All phone examples use parentheses and all primary
IP examples are IPv6. These results cannot characterize every phone format or
IPv4. Redact's phone misses are exact-boundary failures: it omits the opening
parenthesis while masking the digits. They are not 15 fully exposed phone numbers.

## Exposure and negative text

Coverage counts Unicode letters/digits inside each primary gold span, using the
union of original detections regardless of predicted type. A wrong type can
protect content while failing typed scoring. Reports also record covered
non-whitespace characters, which include punctuation.

| System | Fully covered / 195 | Partially exposed | Fully exposed | Alphanumeric characters covered |
| --- | ---: | ---: | ---: | ---: |
| fast | 76 | 1 | 118 | 1245 / 2685 |
| efficient | 159 | 16 | 20 | 2132 / 2685 |
| balanced | 158 | 13 | 24 | 2096 / 2685 |
| Redact Linux CPU | 177 | 2 | 16 | 2530 / 2685 |
| Redact Mac default | 171 | 3 | 21 | 2478 / 2685 |
| Redact Mac CPU, invalid | 54 | 18 | 123 | 1355 / 2685 |

Every pipeline leaves all 27 negative rows unchanged. Nine negative families are
too few to establish a production false-positive rate. False positives still occur
in positive documents, including extra or partial spans counted in the exact table.

The 21 positive long-document rows contain 48 gold spans. Linux Redact fully
covers 39 and fully exposes nine, with exact F1 0.8276; efficient covers 41, partly
exposes three and fully exposes four, with F1 0.8817. Balanced covers 35 and fully
exposes 13, with F1 0.8434. These documents cross model windows but are only a few
kilobytes; they do not validate arbitrary document lengths.

## Representative synthetic cases

- `test-14-0`: Redact reconstructs the full postal address from its components;
  efficient finds the street name and city, balanced finds city and state. Full
  address coverage is a concrete advantage of Redact's complete pipeline here.
- `test-07-0`: the gold phone is `(202) 555-0121`; Redact masks `202) 555-0121`.
  Exact scoring fails while all identifying digits are covered. Mapping remains
  frozen; no boundary repair was added after observing this result.
- `test-09-0`: in a JSON contact record, Linux Redact and efficient miss the person;
  balanced finds the full name. All detect the email.
- `test-19-0`: Linux Redact misses `2001:db8::3a` in a log field; efficient and
  balanced find it. This is an exposure failure, unlike the phone punctuation gap.
- `test-38-0`: Linux Redact detects the phone but misses the person inside a long
  support passage; efficient and balanced find both.

Examples come from the synthetic input corpus. JSON reports retain only entity
types, offsets, identifiers and aggregate measurements, not detected values.

## Supplemental and unsupported entities

Date/time and bare-domain detection have no direct label in Redact's evaluated
taxonomy. All six supplemental occurrences stay exposed; fast and efficient cover
both categories, while balanced covers the domain but misses the date examples.
Organization is available in Redact but excluded by its published default; Linux
Redact leaves all three exposed, while balanced covers them. Mac default partly
masks them as other types; this is not organization support. Generic government
ID is a Redact label without a canonical primary counterpart here; Linux Redact
covers its three supplemental examples, while the Obscura profiles leave them
exposed. Other Redact-specific identifiers are not independently evaluated.

Fast has no location NER and only limited deterministic person recognition. Those
gold spans remain in its denominator. Scores assess the requested task coverage,
not just each profile's favorable supported subset. See the ready metadata for
each Obscura profile's full supported entity list.
