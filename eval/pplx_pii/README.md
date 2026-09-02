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
