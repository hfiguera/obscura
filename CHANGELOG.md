# Changelog

All notable changes to Obscura are documented in this file.

## 0.2.0 - 2026-09-05

- Added the stable `:efficient` CPU profile with deterministic recognition and
  native spaCy person/location NER on Apple Silicon macOS and glibc Linux.
- Added versioned, verified installation, pinned native builds, and a dedicated
  export environment that does not require Presidio or its evaluator.
- Improved form/name/location boundaries using a separate development set;
  retained the original policy under the experimental `:spacy_cpu` alias.
- Added untouched application-like accuracy evaluation, sustained workload
  validation for 1–4 workers, and native release compatibility checks.
- Preserved worker capacity when a caller abandons an unused reservation.
- Updated Nx, Bumblebee, Phoenix, and supporting dependencies while preserving
  the Elixir 1.17 minimum and dependency-light core.

## 0.1.3 - 2026-07-31

- Added opt-in privacy-safe Phoenix request logging that consumes a dedicated
  redacted assign while leaving controller parameters unchanged.
- Added opt-in privacy-safe Phoenix socket and channel telemetry loggers with
  omission-first payload policies, configured topic patterns and event names,
  bounded `:fast` redaction, and raw-default-logger conflict detection.
- Lowered the minimum supported Elixir version from 1.20 to 1.17 and added
  per-minor Elixir and Erlang/OTP compatibility lanes.
- Bounded realtime parameter analysis, owned allowed event labels, rejected
  unsafe configured labels, and rejected correlation metadata keys containing
  high-confidence PII recognized by the `:fast` profile.
- Added a 4 KiB realtime parameter-text ceiling so dense socket and channel
  payloads fail closed before synchronous PII recognition.
- Hardened realtime identifier validation against prefixed structured PII and
  bounded Phoenix parameter-filter configuration before event handling.
- Made the privacy-safe HTTP logger reject startup while any corresponding
  Phoenix default logger is attached, and made the Plug validate and normalize
  its integration options during `init/1`.
- Added real Phoenix endpoint coverage and a sustained real socket/channel
  redaction regression test.
- Synchronized operational load-runner workers before starting measurement so
  scheduler contention cannot produce empty reports.

## 0.1.2 - 2026-07-24

- Improved `:fast` latency and throughput, with the largest gains on large
  inputs containing small matches.
- Prevented returned analyzer results and recursively transparent callback
  metadata from retaining large source-binary allocations.
- Deferred dependency-light NLP and context artifacts until recognizers
  actually require them.
- Hardened custom recognizer validation, metadata ownership, and sanitized
  callback failure handling while preserving the stable extension contract.
- Expanded semantic-equivalence, binary-retention, malformed-input, and
  sustained-load verification for the `:fast` profile.
- Updated real-model smoke tests to use the stable `:replace` operator option.

## 0.1.1 - 2026-07-22

- Documented LDC's confirmation that commercial use of
  `tner/roberta-large-ontonotes5` requires an LDC for-profit membership.
- Added machine-readable asset licensing metadata plus preflight and
  preparation notices for the affected `:balanced` and `:accurate` profiles.
- Preserved model-asset manifest schema version 1 while adding licensing fields
  compatibly.
- Kept `:fast` dependency-light and unaffected by the TNER requirement.

## 0.1.0 - 2026-07-21

Initial public release.

- Added stable `:fast`, `:balanced`, and `:accurate` detection profiles.
- Added validated anonymization operators, structured redaction, reversible
  vaults, rehydration, and LLM workflow helpers.
- Added optional local model preparation with reusable runtimes and structured
  diagnostics.
- Added authoritative accuracy and operational evidence, security hardening,
  public API contracts, and package documentation.
