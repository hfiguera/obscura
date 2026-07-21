# Product Profiles

Obscura exposes three stable user-facing profiles. Two measured profiles remain
experimental and available for controlled evaluation.

| Profile | Stability | Resolved implementation | Intended use | Runtime cost |
| --- | --- | --- | --- | --- |
| `:fast` | stable | `:deterministic_plus` | Structured and context-labeled PII with high precision | Dependency-light BEAM execution |
| `:balanced` | stable | `:hybrid_ner_tner_conservative` | General text needing person, location, and organization NER | One TNER model |
| `:accurate` | stable | `:hybrid_ner_tner_jean_location_cascade` | Highest measured general accuracy with conditional location recovery | Two GPU-oriented NER models |
| `:hybrid_gliner_urchade` | experimental | `:hybrid_gliner_urchade` | CPU-only general PII/NER where GPU use or TNER licensing is unsuitable | One Ortex CPU model plus deterministic recognizers |
| `:openmed_pii` | experimental | `:privacy_filter_native` | OpenMed/Nemotron-style PII evaluation | One high-cost native model |

`:accurate` currently has the best exact-span F1 on all three shared
eight-entity datasets. `:balanced` remains the practical model-backed
recommendation because it uses one model and has lower latency. Their Obscura
contracts are stable, but the optional TNER checkpoint is neither bundled nor
licensed by Obscura. Deployers must review and accept the applicable asset
terms. See `model-asset-licensing.md`.
Measured accuracy does not establish universal accuracy, regulatory
compliance, or suitability for every deployment.

## Fast

Use `:fast` for email, phone, card, SSN, IBAN, IP, URL/domain, and conservative
context-backed entities.

```elixir
{:ok, detections} =
  Obscura.analyze("Contact jane@example.com", profile: :fast)
```

It requires no model weights, accelerator, network, or runtime preparation.
Its main weakness is recall for arbitrary prose names, locations,
organizations, and free-form addresses.

## Balanced

`:balanced` combines deterministic recognizers with
`tner/roberta-large-ontonotes5`. Prepare the reusable serving explicitly during
controlled application startup:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:balanced,
    allow_download: true,
    real_model_backend: :emily,
    emily_fallback: :raise,
    compile: [batch_size: 1, sequence_length: 128]
  )

{:ok, detections} =
  Obscura.analyze("Rachel works at Google in Paris.", profile: runtime)
```

Obscura does not prepare or download this model from an analyzer call. The
host application must include Nx, Bumblebee, and its chosen backend.

## Accurate

`:accurate` runs TNER first for person, organization, and location. It invokes
`Jean-Baptiste/roberta-large-ner-english` with the
`FacebookAI/roberta-large` tokenizer fallback only when TNER returns no
accepted location.

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:accurate,
    allow_download: true,
    real_model_backend: :emily,
    emily_fallback: :raise,
    compile: [batch_size: 1, sequence_length: 128]
  )
```

The product policy is locked to `cascade_trigger: :missing`, Jean
`LOC=0.999`, and `cascade_context_policy: :none`. Advanced callers can still
select the explicit implementation profile for experiments, but options do not
silently change the `:accurate` alias contract.

Two clean Emily GPU repetitions show exact F1 of `0.8024`, `0.8423`, and
`0.6973` on generated heldout, Synth v2, and Nemotron respectively. Those
results beat `:balanced` by `0.0145`, `0.0035`, and `0.0019`. The full
operational matrix passes, but the second model increases memory and latency.
Use concurrency `1` for interactive work;
evaluate `2` or `4` only against a bounded deployment SLO.

## Experimental Profiles

`Obscura.Profile.experimental_names/0` returns
`[:hybrid_gliner_urchade, :openmed_pii]`.
These profiles are callable so their measured implementations can be evaluated
without rebuilding configuration manually. They are not included in
`Obscura.Profile.names/0` and may change or be removed before release. The
recommendation for an experimental profile is use-case-specific and does not
grant a compatibility or production-readiness promise.

### Urchade GLiNER CPU (Experimental)

`:hybrid_gliner_urchade` combines deterministic structured PII recognition
with `urchade/gliner_multi_pii-v1` for person, location, and organization. It
uses Ortex CPU by default and does not require a GPU or Nx accelerator backend.
Prepare its pinned, locally exported ONNX/tokenizer/config bundle explicitly:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:hybrid_gliner_urchade,
    model_dir: ".cache/gliner/urchade-gliner-multi-pii-v1"
  )

{:ok, detections} =
  Obscura.analyze("Rachel works at Google in Paris.", profile: runtime)
```

This is the publicly recommended experimental CPU-only general NER option when
an accelerator is unavailable or the unresolved TNER checkpoint license blocks
`:balanced`. It is not the accuracy leader. Its exact F1 was `0.7209`,
`0.6843`, and `0.4855` on the three shared datasets, compared with `0.7878`,
`0.8388`, and `0.6954` for `:balanced`. Adapter parity passed, but the model
produced materially weaker person/location quality and more false positives.

CPU characterization measured roughly `14.39 ms` mean and `25.94 ms` p95 at
concurrency `1` on a 32-sample length-stratified heldout subset. That result is
candidate characterization, not a promoted full operational matrix. CoreML is
not recommended for the current dynamic ONNX graph because most operations
fall back to CPU and measured latency was substantially worse.

### OpenMed PII (Experimental)

`:openmed_pii` is model-only by design. It does not add deterministic built-ins
to Privacy Filter predictions.

```elixir
clinical_text = "Patient Ada Lovelace called 415-555-0199."

{:ok, runtime} =
  Obscura.Profile.prepare(:openmed_pii,
    checkpoint: ".cache/privacy-filter/openmed-nemotron-v2",
    backend: :emily,
    emily_fallback: :raise
  )

{:ok, detections} = Obscura.analyze(clinical_text, profile: runtime)
```

Validate a checkpoint before preparation:

```sh
mix obscura.privacy_filter.checkpoint \
  --checkpoint .cache/privacy-filter/openmed-nemotron-v2
```

This alias is experimental and not a general recommendation. The model's
license metadata is not a clear production grant. Review upstream terms before
deployment or redistribution.

On the measured Apple M4 Max, use `:openmed_pii` only behind a bounded queue.
For short broad inputs, concurrency `4` is a reasonable throughput starting
point. For Nemotron-style long inputs, concurrency `2` was the best measured
throughput/latency compromise: `1.38` req/s with p95 about `2.83` seconds.
Concurrency `4` reduced throughput to `1.21` req/s and raised p95 to about
`6.67` seconds. The profile also showed large transient Emily allocator and
process-RSS peaks. Retained-memory growth remains inconclusive.

## Preflight

Preflight never analyzes PII. Local checks are the default:

```sh
mix obscura.profile.check --profile fast
mix obscura.profile.check --profile balanced --backend emily --json
```

Model preparation is explicit and may use the configured cache or network:

```sh
OBSCURA_REAL_MODEL_BACKEND=emily \
OBSCURA_EMILY_FALLBACK=raise \
mix obscura.profile.check \
  --profile balanced \
  --backend emily \
  --compile-batch-size 1 \
  --compile-sequence-length 128 \
  --prepare \
  --allow-download
```

A failed Mix preflight exits non-zero and returns a stable diagnostic code.

## First Preparation And Runtime Ownership

Model download authorization is explicit and defaults to `false`. Selecting a
profile in `analyze/2` or `redact/2` never prepares a runtime. Calling
`prepare/2` without `allow_download: true` is cache-only; a missing cache
returns `:model_download_not_allowed`. `offline: true` always wins over
download authorization and returns `:missing_model_asset` on a cache miss.

Use the dedicated task for an interactive first preparation:

```sh
mix obscura.profile.prepare \
  --profile accurate \
  --backend emily \
  --allow-download \
  --timeout 1800000 \
  --inactivity-timeout 300000
```

The task reports the effective cache directory, each model, cache checks,
download bytes when observable, model/tokenizer loading, serving construction,
backend preparation, elapsed time, and final remediation. `--json` emits one
JSON record per event and disables Bumblebee's terminal progress bar.

Online preparation retries one transient sanitized model or tokenizer asset
failure and reports the retry as a separate stage. Offline preparation never
retries asset access. An authorized retry quarantines unreferenced partial
files before rebuilding the active cache and resets byte progress to the
post-quarantine baseline.

For API preparation, `progress: fn event -> ... end` receives report-safe
maps. The same lifecycle is emitted through telemetry under
`[:obscura, :profile, :preparation, event]`. Callback failures are ignored and
cannot fail preparation. Default limits are 30 minutes overall and five
minutes without stage or cache-byte activity; callers can set `timeout`,
`inactivity_timeout`, or `:infinity` explicitly.

Concurrent preparation calls for the same profile are serialized. Each caller
waits for the lock and receives its own final runtime or diagnostic; complete
cache entries are reused, so the later call does not repeat the download. Use
one supervised `Obscura.Profile.Preparer` when the application needs callers to
share one prepared runtime instead of constructing separate runtimes in
sequence.

Long-running applications should supervise one preparer and retain the
runtime:

```elixir
children = [
  {Obscura.Profile.Preparer,
   name: MyApp.ObscuraRuntime,
   profile: :balanced,
   prepare_options: [
     allow_download: true,
     real_model_backend: :emily,
     emily_fallback: :raise
   ]}
]

case Obscura.Profile.Preparer.await(MyApp.ObscuraRuntime, :timer.minutes(30)) do
  {:ok, runtime} -> Obscura.analyze(text, profile: runtime)
  {:error, diagnostic} -> {:error, diagnostic.code}
end
```

`status/1` remains responsive during preparation, `subscribe/1` delivers
progress and readiness messages, and `runtime/1` returns the retained reusable
runtime after readiness. A failed preparer remains alive so supervision and
health checks can inspect its sanitized diagnostic.

## Configuration Precedence

For product profile runtimes, effective values are chosen in this order:

1. Explicit analyzer or preparation options, except profile policies documented
   as locked contracts such as the `:accurate` cascade policy.
2. Explicit overrides passed with a prepared `%Obscura.Profile.Runtime{}`.
3. Values captured in the prepared runtime.
4. Environment variables consulted during explicit backend/checkpoint setup.
5. Profile defaults.

Obscura does not implicitly prepare profiles from application configuration.
Analyzer calls never download models. This keeps startup and request behavior
observable and avoids hidden network access.

## Stability Classes

`Obscura.Profile.classification/1` distinguishes `:stable`, `:advanced`,
`:experimental`, and `:historical` names. `:fast`, `:balanced`, and `:accurate`
are stable product aliases. Experimental aliases retain benchmark evidence but
no compatibility or production-readiness promise.

See `docs/benchmark-status.md` for current metrics and
operational conclusions, `docs/optional-dependencies-and-assets.md` for setup
details, and `docs/known-limitations.md` for residual deployment risks.

The stable `:fast`, `:balanced`, and `:accurate` aliases are covered by the
`0.1.x` compatibility policy.
Experimental aliases, low-level model adapters, serving structs, tensor
layouts, and model-specific tuning options may change independently. See
`docs/public-api-stability.md`.
