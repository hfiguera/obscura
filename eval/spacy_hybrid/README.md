# Obscura deterministic recognizers + spaCy NER experiment

This evaluation asks whether the existing `en_core_web_lg` weights justify a
future native runtime. It adds no production profile or Python runtime dependency
to Obscura.

The completed experiment is in [results/RESULTS.md](results/RESULTS.md), with
interpretation in [DECISION.md](DECISION.md).

The subsequent Python-free CPU prototype and live benchmark are now in
[../spacy_native/README.md](../spacy_native/README.md), with
[native results](../spacy_native/results/RESULTS.md).

Run from the repository root using the existing pinned environment:

```sh
.presidio-authoritative-venv/bin/python eval/spacy_hybrid/benchmark.py
.presidio-authoritative-venv/bin/python eval/spacy_hybrid/report.py --results PATH_TO_RESULTS_JSON
```

The command runs all three authoritative selections, five warmup samples per
mode, and two measured repetitions. Each repetition runs one input at a time on
CPU; the second reverses Python mode order. Results and privacy-safe prediction
artifacts are saved beneath `eval/reports/spacy_hybrid/<timestamp>/`.

Use `--datasets generated_large` for a smaller full-selection check or
`--out-dir PATH` to choose a new output directory. There is no heldout tuning,
threshold sweep, model training, or gold-derived prediction path.

## Fixed candidate and controls

- Primary: `hybrid_spacy_full`. The pinned Presidio spaCy pipeline generates
  `PERSON`, `GPE`, `LOC`, and `FAC` spans. These are imported into a real custom
  Obscura recognizer alongside `:deterministic_plus` (the implementation used by
  the authoritative `:fast` baseline). All normal analyzer filtering, context,
  duplicate handling, and structured-entity precedence run in Elixir.
- Diagnostic: `hybrid_spacy_ner_only`. Same weights and policy with only the NER
  component enabled. This may change predictions and is never silently treated
  as equivalent to the full pipeline.
- Controls: fresh `:fast` and full Presidio Analyzer, repeated on the same data.
  A separate `fast_reference` disables conflict resolution to reproduce the
  historical fixture adapter. The regular `fast` row uses production defaults.
- Mapping: PERSON to person; GPE/LOC/FAC to location, following pinned Presidio.
  The common eight-entity protocol excludes organizations and dates.
- Score: Presidio's assigned 0.85, not a calibrated confidence probability.
  No new score threshold or conflict policy is introduced.

## Integrity and measurement

The Python process verifies the existing pinned Python/package versions and
records model asset hashes. Both languages validate dataset selections. Elixir
rebuilds the protocol selection, checks dataset bytes and ordered IDs, validates
character-to-byte offsets, and rejects mismatched prediction artifact hashes.
Only `Obscura.Eval.Metrics` produces the reported accuracy. Every profile must
produce identical accuracy and output fingerprints across repetitions.

Reports include the shared evaluator's historical metrics and separate
`strict_exact` metrics. The historical evaluator reports offset mismatches and
wrong types separately, excluding them from its F1 denominators. Conventional
strict metrics count those errors as both a false positive and a false negative.
Both views are retained so comparisons with published rows remain reproducible
without hiding boundary errors.

Hybrid latency is the per-document sum of Python model processing and measured
Obscura analyzer execution. It excludes IPC, file reads, serialization, model
loading, and process startup. It is an estimate of serial component cost, not
measured native or production end-to-end latency. Presidio timing covers the
Analyzer call, matching the existing reference. Python peak RSS includes the
full pipeline, reference analyzer, and sequential evaluation work; it does not
estimate native NER memory. Historical GPU timings are not CPU comparisons.

These are exploratory, unpromoted results. No authoritative manifest is changed.

## Verification

```sh
.presidio-authoritative-venv/bin/python -m unittest discover -s eval/spacy_hybrid -p 'test_*.py'
mix run --no-start -r eval/spacy_hybrid/score.exs -r eval/spacy_hybrid/test_score.exs -e ':ok'
```
