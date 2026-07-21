# Obscura Presidio Adapter

This optional adapter supports two Presidio-related workflows:

- Reading Obscura prediction JSONL exports for external evaluator experiments.
- Running a real local Presidio Analyzer baseline and comparing it with Obscura on the same Presidio-Research samples.

The adapter does not vendor Presidio, Presidio-Research, spaCy models, or Python virtualenvs. Install Python dependencies only when running external evaluator comparisons.

## Authoritative Python Environment

The authoritative adapter uses CPython 3.11.15 and a complete hash-locked
dependency graph. Create the ignored environment with:

```sh
PYTHON=/opt/homebrew/bin/python3.11 \
bash eval/presidio_adapter/setup_authoritative_env.sh
```

The tracked inputs are:

- `authoritative-environment.json`: Python, package, source revision, and model
  metadata;
- `requirements-authoritative.in`: direct requirements;
- `requirements-authoritative.lock`: complete transitive lock with hashes;
- `authoritative_protocol.json`: shared taxonomy, mapping, selection, byte
  offset, and scoring policy.

The `.presidio-authoritative-venv/` directory, model cache, and prediction
exports remain ignored. The older `.presidio-venv/` is for historical model
experiments and is not authoritative.

## Authoritative Comparison

Prepare a privacy-safe selection. It contains ordered sample IDs and
fingerprints, never source text:

```sh
mix obscura.presidio.prepare \
  --dataset generated_large \
  --out eval/comparison/generated_large_template_heldout.json
```

Run Presidio after one warmup:

```sh
.presidio-authoritative-venv/bin/python \
  eval/presidio_adapter/real_presidio_benchmark.py \
  --dataset generated_large \
  --selection eval/comparison/generated_large_template_heldout.json \
  --full \
  --warmup 1 \
  --run-suffix authoritative_r1
```

The Python metric block is diagnostic. Generate the candidate authoritative
report with the single Elixir evaluator:

```sh
mix obscura.presidio.score \
  --selection eval/comparison/generated_large_template_heldout.json \
  --predictions eval/predictions/PYTHON_RUN.jsonl \
  --reference-report eval/reports/PYTHON_RUN.json \
  --run-id presidio_authoritative_generated_large_r1
```

Repeat the Python and scoring commands with `authoritative_r2`. Promotion
requires at least two reports with identical protocol fingerprints and accuracy
counts:

```sh
mix obscura.benchmarks.promote \
  --report eval/reports/presidio_authoritative_generated_large_r1.json \
  --external-baseline presidio_spacy_en_core_web_lg \
  --repetition-reports eval/reports/presidio_authoritative_generated_large_r2.json \
  --command ".presidio-authoritative-venv/bin/python ..." \
  --warmup 1
```

For Obscura runs, pass the exact entity list from the protocol, then use
`mix obscura.presidio.annotate` before normal stable-profile promotion. The
annotation command rejects a different dataset, sample order, count, or entity
policy.

Latency is comparable only when hardware and actual device/backend are
equivalent. Presidio spaCy CPU and Obscura Emily GPU accuracy may be compared;
their latency values must remain explicitly non-comparable.
