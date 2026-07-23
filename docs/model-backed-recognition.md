# Model-Backed Recognition

Obscura supports optional local models for open-class entities such as people,
organizations, and locations. Model-backed recognition does not change the
dependency-light default: `Obscura.analyze/2` never downloads weights, starts a
serving, or contacts a remote service unless the caller explicitly prepares a
model profile.

Applications should use the public profile boundary:

- `:balanced` uses one TNER model and is the practical general recommendation
  for noncommercial evaluation or deployments with the required LDC
  authorization.
- `:accurate` adds conditional location recovery and has the highest measured
  general F1.
- `:hybrid_gliner_urchade` is an experimental CPU-only GLiNER option.
- `:openmed_pii` is an experimental specialist for OpenMed-style PII.

See `profiles.md` for profile contracts, `optional-dependencies-and-assets.md`
for setup, and `benchmark-status.md` for promoted evidence.

## Fake Serving

Tests can provide deterministic model output without downloading a model:

```elixir
serving =
  Obscura.Recognizer.NER.FakeServing.new(%{
    "Alice works at Acme." => [
      %{label: "PER", start: 0, end: 5, offset_unit: :character, score: 0.94},
      %{label: "ORG", start: 15, end: 19, offset_unit: :character, score: 0.91}
    ]
  })

Obscura.analyze("Alice works at Acme.",
  entities: [:person, :organization],
  recognizers: [{Obscura.Recognizer.NER, serving: serving}]
)
```

Fake serving validates configuration, label mapping, offsets, conflicts, and
downstream anonymization. It is not evidence of model accuracy.

## Real Local Serving

Stable model profiles should be prepared once during controlled application
startup and reused for every request:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:balanced,
    allow_download: true,
    real_model_backend: :emily,
    emily_fallback: :raise,
    compile: [batch_size: 1, sequence_length: 128]
  )

Obscura.analyze("Rachel works at Google in Paris.", profile: runtime)
```

Preparation is the only profile path allowed to fetch model assets. A normal
analyzer call supplied with an unprepared model profile returns a structured
diagnostic instead of downloading or constructing a serving.

Low-level callers may build a supported token-classification serving directly:

```elixir
{:ok, serving} =
  Obscura.Recognizer.NER.Serving.build(
    model: :dslim_bert_base_ner,
    compile: [batch_size: 1, sequence_length: 32]
  )

Obscura.analyze("Rachel works at Google in Paris.",
  entities: [:person, :organization, :location],
  recognizers: [
    {Obscura.Recognizer.NER,
     serving: serving,
     label_map: serving.model_spec.label_map}
  ]
)
```

The low-level recognizer, serving, model registry, and model-specific options
are experimental in `0.1.x`. Public profile names and their documented runtime
contracts have the stability described in `public-api-stability.md`.

## Optional Backend Selection

Supported backend selections are `:default`, `:binary`, `:exla`, and `:emily`.
Host applications must add the matching optional dependencies before preparing
a model profile.

On Apple Silicon, Emily is the measured GPU path:

```sh
OBSCURA_REAL_MODEL=1 \
OBSCURA_REAL_MODEL_BACKEND=emily \
OBSCURA_EMILY_FALLBACK=raise \
mix deps.get
```

Use `emily_fallback: :raise` for benchmarks and production validation so an
unsupported operation cannot silently move inference to the CPU. EXLA is the
supported optional path on compatible hosts. `Nx.BinaryBackend` is useful for
correctness checks but is not the recommended BERT-class serving backend.

Before accepting traffic, verify readiness without analyzing PII:

```sh
mix obscura.profile.check --profile balanced --backend emily --json
```

## Hybrid Deterministic Plus Real NER

The stable general profiles combine two recognition strategies:

- deterministic recognizers handle email, phone, card, SSN, IBAN, IP, URL,
  domain, and other structured entities;
- model recognizers handle open-class person, location, and organization
  entities.

This separation avoids broad regular expressions for arbitrary names and
places. Model results still pass through Obscura's label policy, thresholds,
context handling, boundary normalization, and conflict resolution.

`:balanced` uses `tner/roberta-large-ontonotes5`. `:accurate` uses the same
primary model and invokes `Jean-Baptiste/roberta-large-ner-english` only when
the primary model returns no accepted location. The stable cascade policy is:

```elixir
[
  cascade_trigger: :missing,
  cascade_secondary_threshold: 0.999,
  cascade_context_policy: :none
]
```

These third-party checkpoints are not bundled or licensed by Obscura. LDC
directly confirmed on 2026-07-22 that commercial use of the TNER checkpoint
requires an LDC for-profit membership. Obscura does not grant or verify that
authorization. Review `model-asset-licensing.md` before deployment.

## Model Policy

Model normalization supports:

- ignored labels;
- per-entity thresholds;
- low-confidence score multipliers;
- label-specific context gates;
- aggregation and alignment settings;
- conservative boundary normalization;
- chunking for inputs longer than a serving's compiled sequence length.

Unknown labels are ignored. Obscura validates mapped entity names against
known atoms and never creates atoms from model output.

Common mappings include:

| Model label | Obscura entity |
| --- | --- |
| `PER`, `PERSON`, `B-PER`, `I-PER` | `:person` |
| `ORG`, `ORGANIZATION`, `B-ORG`, `I-ORG` | `:organization` |
| `LOC`, `LOCATION`, `GPE`, `B-LOC`, `I-LOC` | `:location` |
| `DATE`, `TIME`, `DATE_TIME` | `:date_time` |
| `NORP`, `NRP`, `NATIONALITY` | `:nationality` |

Organization output is deliberately conservative because broad organization
labels produce false positives in general NER models. Applications needing a
different precision/recall tradeoff should benchmark an explicit
implementation profile rather than changing the stable aliases globally.

## Offsets And Boundaries

All public spans use UTF-8 byte offsets. Model adapters must declare their
source offset unit and normalize it before returning analyzer results.

The original model boundaries are retained in safe metadata when a
postprocessor changes a span. Boundary normalization may trim punctuation or
obvious connector noise, but it must not invent text outside the model span.
Exact and IoU metrics are both reported in authoritative evaluation.

## Batch Analysis

Model-backed recognition supports ordered batches:

```elixir
Obscura.analyze_many(texts, profile: runtime)
Obscura.Analyzer.analyze_many(texts, profile: runtime)
```

The output order matches the input order. Batch-capable recognizers process the
batch together; recognizers without batch support use the compatibility
fallback.

## Artifact-Backed Model Output

Callers can attach model output to `Obscura.NLP.Artifacts` and run recognition
without invoking a serving again:

```elixir
{:ok, artifacts} =
  text
  |> Obscura.NLP.Artifacts.build()
  |> then(fn artifacts ->
    Obscura.NLP.Artifacts.put_model_outputs(artifacts, [
      %{label: "PER", start: 0, end: 6, score: 0.99},
      %{label: "LOC", start: 16, end: 21, score: 0.98}
    ])
  end)

Obscura.analyze(text,
  entities: [:person, :location],
  recognizers: [Obscura.Recognizer.NER],
  nlp_artifacts: artifacts
)
```

Artifacts allow one NLP pass to be shared by multiple recognizers. They do not
change the requirement to validate the originating model and adapter.

## Analyzer-Level NLP Engine

A caller-provided NLP engine can populate artifacts before recognizers run:

```elixir
Obscura.analyze(text,
  entities: [:person, :location],
  recognizers: [Obscura.Recognizer.NER],
  nlp_engine: {Obscura.NLP.Engine.Bumblebee, serving: serving}
)
```

The engine never owns model downloading. The caller must provide a serving or
use an explicitly prepared runtime. Batch analysis shares the engine output
across recognizers.

## Experimental Adapters

Obscura contains experimental adapters for GLiNER through Ortex or native Nx,
generic ONNX token classification, and native Privacy Filter checkpoints.
They are useful for controlled evaluation but are outside the stable `0.1.x`
compatibility promise.

Experimental adapters require explicit local assets and dependencies. They do
not run during the dependency-light test suite, do not download during normal
analysis, and are not included in the Hex package. Their current requirements
are listed in `optional-dependencies-and-assets.md` and machine-readable form
in `priv/obscura/capabilities.json`.

## Evidence Boundary

Successful loading or inference proves adapter compatibility, not accuracy.
Accuracy claims require real model inference against pinned datasets, exact
sample IDs, declared entity mappings, and promoted reports. Current promoted
results are summarized in `benchmark-status.md` and recorded in
`eval/authoritative/manifest.json`.

Latency claims additionally require the same hardware, backend, compile shape,
dataset fingerprint, and concurrency. Current promoted operational conclusions
and their evidence boundary are summarized in `benchmark-status.md`.
