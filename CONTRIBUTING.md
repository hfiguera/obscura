# Contributing to Obscura

Thank you for contributing to Obscura. The project accepts focused bug fixes,
tests, documentation improvements, recognizers, performance work, and carefully
validated model integrations.

Obscura processes sensitive data. Correct offsets, value-safe diagnostics, and
reproducible evidence are part of correctness, not optional polish.

## Before You Start

- Use synthetic values in issues, tests, logs, screenshots, and reports. Never
  submit production PII, credentials, vault contents, private prompts, or
  proprietary datasets.
- Report suspected vulnerabilities through the private process in
  `SECURITY.md`; do not open a public issue for them.
- Discuss substantial public API changes, new stable profiles, bundled assets,
  or new runtime dependencies before implementing them.
- Review `docs/public-api-stability.md` when changing stable modules, structs,
  callbacks, profile behavior, option schemas, diagnostics, or Mix tasks.
- Review `docs/model-asset-licensing.md` before adding a model, tokenizer,
  dataset, checkpoint, conversion, or generated model asset.

## Development Setup

The pinned development toolchain is recorded in `.tool-versions`:

- Elixir 1.20 on OTP 29
- Erlang/OTP 29

With the toolchain installed:

```sh
mix local.hex --force
mix local.rebar --force
mix deps.get
mix test
```

The dependency-light test path does not require model downloads, EXLA, Emily,
Ortex, a GPU, external services, or private datasets.

## Making A Change

1. Create a focused branch from the latest `main`.
2. Add or update tests with the implementation.
3. Keep changes within the relevant ownership boundary; avoid unrelated
   refactors and generated-file churn.
4. Format and run the narrowest relevant tests while iterating.
5. Run the required validation below before opening a pull request.
6. Update user documentation and contract tests when behavior visible to
   callers changes.

Use `mix format` for Elixir formatting. Prefer existing modules, result types,
diagnostics, and configuration patterns over parallel abstractions. Comments
should explain non-obvious constraints rather than narrate the code.

### Detection And Anonymization Changes

Detection changes must preserve exclusive byte offsets and should include
tests for Unicode, adjacent entities, overlaps, malformed input, false
positives, and false negatives as applicable. Operator and callback changes
must return structured, value-safe errors and must not leak source or
replacement values through exceptions, inspection, logs, or telemetry.

Do not improve benchmark recall by adding broad person, location, or
organization regexes without evidence. Obscura intentionally uses
deterministic recognizers for structured PII and model-backed recognizers for
open-class entities.

### Public API Changes

The stable `0.1.x` surface is defined by
`priv/obscura/public_api.exs` and documented in
`docs/public-api-stability.md`. A change to stable return shapes, error codes,
defaults, callbacks, profile semantics, or accepted options requires contract
tests and compatibility analysis. Do not update the machine-readable baseline
merely to make a breaking test pass.

Experimental APIs may change, but their stability status and limitations must
remain explicit.

## Validation

Run the full dependency-light gate for ordinary pull requests:

```sh
mix ci.base
```

This includes formatting, compilation with warnings as errors, tests, fixture
validation, static analysis, authoritative-report integrity, documentation
verification, and ExDoc generation.

For faster iteration, run focused commands first:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test path/to/relevant_test.exs
mix credo --strict --all
```

Do not treat a skipped optional or real-model test as passing evidence.

### Optional Dependencies

Changes involving optional parsers, Nx contracts, GLiNER, or checkpoint
loading must also pass:

```sh
mix ci.optional
```

Conditional dependency graphs are selected by environment variables. Follow
`docs/optional-dependencies-and-assets.md` and
`docs/ci-and-model-validation.md`; do not add an optional dependency to the
base runtime merely to simplify local testing.

### Real Models And Accelerators

Real-model validation requires controlled, pre-provisioned assets. Model
downloads must be explicit and must never occur in normal tests or request
handling. Apple GPU claims require Emily with GPU selection and fallback set to
`raise`; a successful CPU fallback is not GPU evidence.

Use the documented controlled command and environment for the affected path:

```sh
mix ci.real_model_smoke
```

Include model revision, tokenizer revision, asset hashes, backend, device,
fallback policy, compile shape, hardware, source commit, and clean-worktree
state in evidence. Do not commit model weights or caches.

## Fixtures, Datasets, And Evaluation

Deterministic fixtures under `fixtures/` are repository contracts. Benchmark
snapshots under `eval/datasets/` are intentionally excluded from the Hex
package. Never replace pinned data silently or commit external data without
documented provenance and licensing.

Working reports belong under ignored `eval/reports/`. A report may be promoted
to `eval/authoritative/` only when it:

- was produced from a clean source revision;
- uses the documented dataset fingerprint and sample IDs;
- records the exact profile, model revisions, mappings, thresholds, backend,
  hardware, and command;
- contains the required reproducible repetitions;
- passes the authoritative manifest verifier;
- contains no unsafe raw values; and
- is reviewed together with the code and documentation claims it supports.

Tune policies only on designated training splits. Report final quality only on
held-out data. Accuracy claims must distinguish deterministic, fake-serving,
Python-reference, and real native-model results. Fake or gold-derived outputs
prove integration contracts, not model accuracy.

See `docs/benchmark-status.md` and `docs/operational-benchmarking.md` for the
current accuracy and performance protocols.

## Documentation

Document stable user behavior in module docs and the relevant guide. Keep the
README focused on supported product behavior; preserve historical experiments
in their dedicated reports rather than presenting them as current guidance.

Validate documentation with:

```sh
mix obscura.docs.verify
mix docs
```

Documentation must not contain machine-specific absolute paths, stale local
repository references, or claims unsupported by promoted evidence.

## Pull Requests

A pull request should state:

- the problem and behavioral change;
- affected stable or experimental APIs;
- tests and commands run;
- accuracy and latency impact when detection or model behavior changes;
- dependency, asset, licensing, privacy, and security impact; and
- remaining limitations or follow-up work.

Keep commits focused and use clear imperative commit messages. Do not include
unrelated formatting, downloaded models, caches, virtual environments, raw
datasets, or temporary reports.

Before requesting review, confirm:

- `mix ci.base` passes;
- required optional or real-model checks pass, or their absence is explicitly
  documented;
- public examples and documentation match the implementation;
- new diagnostics and errors are structured and value-safe;
- no raw or proprietary sensitive data is present; and
- the worktree contains only intentional files.

By contributing, you agree that your contribution is licensed under the
project's MIT License.
