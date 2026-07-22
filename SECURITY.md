# Security Policy

Obscura handles data that callers consider sensitive. Security reports are
welcome. Report suspected vulnerabilities privately through
[GitHub Private Vulnerability Reporting](https://github.com/hfiguera/obscura/security/advisories/new).
Do not open a public issue for an undisclosed vulnerability.

## Supported Versions

Obscura is pre-release. Only the latest `0.1.x` release candidate or release
receives security fixes. Development snapshots and older pre-release revisions
are not supported after a replacement is available.

| Version | Security support |
| --- | --- |
| Latest `0.1.x` | Supported after publication |
| Older or unreleased revisions | Not supported |

## Private Reporting

1. Sign in to GitHub.
2. Open the [private vulnerability report form](https://github.com/hfiguera/obscura/security/advisories/new).
3. Select **Report a vulnerability** and provide a minimal synthetic
   reproduction.
4. Continue discussion through the resulting private security advisory.

The canonical repository is `https://github.com/hfiguera/obscura`. GitHub's
Private Vulnerability Reporting setting and advisory route were verified on
2026-07-21. GitHub requires reporters to sign in before opening the form.

Do not include raw PII, credentials, production vault contents, model prompts,
or private datasets in a report. Use minimal synthetic reproductions and
canary values.

## Report Contents

A useful private report includes:

- affected Obscura version or commit;
- affected stable or experimental API;
- dependency and runtime versions;
- operating system and optional backend, when relevant;
- minimal synthetic reproduction;
- expected and observed impact;
- whether the issue is already public;
- suggested mitigation, if known.

## Handling And Disclosure

Maintainers will acknowledge reports and coordinate validation, remediation,
release timing, and disclosure through the private advisory. Obscura does not
promise a response or remediation SLA. Severity, exploitability, affected
versions, and disclosure timing will be evaluated per report.

Reporters should avoid public disclosure until a fix or coordinated disclosure
date is agreed. Security fixes may override the normal compatibility
deprecation period when retaining behavior would expose data or corrupt it.

## Scope

In scope:

- raw-value leakage from errors, diagnostics, logs, telemetry, inspections,
  reports, or callback failures;
- incorrect byte boundaries that expose only part of a sensitive value;
- unauthorized vault lookup or cross-session access;
- unsafe token parsing or rehydration;
- denial of service through documented public inputs;
- unsafe optional model/checkpoint loading behavior;
- dependency or packaged-asset integrity failures.

Out of scope:

- detection misses that are already documented model or recognizer
  limitations, unless Obscura claims the entity was safely redacted;
- callers intentionally logging raw inputs or explicitly reading raw result or
  vault fields;
- compromise of the BEAM VM, host administrator, debugger, or dependency
  supply chain;
- regulatory or compliance certification;
- guaranteed memory zeroization.

See `docs/security-threat-model.md` and `docs/known-limitations.md` for the
current security model and residual risks.
