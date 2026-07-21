# CI and Model Validation

Obscura separates dependency-light correctness from optional model and
accelerator validation.

## Tier 1: Pull Requests

Every push and pull request runs without EXLA, Emily, Ortex, model downloads,
or external services. It checks formatting, warnings, unit/fixture behavior,
authoritative manifest integrity, static analysis, and documentation.
The lockfile hygiene subprocess fetches and evaluates the union of conditional
optional dependency declarations so Mix can inspect their transitive graphs,
but it does not compile or execute those adapters.

Local equivalent:

```sh
mix ci.base
```

## Tier 2: Optional Compatibility

Scheduled/manual compatibility checks exercise optional parser and adapter
setup paths without large model downloads.

```sh
mix ci.optional
```

## Tier 3: Real Models and Accelerators

Real model jobs are manual or scheduled on controlled runners with
pre-provisioned assets. Apple GPU claims require a self-hosted Apple Silicon
runner and `OBSCURA_EMILY_FALLBACK=raise`.

Controlled jobs prepare with `offline: true` and `allow_download: false`.
Provisioning model caches is a separate operator-approved action; ordinary CI,
tests, analysis, and benchmark request loops never download assets. Preparation
unit tests use fake builders and temporary caches only.

```sh
mix ci.real_model_smoke
```

The alias launches stable `:balanced` and `:accurate` plus experimental
`:openmed_pii` evaluation in three isolated Mix processes. The public experimental
`:hybrid_gliner_urchade` CPU profile runs in the separately gated
`gliner-ortex` job because it needs a different dependency graph and locally
exported ONNX assets. Experimental paths
remain in controlled model CI so evidence does not silently decay. This is
required because a Mix task normally runs only once per VM. A successful job
therefore proves that all three accelerator smoke reports were generated rather
than silently reusing the first task invocation. A passing GLiNER job separately
proves Urchade tokenizer/tensor/span parity and real Ortex inference.
Authoritative matrix refresh is an intentional separate operation; it is not
performed on every pull request.

When `OBSCURA_ENABLE_OPERATIONAL_BENCHMARK_CI` is `true`, the controlled Apple
or Linux job also runs the full operational matrix with pre-provisioned
datasets and assets. It generates evidence but does not auto-promote it.
Promotion remains a reviewed clean-source action.

Long-duration soak execution is independently gated. Apple/Emily uses
`OBSCURA_ENABLE_APPLE_SOAK_CI=true`; Linux/EXLA uses
`OBSCURA_ENABLE_EXLA_SOAK_CI=true`. Each controlled job runs the canonical
60-minute matrix and uploads only privacy-safe working reports for review.
Committed authoritative soak hashes are verified by dependency-light CI.
The separate sustained-latency diagnostic manifest is also verified by
dependency-light CI. Diagnostic execution remains a controlled/manual
Apple/Emily operation because canonical confirmation requires paired controls,
ten- and thirty-minute model runs, and reviewed causal interpretation.

## Security

- Workflows use minimum token permissions.
- Model data and credentials are not uploaded as artifacts.
- Raw benchmark datasets are not uploaded.
- Model jobs use concurrency controls and timeouts.
- Hosted runners do not claim Metal GPU validation.

`mix ci.base` also runs
`mix obscura.docs.verify`, which rejects broken or
machine-specific local Markdown links while ignoring fenced examples and
external URLs.

The workflows under `.github/workflows/` are the executable source of truth;
this document describes their intended boundaries and local reproduction.

## Workflow Map

| Workflow | Trigger | Runner | Local command |
| --- | --- | --- | --- |
| `ci.yml` | every push and pull request | GitHub-hosted Ubuntu | `mix ci.base` |
| `optional-compatibility.yml` | weekly and manual | GitHub-hosted Ubuntu | `mix ci.optional` |
| `model-validation.yml` Apple | weekly/manual when enabled | `[self-hosted, macOS, ARM64, obscura-metal]` | `mix ci.real_model_smoke` with Emily environment |
| `model-validation.yml` EXLA | weekly/manual when enabled | `[self-hosted, Linux, X64, obscura-exla]` | `mix ci.real_model_smoke` with EXLA environment |
| `model-validation.yml` GLiNER | weekly/manual when enabled | `[self-hosted, macOS, ARM64, obscura-ortex]` | tagged GLiNER Ortex test |
| `model-validation.yml` operational | weekly/manual when enabled | controlled Apple/Emily or Linux/EXLA runner | `mix obscura.operational.benchmark` |
| `model-validation.yml` soak | weekly/manual when enabled | controlled Apple/Emily or Linux/EXLA runner | four canonical `mix obscura.operational.soak` runs |

Controlled jobs are disabled unless their repository variables are exactly
`true`: `OBSCURA_ENABLE_APPLE_MODEL_CI`, `OBSCURA_ENABLE_EXLA_MODEL_CI`,
and `OBSCURA_ENABLE_ORTEX_MODEL_CI`. A skipped job
means infrastructure was not enabled; it is not passing model evidence.
Full operational execution additionally requires
`OBSCURA_ENABLE_OPERATIONAL_BENCHMARK_CI=true`.
Soak execution instead requires `OBSCURA_ENABLE_APPLE_SOAK_CI=true` or
`OBSCURA_ENABLE_EXLA_SOAK_CI=true`.

The Apple and Linux jobs require `OBSCURA_PRIVACY_FILTER_CHECKPOINT` as a
runner-local repository variable. Model repository authentication, when
required, uses the protected `HF_TOKEN` secret.

No workflow uploads model caches, raw datasets, reports containing source text,
or credentials. Consequently there is no model artifact retention window to
manage; GitHub's dependency cache contains only build/dependency material on
the dependency-light jobs.
