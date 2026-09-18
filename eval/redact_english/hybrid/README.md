# Follow-up: efficient plus Redact address enrichment

See [REPORT.md](REPORT.md) for the fresh test and measured combined CPU cost.
This is an evaluation adapter, not a public Obscura profile. The previous
standalone evaluation is preserved unchanged in the parent directory.

The rule in [POLICY.md](POLICY.md), twelve development inputs and 48 new test
inputs were frozen before predictions. `manifest.json` hashes those inputs;
each result records execution sources. Do not modify frozen files in place.
`build_data.py` refuses to overwrite the frozen corpus. No model training occurs.

Use the parent evaluation's pinned Node packages, native assets and isolated
Elixir consumer. From the repository root:

```sh
REDACT_MODEL_DIR="$PWD/.cache/redact-evaluation/model" \
  python3 eval/redact_english/hybrid/run.py \
  --output .cache/redact-evaluation/repeat-hybrid --seconds 60
```

The runner refuses to overwrite reports. `--phase accuracy` or `--phase workload`
can run phases separately; the full run includes both. The workload has one and
four logical workers; each hybrid worker uses two underlying pipeline processes.

For the existing physical Linux host (after copying this directory under the
mirrored evaluator):

```sh
ssh linux 'bash /home/humberto/obscura-redact-evaluation-20260913/linux_run.sh \
 /home/humberto/obscura-redact-evaluation-20260913 \
 python3 ../hybrid/run.py --output ../hybrid/results/repeat-linux --seconds 60'
```

To audit the delivered reports without inference:

```sh
python3 -m unittest discover -s eval/redact_english/hybrid -p test_adapter.py
python3 eval/redact_english/hybrid/analyze.py
```

The analysis requires all 16 accuracy reports and 12 operational reports,
recomputes scores, verifies execution/data hashes, validates actual live hybrid
outputs against independently recorded component predictions, and checks equal
workload mixtures, errors and recovery. Results contain offsets and measurements,
not input text or detected values. Raw worker logs are ignored. Synthetic input
text is intentionally included in development.json and test.json.

The parent evaluator's final-validation.json inventories the evidence bundle;
this follow-up also has its own results/analysis.json and source hashes.

The parent evaluator's `source-formatting.json` documents a later formatting-only
change to the shared worker. Its measured snapshot and original report hashes
are preserved. The auditor checks formatter equivalence with Elixir before
accepting the archived hash; new inference runs record the current source hash.

After each host finishes, `python3 hybrid/check_host.py` (from the parent
evaluator) checks the 36 worker logs for known fatal signatures and remaining
workers. On Linux it also verifies CPU/XNNPACK startup evidence for all 18 Redact
processes, including accuracy and recovery calls. Both hosts' saved checks passed.
Individual graceful shutdown exit codes were not retained by the shared driver.
