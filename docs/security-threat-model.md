# Security Threat Model

## Purpose And Status

This threat model defines Obscura's security boundary for the `0.1.x`
early-release line. It covers raw PII lifetime, anonymization, reversible vaults,
model execution, observability, callbacks, structured data, command output,
and benchmark reports.

Obscura reduces accidental disclosure. It is not a secure enclave, encrypted
secret store, data-loss-prevention service, compliance product, or guarantee
that every sensitive value will be detected.

## Protected Assets

The primary assets are:

- source text and structured leaf values;
- detected span text and nearby context;
- anonymizer intermediate source slices;
- replacement values, deterministic salts, and pseudonym tokens;
- vault entries and rehydrated output;
- LLM prompts and responses passed through Obscura;
- model tokenizer inputs, token text, logits, and detected spans;
- credentials, paths, and checkpoint details supplied during optional setup;
- private datasets and benchmark examples.

Offsets, entity labels, aggregate counts, durations, stable profile names, and
sanitized backend identifiers are not confidential by default. They can still
be sensitive in a caller's domain and must be governed by that caller.

## Actors And Trust Boundaries

| Actor or boundary | Trust assumption |
| --- | --- |
| Application caller | Trusted to choose inputs, profiles, operators, retention, and output sinks |
| Custom recognizer/operator/language callback | Application code, but untrusted return values, exceptions, throws, and exits |
| Vault owner process | Trusted holder of reversible mappings |
| Other ordinary BEAM processes | Must not read ETS mappings through normal ETS operations |
| VM administrator, debugger, tracing tool, or code with process-inspection privileges | Trusted; outside Obscura's isolation boundary |
| Telemetry and Logger handlers | Trusted sinks that receive only the documented sanitized Obscura metadata |
| Optional model, tokenizer, backend, checkpoint, and native dependency | Trusted local code/assets after caller verification |
| CLI filesystem and stdout | Caller-controlled explicit output sinks |
| Benchmark tooling | Development-only trusted tooling; authoritative promotion rejects raw-value fields |

The most important boundary is between explicit result access and incidental
observation. Public result fields may intentionally contain source or output
text. Default `Inspect` output, errors, diagnostics, logs, telemetry, and
reports must not reproduce that content.

## Data Flow And Lifetime

### Analysis

Raw text enters the caller process and is passed to recognizers. Deterministic
recognizers, NLP artifacts, context enhancement, and model adapters may hold
references to the original binary, slices, tokens, and model outputs during
the call.

Analyzer results contain exact byte offsets. With `include_text: true`, which
is the compatibility default, `Obscura.Analyzer.Result.text` intentionally
contains the detected source text. Accepted text is detached when retaining it
as a sub-binary would keep an unrelated larger source binary alive. Callers
that do not need text should use `include_text: false`; built-in recognizers
then avoid materializing `Result.text`. The option does not sanitize metadata.
Documented parser metadata can contain normalized PII, and trusted custom
recognizers control metadata they return. Callback result fields are validated
against the public result contract; function-bearing, malformed, improper, or
excessively nested terms are rejected with a sanitized callback error.
Escaping borrowed binaries in accepted recursively transparent metadata and
explanations are detached so they do not retain unrelated parent inputs. These
controls reduce binary retention but do not guarantee memory zeroization. Safe
`Inspect` output omits result text, explanations, context words, and metadata.

### Anonymization

The anonymizer validates every operator configuration before replacement,
validates source byte ranges, extracts source slices, invokes the selected
operator, and constructs a new output binary. Source slices and output parts
exist until the call and garbage collection release them.

Anonymizer result text and item replacements are explicit outputs. Their
default `Inspect` implementations expose only status, counts, byte lengths,
entity types, operators, and offsets. Custom operators receive the source
value by design but receive only the entity from Obscura's context.

### Structured Data, Logger, Plug, And LLM Helpers

Structured redaction recursively visits supported maps, proper lists, and
opted-in structs. Tuples and unsupported terms remain opaque. A depth limit
prevents unbounded recursion. Invalid UTF-8 leaves and improper lists return
controlled errors.

Logger helpers are safe only to the extent that configured recognizers and
field policies detect the values. They do not make arbitrary terms
non-sensitive. Plug and LLM helpers retain raw request/message data in the
caller's original structures unless the caller replaces or discards it.

### Vaults And Rehydration

Memory and ETS vaults store raw values for reversible pseudonymization. Memory
vaults hold mappings in GenServer state. ETS vaults use unnamed private tables
owned by the vault process. Ordinary sibling processes cannot read those
tables directly. All supported lookup goes through serialized GenServer calls.

`clear/1` removes accessible mappings and counters. Stopping the owner removes
its state and ETS tables. These operations drop references; they are not
cryptographic erasure. Tokens are capabilities only when combined with access
to the matching vault, but they are hidden from default `Inspect` output.

Callers control vault supervision, ownership, session isolation, retention,
clear/stop timing, node placement, and whether rehydrated values leave the
trusted boundary.

### Models And Checkpoints

Local model paths tokenize raw text and may copy it into native runtime,
accelerator, or backend-managed memory. Model adapters sanitize execution
failures to stable reason tags and exception classes; they do not return
exception messages, stack arguments, raw outputs, or model input.

Obscura does not control memory retention inside Nx, Bumblebee, Emily, EXLA,
Ortex, Tokenizers, Safetensors, or operating-system drivers. Models and assets
must be pinned, hash-verified, license-reviewed, and prepared explicitly.

### Observability And Reports

Telemetry applies strict measurement and metadata key allowlists. Values are
limited to numbers, atoms, booleans, or lists of safe identifiers. Binary and
unknown values become `:redacted`; unknown keys are dropped.

Diagnostics discard paths and arbitrary message/remediation text at
construction, reduce nested causes to safe reason codes, and redact binary
metadata. Anonymizer errors retain only known atom fields and bounded safe
metadata.

CLI detection exposes source text only after the explicit `--include-text`
option. CLI redaction intentionally writes redacted output, which can still
contain missed PII. Authoritative benchmark promotion rejects raw-value keys;
historical development reports are not production logging sinks.

## Threats And Controls

| Threat | Control | Residual risk |
| --- | --- | --- |
| Raw text appears in default inspection | Safe Inspect implementations for raw-bearing stable and model structs | Explicit field access and `Map.from_struct/1` still expose fields |
| Callback exception leaks source arguments/message | Callback trapping and reason sanitization | Callback code itself can log or transmit its input |
| Callback result retains source through malformed or opaque metadata | Public result validation, recursive binary ownership, and rejection of function-bearing metadata | Callback code can retain or transmit input through external state |
| Invalid UTF-8 crashes regex/model paths | Stable text boundaries return `:invalid_utf8` | Native dependencies can still fail internally |
| Malformed spans return expected/actual source values | Span normalization and value-safe reason conversion | Callers must still supply correct exclusive byte offsets |
| Telemetry receives nested/raw metadata | Strict measurement/key/value allowlists | Application handlers can correlate safe identifiers with other data |
| Sibling process reads ETS vault | Unnamed `:private` ETS tables and GenServer API | VM administrators and tracing/debug tooling remain trusted |
| Token error reveals token content | Errors report only token shape and policy code | Explicit successful output and rehydration contain values |
| Deep or improper structures exhaust/crash traversal | Proper-list checks and configurable maximum depth | Wide but shallow structures can still consume caller resources |
| Model exception/logit output leaks input | Exception class/reason tags only | Third-party runtime logging is outside Obscura's control |
| Report publishes raw examples | Authoritative promotion schema and raw-key rejection | Historical/local files require normal filesystem controls |
| Cleared value remains in memory | References and tables are removed | BEAM/native memory cannot be guaranteed zeroized |

## BEAM Memory Limitation

BEAM binaries may be shared between processes, referenced by sub-binaries,
copied into messages, retained until garbage collection, or copied into native
libraries. Dropping references, clearing a vault, stopping a process, or
deleting an ETS table does not prove that every byte was overwritten.

Obscura cannot guarantee secure memory zeroization. Workloads requiring
cryptographic erasure, hardware isolation, or protection from VM
administrators need a different execution boundary.

## Attacker Capabilities Considered

The review considers callers or integrated callbacks that provide malformed
types, invalid UTF-8, invalid offsets, adversarial token strings, deeply nested
values, invalid operator options, callback failures, and concurrent vault
requests. It also considers accidental logging or inspection by application
developers.

It does not defend against arbitrary code execution in the VM, hostile NIFs,
runtime tracing by an administrator, a compromised dependency, kernel access,
or a caller deliberately exporting explicit raw fields.

## Operational Requirements

Before deployment, callers must:

1. choose a profile using representative heldout data;
2. disable result text where it is not required;
3. keep raw result and vault structs out of generic serializers;
4. supervise vaults and define retention and cleanup;
5. restrict VM debugging, tracing, remote shell, crash dump, and ETS access;
6. review telemetry handlers and log processors;
7. pin and verify optional assets and dependencies;
8. load-test depth, width, memory, and model latency limits;
9. handle detection misses as expected risk;
10. route suspected vulnerabilities through the private process in
    `SECURITY.md` rather than a public issue.

## Verification Evidence

Security regression and property tests live under `test/obscura/security/`.
They use unique synthetic canaries and bounded generators for Unicode, invalid
UTF-8, spans, operators, tokens, nested data, vault concurrency, lifecycle,
private ETS access, callbacks, telemetry, diagnostics, inspection, and model
errors. The dependency-light CI gate runs these tests together with the
repository's static-analysis, documentation, and authoritative-manifest checks.
