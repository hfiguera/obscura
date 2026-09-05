# Native spaCy feasibility decision

The experiment supports a bounded native feasibility prototype for a CPU-focused
profile. It does not support replacing `:balanced` or `:accurate`.

The full hybrid improves shared-protocol F1 over Presidio by 0.1029, 0.0699, and
0.0687 on generated heldout, Synth v2, and Nemotron respectively. Compared with
the production-default deterministic analyzer, it recovers 262, 481, and 424
additional exact matches. All six structured entity categories retain identical
predictions. The benefit comes from adding person/location recognition while
keeping Obscura's structured recognizers and conflict rules.

The hybrid trails `:balanced` by 0.0040, 0.0478, and 0.0014 on the historical
metric. Conventional strict-span F1 shows a larger gap: 0.0198, 0.0676, and
0.0255. Name detection is weaker than TNER, while the shared per-entity location
score is higher on all three datasets. Nemotron still has 323 boundary errors
and 30 wrong-type errors, so the nearly equal historical overall F1 should not
be interpreted as equivalent protection.

NER-only inference is an attractive scope for a prototype. Its hybrid component
cost is approximately 1.66 ms, 1.76 ms, and 11.64 ms per document, versus 3.53 ms,
3.82 ms, and 25.31 ms for the full pipeline. These are summed Python and Elixir
CPU costs without IPC or serialization. Native speed and production throughput
have not been measured. NER-only changes seven Synth documents and one Nemotron
document; shared F1 moves by less than 0.0003 on each dataset. It is a separately
identified candidate, not an exact substitute for the full pipeline.

The installed NER network has 1,593,322 trainable parameters, but its static
vectors occupy 411,501,600 bytes. A CPU-oriented port could avoid a Python runtime
and unrelated pipeline components, but still requires compatible tokenization,
feature hashing, numerical operations, and transition decoding. The vector
footprint remains material unless a separately evaluated compression changes it.

If proceeding, the next milestone should reproduce the pinned NER-only outputs
in a Python-free runtime, including UTF-8 offsets and structured-span precedence.
Measure single-request latency, startup, RSS, and bounded concurrency on the same
CPU against the Python reference and the existing CPU alternatives. Validate
accuracy on untouched, deployment-representative documents before promotion.
Changing thresholds, fine-tuning, or pruning vectors would be separate experiments.

This document records the initial Python-reference decision. The subsequently
requested native CPU prototype is now implemented and measured on this branch;
see [native results](../spacy_native/results/RESULTS.md) and the
[prototype README](../spacy_native/README.md). No production profile is promoted.
The original Python metrics and reproduction commands remain in
[results/RESULTS.md](results/RESULTS.md) and [README.md](README.md).
