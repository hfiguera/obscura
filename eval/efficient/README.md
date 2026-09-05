# Efficient release evidence

The public name is `:efficient`. The legacy `:spacy_cpu` alias retains its
original model output policy. This directory contains independent evaluation
and workload evidence; it is not needed to install or use the profile.

The [protocol](PROTOCOL.md) was written before measuring candidates.
[Selection and gold hashes](accuracy-selection.json) freeze 5,000 development
and 5,000 untouched test documents from Gretel's publisher validation/test
splits at revision `e06eb1499ca8d54470f085021cd8e54f9efac7fd`.
The [boundary policy](boundary-policy.json) was frozen after development and
before observing heldout predictions. No rules were tuned on the final test.

## Independent accuracy

| Profile | Exact F1 | Precision | Recall | False positives | Missed gold spans |
| --- | ---: | ---: | ---: | ---: | ---: |
| fast | 0.6351 | 0.8425 | 0.5096 | 1,242 | 6,394 |
| original native spaCy | 0.6406 | 0.6416 | 0.6395 | 4,658 | 4,700 |
| efficient | **0.6654** | 0.6684 | 0.6625 | 4,286 | 4,401 |
| Presidio | 0.6102 | 0.5443 | 0.6942 | 7,578 | 3,987 |

These are 5,000 synthetic English application-like test documents and 13,039
gold spans across person, location, email, phone, SSN, card, IP, and date/time.
Unlike the earlier shared eight-entity benchmark, this policy includes
date/time and omits URL. Gold annotations are literal values rather than
offsets: the frozen loader finds word-bounded occurrences and joins adjacent
first/last names. No model predictions influence gold construction.
Twenty-eight supported annotation values in the test split could not be located
with that policy; their label counts are reported in the selection manifest.
Unsupported entity types are counted separately, without treating them as
covered. No documents were dropped for invalid annotations or deduplication.

The source is [Gretel's dataset](https://huggingface.co/datasets/gretelai/gretel-pii-masking-en-v1),
licensed Apache-2.0 and generated with Mistral Nemo. It has not been used in
Obscura's earlier tracked authoritative evaluations. It is independent of our
development split but is not a human-audited production sample. Incomplete or
inconsistent synthetic labels can affect both missed-span and false-positive
counts. The full [aggregate test report](results/heldout.json) includes
per-entity counts and partial-overlap coverage, clearly separate from exact
matches. Reports contain no source text.

Efficient improves person exact recall from 73.46% to 80.69% and location
exact recall from 6.70% to 14.42% versus the original native policy. Most gold
locations in this set are full addresses, for which spaCy provides poor exact
coverage. Efficient covers at least part of 879/1,761 gold locations; only 254
are exact. Exact false negatives include boundary/type mismatches. Supplementary
redaction-coverage counts distinguish fully unmasked gold spans: efficient
leaves 2,969 completely uncovered, versus 1,814 for Presidio; another 1,238
and 1,637 respectively are only partially covered. These descriptive metrics
were added after evaluation and did not affect policy selection. Coverage is
for this frozen eight-entity request, not the default thirteen-entity profile.

Relative to Presidio it produces 3,292 fewer false positives but
misses 414 more gold spans. Its advantage is the measured tradeoff, not uniform
dominance. No conclusion about `:balanced` on this new set is implied.

On development data, exact F1 increased from 0.6348 to 0.6645, with higher
person/location recall. See [development results](results/development.json).
The final test passes the predeclared accuracy gate: recall improves over
`:fast` and exact F1 does not regress from the original native profile.

## Reproduce accuracy

```sh
uv run --no-project --with pyarrow==21.0.0 python eval/efficient/prepare_accuracy.py
```

Set `OBSCURA_SPACY_MODEL_DIR` and `OBSCURA_SPACY_BINARY` to the verified assets.
For each split (`development`, `heldout`), run the live analyzer with the same
input file and each profile (`fast`, `spacy_cpu`, `efficient`):

```sh
EFFICIENT_PROFILE=efficient \
EFFICIENT_INPUT=.cache/efficient/gretel/heldout.json \
EFFICIENT_PREDICTIONS=.cache/efficient/gretel/heldout-efficient.json \
mix run --no-start eval/efficient/predict.exs
.presidio-authoritative-venv/bin/python eval/efficient/presidio.py \
  --input .cache/efficient/gretel/heldout.json \
  --output .cache/efficient/gretel/heldout-presidio.json
python3 eval/efficient/score.py --split heldout
```

Use `heldout-native.json` for the `spacy_cpu` prediction file. The Presidio
reference alone uses the separately pinned historical evaluation environment;
the installer and native runtime do not. Evaluation caches hold the downloaded
public text and raw predictions and are not committed or packaged.

## Workload validation

Run `EFFICIENT_REPORT=/output/report.json mix run --no-start
eval/efficient/workload.exs` after provisioning local assets. The default is
300 measured seconds after warmup for each of 1, 2, 3, and 4 workers. Shorter
pilot runs are explicitly ineligible to pass the release gate. The runner
checks saturation, caller death, native process loss, limits, recovery, and
shutdown, in addition to sustained throughput and current RSS.

The physical Linux host is a System76 Meerkat, Intel i5-1135G7 (4 cores/8
threads), 62 GiB RAM, Pop!_OS 22.04, with `systemd-detect-virt` reporting `none`.
It runs a native x86-64 Debian 12 container; it uses neither QEMU nor Docker
Desktop emulation. This validates physical CPU behavior but does not claim
the prebuilt binary runs against Pop!_OS's older host glibc outside a container.
Linux ARM64 runs natively in Docker Desktop's ARM64 VM on the Apple host.
macOS and the ARM64 VM share that host; throughput characterizes the validation
load and is not an isolated hardware ranking or promised production capacity.

All twelve final configurations passed: 300 measured seconds per worker count,
zero unexpected inference errors/restarts, and successful saturation, caller
death, native crash recovery, invalid-input, limit, and shutdown checks. Source
and executable hashes were captured before each run and verified unchanged
after it. The raw reports retain every ten-second sample:
[macOS ARM64](results/workload-macos-arm64.json),
[Linux ARM64](results/workload-linux-arm64.json), and
[physical Linux x86-64](results/workload-physical-linux-x86_64.json).

| Environment | Workers | Requests/s | p95 ms | p99 ms | Max sampled native RSS MiB | Native growth MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| macOS ARM64 | 1 | 36.88 | 15.4 | 1,230.4 | 84.1 | -0.12 |
| macOS ARM64 | 2 | 74.39 | 15.6 | 1,223.5 | 168.6 | -0.14 |
| macOS ARM64 | 3 | 104.99 | 17.0 | 1,244.8 | 244.1 | -6.88 |
| macOS ARM64 | 4 | 112.91 | 23.4 | 1,489.7 | 328.8 | 3.16 |
| Linux ARM64 | 1 | 33.34 | 18.6 | 1,341.3 | 75.0 | 0.00 |
| Linux ARM64 | 2 | 65.64 | 20.1 | 1,351.6 | 151.2 | 0.12 |
| Linux ARM64 | 3 | 87.52 | 22.3 | 1,487.6 | 223.1 | 1.87 |
| Linux ARM64 | 4 | 94.48 | 29.8 | 1,792.0 | 286.3 | 3.68 |
| Physical Linux x86-64 | 1 | 16.93 | 35.5 | 2,566.4 | 66.9 | 0.15 |
| Physical Linux x86-64 | 2 | 26.57 | 49.0 | 3,313.8 | 124.3 | -0.30 |
| Physical Linux x86-64 | 3 | 33.26 | 69.2 | 4,128.3 | 185.8 | 47.29 |
| Physical Linux x86-64 | 4 | 32.89 | 88.9 | 5,090.4 | 235.2 | 17.24 |

RSS is the sum across native workers and can count shared pages more than once;
BEAM RSS is separate in the reports. Growth compares the first sample after
the initial third of the run with the final sample. The largest native growth
was 47.29 MiB for three physical Linux workers, within the 96 MiB budget for
that configuration. This passes the regression gate without establishing
hours-long memory stability.

The mix contains 80% short, 18% medium, and 2% long documents. Its p99 includes
long documents and should not be read as short-request latency. On the physical
Linux host, three workers achieved the highest throughput; a fourth increased
latency without improving capacity. Select worker count against the actual
deployment's workload and contention.

## Installation, compatibility, and release status

[Build evidence](results/builds.json) records byte-identical independent native
rebuilds on all three targets, matching fresh model exports on macOS and Linux,
and a clean packaged consumer on Elixir 1.17.3 / OTP 27 with four native workers
and no Python, Nx, or Bumblebee. The full macOS suite passed 864 checks with
14 optional exclusions; native Linux compatibility passed 183 tests on each
architecture. The final installer/native tests passed another 34 checks.

A [heldout compatibility replay](results/prediction-parity.json) using the final
candidate produced identical typed byte spans on all 5,000 test documents
across macOS ARM64, Linux ARM64, and physical Linux x86-64. It did not change
the frozen policy or evaluation selection.

Run `python3 scripts/efficient/verify_candidate.py` to verify the local evidence
against the current sources and asset manifest. This checks evidence only and
never publishes anything. The candidate remains **unpublished** at the user's
request. The added hosted Linux CI workflow has not run and remains required
before a future release. Linux x86-64 and ARM64 servers are the production
targets. Apple Silicon macOS results validate the local development environment;
older macOS compatibility is outside the release requirements. All recorded
measurements and evaluation thresholds are unchanged by this platform scope.
