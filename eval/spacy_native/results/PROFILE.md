# Experimental :spacy_cpu profile validation

The packaged native runtime and public profile reproduce every final prediction from the measured native prototype on all 2,648 documents, in two repetitions. This also preserves its verified spaCy NER-only parity. No model or threshold changes were made.

| Dataset | Documents | Strict F1 | Mean latency | p95 latency |
|---|---:|---:|---:|---:|
| generated_large | 648 | 0.7190 | 0.416 ms | 0.698 ms |
| synth_dataset_v2 | 1500 | 0.7315 | 0.419 ms | 0.781 ms |
| nemotron_pii_test_subset | 500 | 0.5403 | 1.747 ms | 3.970 ms |

Latency wraps live Obscura.analyze using the prepared :spacy_cpu runtime: pool reservation, IPC/JSON, native inference, deterministic recognizers, and conflict handling. The table averages two runs; p95 is the mean of run p95s. Five warmup documents precede each run, with one native worker and one in-flight request. This is an Apple M4 Max characterization, not a deployment SLO.

Preparation including verification of every pinned model file: 239.0 ms on a warm filesystem cache. Native worker peak RSS: 174.2 MiB. Worker RSS excludes BEAM memory and grows as mapped vector pages are touched; total assets remain about 408 MiB.

The profile adds explicit ownership, bounded admission without a text queue, per-request deadlines, native response validation, and limited worker recovery. Saturation and failures return errors; analysis never prepares assets or downloads models.

Accuracy remains below balanced, including Nemotron strict F1 0.5403 versus 0.5659. This is an experimental Apple Silicon CPU option; balanced remains the general accuracy recommendation. No authoritative profile is promoted.

Portable protocol tests exercise saturation, caller death, expiry, crashes, malformed responses, cleanup, and sanitized status. Opt-in real-model tests exercise UTF-8 offsets, analyze/redact/analyze_many, concurrency, ownership, worker loss, and corrupt assets. See [setup and lifecycle](../../../docs/spacy-cpu.md).

Run from the repository root after building/exporting: `mix run --no-start eval/spacy_native/profile_benchmark.exs`. [profile.json](profile.json) records source, model, binary and baseline hashes. The original [feasibility results](RESULTS.md) remain available.
