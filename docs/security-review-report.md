# Security Review Report

## Scope

This report records the focused `0.1.x` security review defined by
`docs/security-threat-model.md`. It covers raw-value lifetime, result
inspection, errors and diagnostics, callbacks, telemetry, stable text
boundaries, structured traversal, token handling, Memory and ETS vaults, model
errors, CLI errors, and authoritative report safeguards.

## Findings And Disposition

| Severity | Finding | Disposition |
| --- | --- | --- |
| High | Named protected ETS tables allowed ordinary sibling processes to read reversible mappings | Fixed with unnamed private owner tables |
| High | Default inspection of analyzer/structured/anonymizer/stream values exposed raw text, replacements, tokens, paths, or buffers | Fixed with value-safe Inspect implementations |
| Medium | Invalid UTF-8 could raise from stable regex-backed APIs | Fixed with controlled `:invalid_utf8` failures |
| Medium | Malformed spans could raise or preserve supplied expected/actual values in errors | Fixed with guarded normalization and safe reason shapes |
| Medium | Diagnostic and model errors could retain arbitrary messages, paths, causes, or exception text | Fixed by retaining only static messages, safe identifiers, reason codes, and exception classes |
| Medium | Telemetry filtering was shallow and key-denylist based | Fixed with strict measurement, metadata-key, and value allowlists |
| Low | User-facing Mix task option errors echoed invalid option values | Fixed with generic task error text |
| Release infrastructure | Canonical repository and private vulnerability-reporting destination | Completed and verified on 2026-07-21; see `SECURITY.md` |

## Compatibility

No stable module, function, arity, outer return tuple, struct field, profile,
operator, or callback was removed. Security hardening changes unstable
human-readable inspection and error details, which are explicitly outside the
`0.1.x` compatibility guarantee.

One intentional urgent security behavior change is required: the ETS
`table:` option is accepted only as a compatibility label and no longer names
an accessible ETS table. Callers which read tables directly must use
`Obscura.Vault` lookup functions instead. Stable vault functions and return
tuple shapes are unchanged.

## Test Evidence

The focused suite contains 17 tests: 7 bounded properties and 10 canary,
lifecycle, concurrency, task/report, telemetry, callback, model, and
inspection regressions. It passed independently with replay seeds `101`,
`202`, and `303`. The complete dependency-light suite passed with seed
`424242`: 567 tests, including 9 properties, with 4 optional/model tests
excluded. No real-world PII is used.

The seed `202` replay initially found a test-oracle collision: the generated
one-character token `%` also appeared in Elixir's safe map syntax. The
generator was corrected to embed the unique synthetic canary, after which all
three seeds passed. This was not an implementation leak.

## Validation

The release gate includes formatting, warning-free compilation, the complete
test suite, repeated security seeds, Credo, Dialyzer, ExDNA, ExSlop, Credence,
documentation verification and generation, Hex archive construction, and
unused-dependency checking.

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | Passed |
| `mix compile --warnings-as-errors` | Passed |
| `mix test --seed 424242` | Passed: 567 tests, including 9 properties; 4 optional/model exclusions |
| `mix test test/obscura/security --seed 101` | Passed: 17 tests, including 7 properties |
| `mix test test/obscura/security --seed 202` | Passed: 17 tests, including 7 properties |
| `mix test test/obscura/security --seed 303` | Passed: 17 tests, including 7 properties |
| `mix credo --strict --all` | Passed: 325 source files, no issues |
| `mix dialyzer` | Passed: zero errors, skips, or unnecessary skips |
| `mix ex_dna` | Passed: no duplication in 183 files |
| ExSlop | Passed: no issues |
| Credence | Passed: no issues |
| `mix obscura.docs.verify` | Passed: 573 Markdown files |
| `mix docs` | Passed without warnings |
| `mix hex.build --output /tmp/obscura-security-review.tar` | Passed; `SECURITY.md` included and model/dataset/cache assets excluded |
| `mix deps.unlock --check-unused` | Passed |

Optional real-model and accelerator validation is excluded from this
dependency-light security review.

## Residual Risks

- explicit result fields and successful rehydration contain data by design;
- detection misses can leave values in redacted output;
- custom callbacks can independently log or transmit their source argument;
- VM administrators, tracing tools, crash dumps, and hostile native code are
  outside Obscura's isolation boundary;
- BEAM and native memory cannot be guaranteed zeroized;
- Memory and ETS vaults are reversible and not encrypted persistent stores;
- third-party model runtimes can have their own logging and retention behavior;
- wide inputs and expensive models still require deployment-specific limits;
- reporters require a GitHub account to use the private advisory form, and no
  response or remediation SLA is promised.

## Release Decision

The code and automated evidence satisfy the focused hardening scope. The
canonical repository and private vulnerability-reporting destination were
configured and verified on 2026-07-21. Remaining release decisions are tracked
separately from this security review.
