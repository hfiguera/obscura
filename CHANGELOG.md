# Changelog

All notable changes to Obscura are documented in this file.

## Unreleased

- Added opt-in privacy-safe Phoenix socket and channel telemetry loggers with
  omission-first payload policies, configured topic patterns and event names,
  bounded `:fast` redaction, and raw-default-logger conflict detection.
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
