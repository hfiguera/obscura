# Native spaCy CPU prototype results

The native port reproduces pinned spaCy NER-only predictions on all 2,648 selected documents in both repetitions. It is a useful CPU candidate; `:balanced` remains the stronger general accuracy choice.

Measured on Apple M4 Max (arm64); Apple Accelerate CPU, one math thread per native worker. Branch: `benchmark-spacy-hybrid`. No production profile or authoritative manifest changed.

## Accuracy

| Dataset | Documents | Native shared F1 | Native strict F1 | Balanced strict F1 | Accurate strict F1 |
|---|---:|---:|---:|---:|---:|
| generated_large | 648 | 0.7838 | 0.7190 | 0.7388 | 0.7531 |
| synth_dataset_v2 | 1500 | 0.7907 | 0.7315 | 0.7992 | 0.8024 |
| nemotron_pii_test_subset | 500 | 0.6938 | 0.5403 | 0.5659 | 0.5676 |

Parity covers all 18 entity labels and UTF-8 boundaries, before mapping PERSON→person and GPE/LOC/FAC→location. The live Elixir analyzer also produces identical final predictions for native and Python workers. All six structured categories match the deterministic control; repeated runs and native concurrency produce identical output fingerprints.

The historical shared F1 excludes boundary and wrong-type errors from FP/FN denominators. Strict F1 counts them as both a false positive and a false negative. This port preserves NER-only accuracy; it does not improve the trained model. The prior full-pipeline Nemotron strict F1 was 0.5404; this NER-only candidate is 0.5403. Balanced's 0.5659 remains higher. There was no threshold tuning, retraining, vector pruning, or use of gold to generate predictions.

## Live end-to-end CPU latency

| Dataset | Deterministic mean | Python hybrid mean | Native hybrid mean | Native p95 | Speedup vs Python |
|---|---:|---:|---:|---:|---:|
| generated_large | 0.104 ms | 1.828 ms | 0.379 ms | 0.807 ms | 4.82× |
| synth_dataset_v2 | 0.113 ms | 1.982 ms | 0.422 ms | 1.167 ms | 4.70× |
| nemotron_pii_test_subset | 0.353 ms | 12.282 ms | 2.017 ms | 4.420 ms | 6.09× |

Timings wrap actual `Obscura.analyze`: deterministic recognizers, live GenServer/Port request, JSON serialization, CPU inference, offset normalization, and normal conflict resolution. Both candidates use the same Elixir adapter and protocol. Two repetitions, five warmup documents per mode; mode order reverses in repetition two. Table entries average the two runs (p95 is the mean of run p95s). Startup and dataset loading are excluded. Historical GPU profile timings are not used as CPU speed comparisons.

## Startup and memory

| Worker | Startup to ready | Model load inside worker | Peak RSS across serial evaluation |
|---|---:|---:|---:|
| native | 23.8 ms | 19.9 ms | 169.7 MiB |
| python | 792.0 ms | 775.5 ms | 792.3 MiB |

Exported assets total 407.8 MiB; static vectors alone are 392.4 MiB. Native maps vectors read-only and faults in used pages; the measured RSS is workload-dependent, not an upper memory bound. RSS is the worker process high-water mark, excludes the BEAM, and includes each runtime's loaded vocabulary/model. Python uses the pinned model with only NER enabled. Startup uses fresh processes on a warm filesystem cache, not cold disk or fresh installation.

## Bounded native concurrency

Nemotron's same 500 documents, fixed 1/2/4-worker pools, one in-flight document per worker. Each row averages two repetitions; input sharding changes with pool size. No batching or queue-overload test.

| Native workers | Documents/second | Mean request latency | Sum of worker peak RSS |
|---:|---:|---:|---:|
| 1 | 620 | 1.604 ms | 147.9 MiB |
| 2 | 1030 | 1.911 ms | 250.0 MiB |
| 4 | 1984 | 1.955 ms | 427.0 MiB |

Summed RSS double-counts shared mapped pages and is not unique physical memory. These are short throughput runs, not a production soak, autoscaling policy, or tail-latency guarantee.

## Decision and limits

Proceed with a separately named experimental CPU integration if this speed/accuracy tradeoff fits the product. Keep `:balanced` as the general recommendation. The port avoids a Python runtime at inference and delivers substantial CPU savings while preserving this model's accuracy.

This is an Apple Silicon macOS feasibility implementation under `eval/spacy_native`, not a packaged production profile. Linux/Windows portability, supervised pool admission/recovery, signed/versioned model packaging, and a deployment-representative external test set remain work before shipping. Exact parity on these documents and handcrafted edge cases is evidence, not a proof for all possible Unicode/tokenizer inputs or future spaCy versions. The vector footprint remains substantial.

## Reproduction and provenance

See [README.md](../README.md) for build, export, tests, and benchmark commands. [comparison.json](comparison.json) contains shareable metrics and artifact hashes; no raw input text or gold spans are committed.

Source result: `/Users/humberto/Projects/obscura/eval/reports/spacy_native/20260905T002321Z/results.json`

SHA-256: `a39ba4ddd7e9ac2ecacdcd55db9426c987026e9b053f69f037b22f8b8afeb570`

Native binary SHA-256: `debd259120738b3514e955a38a03f4e9357c6f4d92f8416c45fb665ec6fcdc05`

Model manifest SHA-256: `ea006cbbe70e3f794a7136acf9c1d85199ee6925526578b3dc920ce2947fc95b`
