# Authoritative Benchmarks

This directory contains the release-relevant benchmark evidence promoted into
the public release tree. New and unpromoted runs use the ignored
`eval/reports/` working directory.

The source of truth is `manifest.json`. A report is authoritative only when it
has a valid manifest entry and its current SHA-256 hashes match that entry.
Names such as `best`, `final`, or a high experiment version do not grant
authoritative status.

Promotion rejects skipped reports, fake/gold-derived NER, mismatched Markdown
metrics, missing dataset fingerprints, missing model revision/hash evidence,
and report payloads containing non-omitted raw `text` or `value` fields.

External baselines use a distinct `external_baseline` manifest entry type. They
are never stable Obscura profiles. Presidio promotion additionally requires a
pinned Python lock, complete runtime/model identity, shared protocol hashes,
ordered sample-ID fingerprint, entity-policy fingerprint, scoring fingerprint,
and at least two measured repetitions with identical accuracy counts.

Working and failed reports may be retained locally under `eval/reports/` for
engineering analysis, but they are not product claims. Historical development
reports are not part of the public release tree.
