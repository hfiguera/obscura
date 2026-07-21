# Public API Stability

This document defines the supported caller contract for the Obscura `0.1.x`
release line. The machine-readable baseline is
`priv/obscura/public_api.exs`. Contract tests verify that its functions,
struct fields, behaviours, profiles, operators, and error codes remain
available.

Elixir makes every exported function callable, but callability does not make a
module public API. Obscura supports only modules classified as stable or
experimental in the baseline. All other application modules are internal.
ExDoc filters internal modules from the published reference.

## Stability Classes

| Class | Compatibility promise |
| --- | --- |
| Stable | Protected by the `0.1.x` compatibility policy and contract tests |
| Experimental | Documented for evaluation, but signatures, options, structs, and behavior may change |
| Internal | Not supported for direct caller use and may change without notice |
| Deprecated | Still supported during the documented transition period |

There are currently no deprecated APIs. The stable product profiles are
`:fast`, `:balanced`, and `:accurate`.

## Stable Module Inventory

The following table lists stable caller entry points. Functions not listed in
the machine-readable baseline remain internal even when their module is stable.
Default-argument functions are listed at every exported arity.

| Area | Stable modules and entry points |
| --- | --- |
| Primary API | `Obscura.analyze/1,2`, `analyze_many/1,2`, `anonymize/2,3`, `redact/1,2`, `rehydrate/1,2` |
| Analyzer facade | `Obscura.Analyzer.analyze/1,2`, `analyze_many/1,2` |
| Analyzer results | `Obscura.Analyzer.Result`, `Obscura.Analyzer.Explanation` |
| Anonymization | `Obscura.Anonymizer.anonymize/2,3`, `validate_options/1`; result, item, and error structs |
| Profiles | `Obscura.Profile` query, preflight, validation, description, and preparation functions; `Obscura.Profile.Runtime` values |
| Diagnostics | `Obscura.Diagnostic` codes, constructors, normalization, formatting, map conversion, and remediation |
| Recognizer extension | `Obscura.Recognizer` callbacks and `Obscura.Recognizer.PatternDefinition.new!/1` |
| Operators | `Obscura.Operator.Custom` callback and `Obscura.Operator.Hash.verify/2` |
| Structured data | `Obscura.Structured.analyze/1,2`, `redact/1,2`; structured result and item structs |
| Protocol | `Obscura.Redactable.redact/2` and the documented derive contract |
| Logging and Plug | `Obscura.Logger` helpers and the `Obscura.Phoenix.Plug` Plug callbacks |
| LLM workflows | All `Obscura.LLM` redaction and rehydration functions |
| Streaming | `Obscura.Stream.Rehydrator.new/1`, `feed/2`, and `flush/1` |
| Vaults | `Obscura.Vault`; `Obscura.Vault.Memory` and `ETS` startup/child specs; `Obscura.Vault.Backend`; `Obscura.Vault.Entry` |
| Rehydration | `Obscura.Rehydrator` and `Obscura.Rehydrator.Structured` |
| Language | `Obscura.Language` and the `c:Obscura.Language.Detector.detect/2` callback |
| Capabilities | Capability loading and profile/asset lookup functions in `Obscura.Capabilities` |

Stable Mix commands are:

- `mix obscura.detect`;
- `mix obscura.docs.verify`;
- `mix obscura.redact`;
- `mix obscura.profile.check`;
- `mix obscura.profile.prepare`.

Evaluation, fixture, report-generation, benchmark-promotion, and development
Mix tasks are project tooling rather than application API.

## Experimental Module Inventory

The following entry points are intentionally outside the `0.1.x` compatibility
promise:

- `Obscura.Tiktoken` and `Obscura.Tiktoken.Encoding`;
- `Obscura.NLP.Artifacts`, `Obscura.NLP.Engine`, and the Bumblebee engine;
- low-level `Obscura.Recognizer.NER`, fake serving, and serving construction;
- `Obscura.Recognizer.GLiNER` and its Ortex adapter;
- the optional `ex_phone_number` validator adapter;
- native Privacy Filter recognition, serving, checkpoint validation, and setup.

## Stable Profile Contracts

The `:balanced` and `:accurate` names, requirements, behavior, and preparation
contracts are stable under the `0.1.x` compatibility promise. Their optional
third-party model assets are not bundled or licensed by Obscura; stable API
classification is not a grant of checkpoint rights. See
`docs/model-asset-licensing.md`.

## Experimental Profile Contracts

`:hybrid_gliner_urchade` and `:openmed_pii` remain experimental.
`:hybrid_gliner_urchade` is the public
CPU-only alternative with a clearer provenance chain, but lower measured
accuracy. `:openmed_pii` has specialist evidence but unresolved precision, licensing,
tail-latency, and retained-memory concerns.

All `Obscura.Eval.*`, `Obscura.Fixtures.*`, engine, registry, routing,
normalization, validator, model-math, and Mix-task implementation modules not
listed above are internal. Their exported functions are not supported caller
contracts.

## Function And Return Contracts

Stable functions preserve:

- their module, name, and arity;
- documented accepted input categories;
- the outer success/error tuple shape;
- documented stable result and error structs;
- byte-offset semantics for detection and anonymization;
- input-order preservation for batch APIs;
- the rule that ordinary analysis does not prepare or download models.

Adding a new function or accepting additional inputs is compatible. Tightening
an accepted stable input, changing `{:ok, value}` into another outer shape, or
replacing a documented error struct is breaking.

Configuration failures at caller boundaries return error tuples. Functions
whose established Elixir convention is construction-time failure, such as
`PatternDefinition.new!/1`, retain their explicit bang semantics.

## Struct Contracts

The baseline records stable fields for:

- analyzer result and explanation;
- anonymizer result, item, and error;
- structured result and item;
- profile descriptor and prepared runtime;
- diagnostic;
- vault entry.

Removing or renaming a stable field, changing its documented meaning, or
changing its fundamental type is breaking. Adding a field is compatible.
Callers must pattern-match only fields they consume and must not compare
`Map.from_struct/1` output for exact key equality.

`Obscura.Profile.Runtime` and `Obscura.Stream.Rehydrator` are state-carrying
values. Callers may pass them back to documented functions but must not mutate
their implementation fields. Runtime resource and backend metadata contents
are informative and additive, not stable schemas.

All `metadata` maps are additive extension points. Their presence is stable;
individual keys are stable only when explicitly documented elsewhere.

## Error Contracts

`Obscura.Anonymizer.Error` guarantees these fields:

- `code`;
- `operator`;
- `field`;
- `reason`;
- `metadata`.

Its stable codes are recorded in the baseline. New codes may be added.
Existing codes will not be removed or repurposed in `0.1.x`.

`Obscura.Diagnostic` similarly guarantees its documented fields and the codes
returned by `Obscura.Diagnostic.codes/0`. Diagnostic `code`, component/profile
identifiers, and the sanitized `to_map/1` shape are machine-readable.

Human-readable exception messages, diagnostic messages, remediation wording,
inspection formatting, nested causes, and metadata ordering are not stable.
Applications must branch on codes and fields, never rendered text.

Errors, diagnostics, telemetry, and reports must not contain source PII,
replacement values, callback exception messages, credentials, or salts.
Stable text boundaries reject invalid UTF-8 with controlled error tuples.
Default inspection of raw-bearing result/state structs is deliberately
value-safe; explicit fields and caller-requested serialization retain their
documented data.

## Profile Contracts

The stable profile names are:

| Profile | Stable intent | Optional requirements |
| --- | --- | --- |
| `:fast` | Dependency-light structured PII detection | Optional phone parser |
| `:balanced` | Practical deterministic plus general-NER profile | Nx, Bumblebee, backend, pinned TNER assets |
| `:accurate` | Highest measured general accuracy with conditional location recovery | Nx, Bumblebee, backend, two pinned model/tokenizer pairs |

The names, classification, dependency/asset reporting, explicit preparation,
and no-implicit-download rule are stable. Downloads require
`allow_download: true`; cache-only behavior is the default and `offline: true`
forbids network access. Preparation returns a reusable runtime or a structured
diagnostic and supports bounded timeouts and safe progress events. Benchmark
values may change as new evidence is promoted. Changing a profile's intended
category, silently adding a network operation, or requiring new assets without
a release note is breaking.

`Obscura.Profile.Preparer` is the stable supervised ownership path. It prepares
once, retains the runtime, exposes readiness/failure, and supports waiting and
progress subscriptions. Subscriber message payloads and progress maps are
additive; applications should match only the documented event/status keys they
consume.

Model licenses are not granted by Obscura. TNER and OpenMed require independent
license review, as documented in `docs/known-limitations.md`.

The experimental product aliases are:

| Profile | Evaluation purpose | Why it is not stable |
| --- | --- | --- |
| `:hybrid_gliner_urchade` | CPU-only GLiNER alternative | Lower measured accuracy and exported local asset contract |
| `:openmed_pii` | Native OpenMed/Nemotron PII specialist | Low precision, high tail latency, unclear licensing, and inconclusive retained memory |

Their explicit-preparation and analyzer behavior may change without the stable
deprecation window. Applications must branch on
`Obscura.Profile.classification/1` rather than assuming every accepted alias is
stable.

## Operator Schemas

Every operator map requires an atom `:type`. Unknown operators and unknown
operator keys return `%Obscura.Anonymizer.Error{}` before any replacement.

| Type | Required keys | Optional keys and defaults |
| --- | --- | --- |
| `:replace` | `:type` | `value: "[REDACTED]"` |
| `:redact` | `:type` | none |
| `:mask` | `:type` | `char: "*"`, `keep_last: 0` |
| `:hash` | `:type` | `algorithm: :sha256`, `mode: :secure`; deterministic mode also requires `:salt` |
| `:pseudonymize` | `:type` | `vault: nil`, with a vault required from config or call options |
| `:custom` | `:type`, `:module` | `options: %{}` |

Changing a default, accepting a formerly invalid ambiguous value, changing the
versioned hash representation, or changing preflight-before-replacement
semantics is breaking.

## Behaviour Contracts

`Obscura.Recognizer` requires `name/0`, `supported_entities/0`, and
`analyze/2`. `entity/0` and `analyze_many/2` are optional. Recognizers return a
result list, `{:ok, result_list}`, or `{:error, reason}` using byte offsets.

`Obscura.Operator.Custom` requires `apply/3`. It receives source text, the safe
documented context, and its configured options. Valid results are
`{:ok, replacement}` and `{:ok, replacement, metadata}`. Callback failures,
raises, throws, exits, and malformed returns become sanitized errors.

`Obscura.Language.Detector` requires `detect/2`.

`Obscura.Vault.Backend` defines the GenServer startup and call callbacks used by
vault implementations.

Adding a new required callback or changing a callback arity or return shape is
breaking. Adding an optional callback is compatible.

## Stable Option Schemas

### Analyze

Core stable options and defaults are:

| Option | Type | Default |
| --- | --- | --- |
| `:profile` | stable alias, experimental alias, implementation atom, or prepared runtime | `:regex_only` compatibility default |
| `:entities` | list of atoms | profile-supported entities |
| `:language` | supported atom/string | `:en` |
| `:score_threshold` | number from 0 through 1 | `0.0` |
| `:explain` | boolean | `false` |
| `:include_text` | boolean | `true` |
| `:built_ins` | boolean | `true` |
| `:recognizers` | recognizer modules/definitions | `[]` |
| `:deny_lists` | deny-list definitions | `[]` |
| `:allow_list` | allow-list definitions | `nil` |
| `:context` | list of strings | `[]` |
| `:context_window` | non-negative integer | `30` |
| `:context_prefix_count` / `:context_suffix_count` | non-negative integer | `5` |
| `:context_boost` | number from 0 through 1 | `0.15` |
| `:context_min_score` | number from 0 through 1 | `0.4` |
| `:context_match` | `:whole_word` or `:substring` | `:whole_word` |
| `:detect_language` | boolean | `false` |
| `:language_detector` | detector module or `nil` | `nil` |
| `:batch_size` | positive integer | `8` |
| `:recognizer_timeout` | timeout | `5_000` |
| `:parallel_recognizers` | boolean | `false` |
| `:phone_parser` / `:phone_validator` / `:phone_regions` | optional phone policy | disabled / `[]` |
| `:telemetry` | boolean | `true` |

Low-level `:ner`, serving, NLP-engine, and model-routing options are
experimental. Stable prepared profiles are the supported application path.

Analyzer keyword lists currently ignore unknown keys. Unknown keys are outside
the supported schema and callers must not rely on that tolerance; a future
minor release may return a structured configuration error after deprecation.

### Anonymize And Redact

`anonymize/3` accepts `:operators` (default built-ins), `:conflict_strategy`
(default `:aggressive`), `:merge_whitespace` (default `false`), `:vault`, token
formatting options, and `:telemetry`. `redact/2` combines analyzer and
anonymizer options. Operator collections and operator-specific options are
strict; unknown keys are errors.

### Structured Data

Structured redaction accepts `:field_policies` (`%{}`), `:traverse_structs`
(`false`), `:preserve_structs` (`true`), `:max_depth` (`20`), and `:dry_run`
(`false`) plus analyzer/anonymizer options for string leaves. Unknown
structured keys are currently ignored and are not a supported extension
mechanism.

### Vault And Tokens

Vault token options are `:token_prefix` (`"<<"`), `:token_suffix` (`">>"`),
`:token_separator` (`"_"`), `:token_width` (`3`), `:token_case` (`:upper`),
and `:token_strategy` (`:sequential`). These options are strictly validated
when used by pseudonymization.

LLM redaction adds `:vault`, `:create_vault` (`false`), and `:roles`
(`[:user]`) and forwards supported redaction options.

Streaming rehydration requires `:vault` and supports `:token_prefix`,
`:token_suffix`, `:max_token_length` (`128`), `:unknown` (`:keep`), and
`:telemetry` (`true`).

The Plug supports `:fields` (`[:params]`), `:mode` (`:assign_redacted`,
`:replace`, or `:disabled`), `:assign` (`:obscura_redacted`), and supported
redaction options. Other values are outside the stable schema.

## Optional Dependencies And Assets

The package's required runtime dependencies are Jason, Telemetry, and Plug.
The `:fast` profile needs no model dependency or asset.

- parser-backed phone validation uses optional `ex_phone_number`;
- broad NER uses optional Nx, Bumblebee, an explicit backend, tokenizers, and
  model assets;
- native Privacy Filter uses optional Nx, Safetensors, an explicit backend,
  and a local checkpoint;
- GLiNER/Ortex uses optional Ortex and Tokenizers and remains experimental;
- Emily and EXLA are development/runtime choices and are never selected as
  proof of GPU execution without backend metadata.

No model weights ship in the Hex package. Ordinary analysis and redaction never
download assets. Explicit profile preparation defaults to cache-only, online
preparation requires deployer authorization, and scheduled model CI uses
pre-provisioned caches.

## Versioning Policy Below 1.0

Obscura follows SemVer while making a stronger promise than SemVer requires for
the stable `0.1.x` surface:

- patch releases fix bugs and do not intentionally break stable contracts;
- minor releases may add stable APIs and fields;
- stable breaking changes require deprecation and migration guidance, even
  before `1.0`;
- experimental and internal APIs may change in any release;
- a critical security or correctness issue may require an immediate breaking
  fix, documented prominently in release notes.

A breaking change includes removing or renaming a stable function, changing an
arity, narrowing accepted documented inputs, changing outer return tuples,
removing/renaming stable struct fields, removing/repurposing stable codes,
changing operator defaults or schemas, changing stable profile identity, or
adding a required behaviour callback.

## Deprecation And Migration

Normal stable deprecations remain available for at least one subsequent minor
release and at least 90 days from the release that announces them. They include
a compiler/runtime warning where practical, release-note migration steps, and
replacement contract tests.

The only exception is an urgent security or data-corruption issue. In that
case, Obscura may remove unsafe behavior immediately, with a security notice
and explicit migration instructions.

Before a future breaking release:

1. add the replacement API;
2. mark the old API deprecated in code and this inventory;
3. retain tests for both during the transition;
4. publish migration examples;
5. update the machine-readable baseline only in the breaking release.

## Contract Evidence

`test/obscura/public_api_contract_test.exs` verifies the machine-readable API
baseline. `test/obscura/documented_examples_test.exs` exercises the
dependency-light examples and verifies the documented-example evidence
registry. Optional model examples point to tagged integration tests and never
download assets during the base suite.
