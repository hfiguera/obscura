# Native spaCy CPU feasibility prototype

This is a Python-free Rust implementation of the pinned `en_core_web_lg` 3.8.0
NER inference path, connected to Obscura through an Elixir Port worker and the
existing custom recognizer interface. It uses the original learned weights,
tokenizer assets, vocabulary normalization, and static vectors. It does not
introduce a production profile or change the existing profiles.

The measured outcome and recommendation are in [results/RESULTS.md](results/RESULTS.md).
This follows the [Python-reference experiment](../spacy_hybrid/README.md).

The Rust source now lives in `native/spacy_cpu`. The opt-in `:spacy_cpu` profile
and owned worker pool are documented in [../../docs/spacy-cpu.md](../../docs/spacy-cpu.md).
Profile integration validation is in [results/PROFILE.md](results/PROFILE.md).
The original feasibility artifacts below remain a historical measurement.

## Scope

- Apple Silicon macOS CPU; Accelerate matrix multiplication and Homebrew PCRE2.
- Native tokenization, lexical feature hashes, four-layer residual maxout CNN,
  token projection, precomputed transition features, and greedy BILUO decoder.
- All 18 labels compete during decoding. Only PERSON and GPE/LOC/FAC enter
  Obscura as person/location; the assigned score remains 0.85, not a calibrated
  probability. Obscura's deterministic recognizers and normal conflict rules run.
- NER-only blank-document inference, with no supplied sentence/entity attributes.
  This preserves the NER-only candidate, which differs slightly from Presidio's
  full pipeline. It does not implement training, beam search, or arbitrary models.
- One request at a time per persistent worker. 1 MiB input, 10,000-token limit,
  bounded JSON frames, 30-second response timeout, and error propagation through
  the recognizer. No silent fallback if the native worker fails.

The runtime does not invoke Python. Python is used to export immutable assets,
test parity, load evaluation data, and run a separately identified timing control.
This is a native executable via a Port, not an in-process NIF.

## Export and build

From the repository root, with the existing pinned Python evaluation environment,
Rust, Xcode command-line tools, and ARM64 Homebrew PCRE2 installed:

```sh
.presidio-authoritative-venv/bin/python eval/spacy_native/export.py
cargo build --release --locked --target aarch64-apple-darwin --manifest-path native/spacy_cpu/Cargo.toml
```

The explicit target also works when the default Rust toolchain runs under Rosetta.
Build output and the roughly 408 MiB of exported assets are ignored by Git.
Export validates the pinned packages and records hashes of all original model
files and exported binaries. It never reads a benchmark dataset or gold labels.
Assets must remain unmodified while mapped by a worker.

## Use the prototype with Obscura

Load `eval/spacy_native/native.exs` in a local Mix session:

```sh
iex -S mix run --no-start -r eval/spacy_native/native.exs
```

```elixir
{:ok, worker} = Obscura.SpacyNative.Worker.start_link()

Obscura.analyze("José García lives in São Paulo.",
  profile: :deterministic_plus,
  include_text: false,
  recognizers: [{Obscura.SpacyNative.Recognizer, worker: worker}]
)

GenServer.stop(worker)
```

The executable also accepts one JSON request per stdin line after emitting its
readiness response. Requests contain `text`; responses contain label/byte offsets,
assigned scores, timings, and worker RSS. Raw input text is not echoed. Diagnostic
`debug` and `tokens_only` requests are for local parity testing.

## Reproduce the experiment

```sh
VECLIB_MAXIMUM_THREADS=1 .presidio-authoritative-venv/bin/python eval/spacy_native/benchmark.py
.presidio-authoritative-venv/bin/python eval/spacy_native/report.py --results PATH_TO_RESULTS_JSON
```

The benchmark validates all three authoritative selections (648 generated heldout,
1,500 Synth v2, 500 Nemotron documents), original model hashes, native binary hash,
and prediction artifact hashes. It uses two repetitions and five warmup documents
per mode. All-label byte-span parity is checked against fresh pinned spaCy NER-only
predictions, then checked again when the live Elixir workers run. Native and Python
final analyzer outputs, deterministic structured spans, repetitions, and concurrency
fingerprints must agree. Only the shared Elixir evaluator computes accuracy.

Live timings cover actual `Obscura.analyze`, including IPC and serialization for
both the native worker and Python control. Additional 1/2/4-worker measurements
use the same Nemotron selection. They measure a bounded, closed workload, not
queue overload or a long-running production service. The deterministic analyzer
is the fresh CPU control; authoritative balanced/accurate rows are used for accuracy
only, not for speed comparisons across different hardware/backends.

`--skip-elixir` runs only reference/native parity. `--datasets generated_large`
is a shorter full-selection check. `--out-dir` must identify a new directory.
Detailed reports live under ignored `eval/reports/spacy_native/<timestamp>/`;
the shareable report retains metrics, IDs, byte offsets, and hashes, without raw
input text, raw gold spans, or trained weights. No authoritative rows are promoted.

## Verification

```sh
cargo fmt --manifest-path native/spacy_cpu/Cargo.toml --check
cargo clippy --release --locked --target aarch64-apple-darwin --manifest-path native/spacy_cpu/Cargo.toml -- -D warnings
VECLIB_MAXIMUM_THREADS=1 .presidio-authoritative-venv/bin/python -m unittest discover -s eval/spacy_native -p 'test_*.py'
mix run --no-start -r eval/spacy_native/native.exs -r eval/spacy_native/test_native.exs -e ':ok'
mix obscura.benchmarks.verify
```

The Python tests cover handcrafted ASCII/Unicode/tokenizer cases, intermediate
neural-layer parity, empty input, request limits, and recovery after errors.
The Elixir tests cover UTF-8 offsets and structured precedence through the actual
analyzer, concurrent callers, limits, and failure propagation. Dataset-wide parity
and accuracy are additional experiment checks, not assertions fabricated from gold.

## Source and implementation notes

The port follows the installed spaCy 3.8.13 / Thinc 8.3.13 source:

- `spacy/tokenizer.pyx`, `spacy/lang/lex_attrs.py`, `spacy/strings.pyx`.
- `spacy/ml/models/tok2vec.py`, `spacy/ml/models/parser.py`,
  `spacy/ml/staticvectors.py`, `spacy/ml/_precomputable_affine.py`.
- `spacy/pipeline/_parser_internals/ner.pyx` and `_state.pxd`.
- `thinc/layers/hashembed.py`, `maxout.py`, `layernorm.py`, `with_array.py`,
  `thinc/backends/numpy_ops.pyx`.

Important compatibility details include reserved string IDs, MurmurHash variants,
Python Unicode shape flags, tokenizer exception normalization, four-token padding
around the whole residual CNN, and all 74 transition classes. Python Unicode regex
escape syntax is translated for PCRE2. Numerical operations are f32; tiny differences
between Accelerate and BLIS are expected and intermediate activations are checked.

The vector table is mapped read-only; measured resident memory grows with the pages
the workload touches. It is not compressed or pruned. A production implementation
would still need portable packaging, supervised pool admission/recovery, deployment
validation beyond these previously inspected datasets, and model provenance review.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
