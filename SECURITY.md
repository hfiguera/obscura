# Security Policy

Obscura handles data that callers consider sensitive. Security reports are
welcome, but the project does not yet have a configured private reporting
channel and must not be publicly released until one exists.

## Supported Versions

Obscura is pre-release. Only the latest `0.1.x` release candidate or release
receives security fixes. Development snapshots and older pre-release revisions
are not supported after a replacement is available.

| Version | Security support |
| --- | --- |
| Latest `0.1.x` | Supported after publication |
| Older or unreleased revisions | Not supported |

## Private Reporting Blocker

No repository remote, security-advisory URL, or private security email address
is configured in this checkout. There is therefore no truthful private
destination to publish here.

Before publishing Obscura, the repository owner must:

1. configure the canonical source repository;
2. enable that host's private vulnerability-reporting or security-advisory
   feature;
3. verify that a reporter who is not a maintainer can open a private report;
4. replace this blocker with the exact private reporting link;
5. add the same link to the Hex package metadata and README.

For GitHub, the concrete configuration action is to enable **Private
vulnerability reporting** in the repository security settings and verify the
repository's private advisory form. This text does not imply that a GitHub
repository currently exists.

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

After a private channel is configured, maintainers will acknowledge reports
and coordinate validation, remediation, release timing, and disclosure through
that channel. Obscura does not promise a response or remediation SLA while it
is unpublished. Severity, exploitability, affected versions, and disclosure
timing will be evaluated per report.

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
