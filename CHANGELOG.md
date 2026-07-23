# Changelog

All notable changes to Obscura are documented in this file.

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
