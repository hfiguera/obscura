# Frozen comparison policy v1

Freeze before test inference. No thresholds are selected from the test set.

Primary entities: person, location, email, phone, us_ssn, credit_card,
ip_address, url and iban. Full names exclude titles. A complete postal address
is one location span; individual place mentions are individual locations.
Repeated mentions are separately annotated. Offsets are UTF-8 bytes.

Obscura is requested to emit these nine types plus street_address where supported.
Its street_address predictions are mapped to location. Redact runs its complete
published default pipeline, including its deterministic recognizers, confidence
0.6 and default label set (ORG excluded). Additional output types are reported
separately and remain visible to the redaction-coverage/negative-text checks.

Redact mapping:
- GIVEN_NAME/SURNAME → person. Merge adjacent name components separated only by
  whitespace (at most eight UTF-16 units); no inserted words or extrapolated spans.
- STREET_NAME/BUILDING_NUMBER/SECONDARY_ADDRESS/CITY/STATE/ZIP_CODE → location.
  Merge a sequence separated only by whitespace/commas when it contains a street
  name or building number. City lists without an address anchor stay separate.
- EMAIL/PHONE/CREDIT_CARD/IP_ADDRESS/URL/SSN → corresponding primary entity.
- BANK_ACCOUNT → iban only if the detected text passes IBAN shape and mod-97.
  Other bank account detections remain unmapped, not mislabeled as IBAN.
- Other labels remain unmapped; they do not become a supported category by name.

Convert each SDK UTF-16 offset to a UTF-8 byte boundary and validate against its
returned substring before normalization. Preserve original component spans for
privacy coverage. Never count a merged span as evidence that its gaps were masked.

Exact metrics require canonical type and both boundaries to match. Deduplicate
identical predictions. Report precision, recall, F1, TP/FP/FN and per-entity counts.
Privacy exposure uses the union of original prediction spans: for each gold span,
count covered Unicode letters/digits. Classify fully covered, partially exposed,
or fully exposed. Also report strict non-whitespace character coverage. This keeps
punctuation-only gaps distinct from exposed identifying letters/digits. Wrong-type
masking can protect text while still failing the typed exact score.

Negative rows report whether any original detection changed text, plus detection
count. Supplemental rows test date_time, organization, bare domain and generic
government identifiers; report them separately, including unsupported types.
The primary leaderboard never silently drops an unsupported primary gold span.

The corpus is newly authored synthetic text with distinct development/test
templates and name pools. Repeated negative variants share text and must not be
treated as independent observations; report family counts and do not manufacture
confidence intervals from duplicated templates. No claim of production or broad
English superiority follows from this small corpus alone.
