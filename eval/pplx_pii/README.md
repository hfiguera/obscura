# Perplexity PII Candidate Evaluation

This adapter evaluates `perplexity-ai/pplx-pii-masking` as an Obscura model
candidate. It pins the masking model and its public backbone by revision and
verifies every executable, tokenizer, configuration, and weight file before
loading them.

It reports two different questions:

- **Typed exact spans:** Can the model satisfy Obscura's current entity and
  exact byte span contract?
- **Label agnostic exact spans:** Are the boundaries correct when taxonomy is
  ignored?
- **Label agnostic characters:** How much of all annotated PII text does the
  model cover when its broader privacy taxonomy is accepted?

The second metric is diagnostic. It cannot establish a new Obscura champion
because `account_number`, for example, does not distinguish credit cards from
US Social Security numbers.

## Setup

```console
python3.11 -m venv .pplx-pii-venv
.pplx-pii-venv/bin/pip install -r eval/pplx_pii/requirements.lock
```

## Smoke Run

```console
.pplx-pii-venv/bin/python eval/pplx_pii/reference_benchmark.py \
  --dataset generated_large \
  --device mps \
  --limit 20
```

Use `--full` for the complete authoritative selection. Reports are written to
the ignored `eval/reports/` directory and contain no raw sample text or values.

Prepare the ignored, pinned Nemotron selection before evaluating it:

```console
.pplx-pii-venv/bin/python eval/pplx_pii/prepare_nemotron.py
```

The default preserves the tokenizer behavior in Perplexity's published
`example_usage.py`. Transformers 5.11 warns about that tokenizer's regex.
`--fix-tokenizer-regex` allows an explicit comparison, but results from that
mode must be reported separately from published reference behavior.

## Hybrid Experiment

The hybrid scorer consumes raw-text-free prediction artifacts. Obscura remains
authoritative for every overlapping span. The Perplexity model may only add a
nonoverlapping span whose entity is allowed by the selected policy.

Export model predictions while running the reference benchmark:

```console
.pplx-pii-venv/bin/python eval/pplx_pii/reference_benchmark.py \
  --dataset generated_large \
  --device mps \
  --full \
  --model-dir .cache/pplx-pii/materialized-model \
  --backbone-dir .cache/pplx-pii/materialized-backbone \
  --predictions-out eval/predictions/hybrid/pplx-generated_large.json
```

Export predictions from a prepared Obscura profile:

```console
OBSCURA_REAL_MODEL_BACKEND=emily \
OBSCURA_EMILY_DEVICE=gpu \
OBSCURA_EMILY_FALLBACK=raise \
mix run eval/pplx_pii/export_obscura_predictions.exs \
  --profile accurate \
  --dataset generated_large \
  --selection eval/authoritative/selections/generated_large_template_heldout.json \
  --out eval/predictions/hybrid/accurate-generated_large.json
```

Then score all fixed merge policies:

```console
.pplx-pii-venv/bin/python eval/pplx_pii/hybrid_benchmark.py \
  --dataset generated_large \
  --base-profile accurate \
  --obscura-predictions eval/predictions/hybrid/accurate-generated_large.json \
  --pplx-predictions eval/predictions/hybrid/pplx-generated_large.json
```

Repeat with the matching authoritative selection for `synth_dataset_v2` and
`nemotron_pii_test_subset`. Prediction artifacts and reports are ignored by
Git and contain no source text or detected values.
