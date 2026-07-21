# Authoritative Presidio Comparison Report

## Status

This report is the current direct comparison between Obscura and Python
Presidio. It supersedes smoke comparisons and phase-local cross-project
numbers. Machine-readable evidence is in:

- `eval/authoritative/manifest.json`;
- `eval/authoritative/comparisons/generated_large.json`;
- `eval/authoritative/comparisons/synth_dataset_v2.json`;
- `eval/authoritative/comparisons/nemotron_pii_test_subset.json`.

All 15 rows are promoted. No fake serving, gold-derived prediction, skipped
run, or unpinned Python dependency is included.

## Reproducibility Contract

Python Presidio ran in a fresh environment created by
`eval/presidio_adapter/setup_authoritative_env.sh`:

| Component | Locked value |
| --- | --- |
| Python | CPython 3.11.15 |
| pip | 26.1.1 |
| `presidio-analyzer` | 2.2.363 |
| `presidio-evaluator` | 0.2.5 |
| spaCy | 3.8.13 |
| `en_core_web_lg` | 3.8.0 |
| Presidio analyzer source revision | `5c0ac333534955601f0649cff3e323ca5d5d7345` |
| Presidio-Research source revision | `2e9741154a3857712307b776cc2cd5f13c95c34b` |
| spaCy model wheel SHA-256 | `293e9547a655b25499198ab15a525b05b9407a75f10255e405e8c3854329ab63` |
| Python lock SHA-256 | `58ab6dd7246b230a847c06ecd15f86c2e23984bbbb8a1a6bb7f4f9aca9580063` |

The environment was built from scratch and its installed dependency set
matched the hash-locked requirements file.

## Shared Protocol

Every system consumed the same privacy-safe selection file for each dataset.
Those files lock the ordered sample IDs, selected text hashes, gold spans,
dataset fingerprint, split, entity policy, label mapping, offset policy, and
scoring policy.

- Protocol: `presidio_obscura_common_v1`.
- Entities: credit card, email, IP address, location, person, phone, URL, and
  US SSN.
- Offsets: half-open UTF-8 byte spans.
- Exact scoring: entity and boundaries must both match.
- IoU scoring: same entity with threshold 0.9.
- Unsupported expected spans: reported separately from false negatives.
- Protocol SHA-256:
  `dc7b6533f77104f0f08d12cb322b5425480fd7859c13ecd8fa59d2f17390ec80`.
- Entity/mapping policy SHA-256:
  `b2e8b8b3263f50cb187319ebb90532df2b154ec536558326029556921e6a2405`.
- Scoring policy SHA-256:
  `5cfd212921e345a7410c68dec31fbc6355ed7bc7b4a4221caa495c51c6b0ffaf`.

| Dataset/split | Samples | Dataset SHA-256 | Ordered-ID SHA-256 |
| --- | ---: | --- | --- |
| `generated_large/template_heldout` | 648 | `b84d6553a3fc27a5c664a1c2f95be15291ea16b83501e109d411fe237e380e26` | `abd254573ceacfd0a8472a48633db7a98e134c1be9e1c9301dda4e22ee372018` |
| `synth_dataset_v2/all` | 1500 | `ec08a771ba8135314cafb60752b2295212222ba3a4cd75d73811839c699e0012` | `4ae1a24321c77e5ec34560cfa25b5cecd3381f50fe4d69e5fc0ac69d0646b07c` |
| `nemotron_pii_test_subset/all` | 500 | `a36582d34f64ba871a604eabd53a8d92f0628b76ddb027105ac0f9d9a3042577` | `14206c51fbdafb0c28331bd07e74a26a6beede594c3edf4246163df32844972c` |

## Hardware And Runs

All systems ran on the same Apple M4 Max machine with 128 GiB memory and macOS
26.5.2. Each row has one warmup and two measured runs at concurrency one.
Accuracy counts were identical between repetitions.

Presidio spaCy and Obscura `:fast` ran on CPU. `:balanced`, `:accurate`, and
`:openmed_pii` ran through Emily 0.7.2 on Apple Metal GPU with fallback set to
`raise`. Their reports prove `actual_device=gpu`,
`backend_proven=true`, and `fallback_occurred=false`.

## Exact-Span Results

### Generated-Large Heldout

| System | Precision | Recall | F1 | F2 | IoU F1 | TP | FP | FN | Offset | Wrong | Unsupported |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Presidio spaCy | 0.7338 | 0.6351 | 0.6809 | 0.6527 | 0.6445 | 590 | 214 | 339 | 43 | 48 | 964 |
| Obscura `:fast` | 0.9618 | 0.5101 | 0.6667 | 0.5630 | 0.6379 | 503 | 20 | 483 | 34 | 0 | 964 |
| Obscura `:balanced` | 0.8237 | 0.7550 | 0.7878 | 0.7678 | 0.7421 | 724 | 155 | 235 | 58 | 3 | 964 |
| Obscura `:accurate` | 0.8249 | 0.7810 | 0.8024 | 0.7894 | 0.7564 | 749 | 159 | 210 | 58 | 3 | 964 |
| Obscura `:openmed_pii` | 0.3341 | 0.7826 | 0.4683 | 0.6170 | 0.4044 | 594 | 1184 | 165 | 203 | 58 | 964 |

### Synth Dataset V2

| System | Precision | Recall | F1 | F2 | IoU F1 | TP | FP | FN | Offset | Wrong | Unsupported |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Presidio spaCy | 0.6993 | 0.7442 | 0.7211 | 0.7348 | 0.6874 | 1065 | 458 | 366 | 73 | 71 | 1288 |
| Obscura `:fast` | 0.9349 | 0.4844 | 0.6382 | 0.5361 | 0.6207 | 747 | 52 | 795 | 33 | 0 | 1288 |
| Obscura `:balanced` | 0.8297 | 0.8480 | 0.8388 | 0.8443 | 0.8018 | 1272 | 261 | 228 | 75 | 0 | 1288 |
| Obscura `:accurate` | 0.8266 | 0.8586 | 0.8423 | 0.8520 | 0.8049 | 1287 | 270 | 212 | 76 | 0 | 1288 |
| Obscura `:openmed_pii` | 0.3306 | 0.7920 | 0.4665 | 0.6192 | 0.3909 | 891 | 1804 | 234 | 362 | 88 | 1288 |

### Nemotron PII Test Subset

| System | Precision | Recall | F1 | F2 | IoU F1 | TP | FP | FN | Offset | Wrong | Unsupported |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Presidio spaCy | 0.5970 | 0.6565 | 0.6254 | 0.6437 | 0.5402 | 883 | 596 | 462 | 329 | 51 | 2361 |
| Obscura `:fast` | 0.8037 | 0.2729 | 0.4074 | 0.3144 | 0.4218 | 438 | 107 | 1167 | 101 | 19 | 2361 |
| Obscura `:balanced` | 0.8703 | 0.5790 | 0.6954 | 0.6206 | 0.6105 | 839 | 125 | 610 | 258 | 18 | 2361 |
| Obscura `:accurate` | 0.8716 | 0.5811 | 0.6973 | 0.6226 | 0.6121 | 842 | 124 | 607 | 258 | 18 | 2361 |
| Obscura `:openmed_pii` | 0.4928 | 0.9825 | 0.6564 | 0.8196 | 0.6555 | 1680 | 1729 | 30 | 13 | 2 | 2361 |

Exact F1 remains the primary decision metric because correct redaction
boundaries matter; IoU does not replace exact-span evidence.

## Latency

| Dataset | System/device | Mean ms | Median ms | P95 ms | Throughput samples/s |
| --- | --- | ---: | ---: | ---: | ---: |
| Generated | Presidio CPU | 3.4169 | 3.2025 | 6.2047 | 292.6647 |
| Generated | `:fast` CPU | 0.1338 | 0.0710 | 0.2970 | 7473.4451 |
| Generated | `:balanced` GPU | 21.4730 | 21.0990 | 23.6370 | 46.5701 |
| Generated | `:accurate` GPU | 34.4296 | 40.0890 | 48.5730 | 29.0448 |
| Generated | OpenMed GPU | 231.5783 | 222.2150 | 317.5720 | 4.3182 |
| Synth | Presidio CPU | 3.7588 | 3.1656 | 7.0820 | 266.0436 |
| Synth | `:fast` CPU | 0.1208 | 0.0690 | 0.3960 | 8276.9581 |
| Synth | `:balanced` GPU | 22.3443 | 21.9680 | 24.7180 | 44.7541 |
| Synth | `:accurate` GPU | 39.7342 | 43.6420 | 49.0420 | 25.1673 |
| Synth | OpenMed GPU | 234.0717 | 217.4650 | 350.2980 | 4.2722 |
| Nemotron | Presidio CPU | 24.4653 | 20.7062 | 57.9023 | 40.8742 |
| Nemotron | `:fast` CPU | 0.3189 | 0.2410 | 0.6170 | 3136.2120 |
| Nemotron | `:balanced` GPU | 24.3216 | 23.9910 | 26.7610 | 41.1157 |
| Nemotron | `:accurate` GPU | 66.0605 | 76.3800 | 86.3340 | 15.1376 |
| Nemotron | OpenMed GPU | 919.5933 | 743.9320 | 2063.1230 | 1.0874 |

Only Presidio CPU versus `:fast` CPU is a direct latency comparison. The GPU
rows are descriptive operating evidence. A CPU-to-GPU speed ranking would be
misleading even though every run used the same physical machine.

The OpenMed refresh uses the optimized default context policy. Its two default
repetitions and one explicit-policy run have identical output fingerprints.
The previous Nemotron row used `n_ctx=128`; removing those artificial context
boundaries explains the small accuracy gain and is recorded as a policy change,
not nondeterministic model output.

## Entity-Level Findings

Obscura `:balanced` improves the broad model-backed categories on the two
Presidio-Research corpora:

- generated person F1: 0.9211 versus Presidio 0.7712;
- generated location F1: 0.6341 versus 0.4071;
- synth person F1: 0.9506 versus 0.7795;
- synth location F1: 0.6267 versus 0.4554.

Presidio remains better on generated and synth phone F1: 0.7487 versus 0.7072,
and 0.6375 versus 0.5391. On Nemotron, Presidio remains better for location and
IP address, while `:balanced` is better for person, phone, URL, and US SSN.
That mixed result is why this report does not claim universal superiority.

## Decision

Obscura is working. The deterministic path is extremely precise and fast but
recall-limited. `:accurate` is the strongest measured general choice under this
shared eight-entity protocol and exceeds Presidio exact F1 by `0.1215` on
generated heldout, `0.1212` on synth, and `0.0719` on Nemotron.

`:fast`, `:balanced`, and `:accurate` have stable Obscura profile contracts.
`:accurate` has the best measured general F1 under this protocol, while
`:balanced` remains the practical one-model recommendation. The optional TNER
checkpoint is neither bundled nor licensed by Obscura; deployers remain
responsible for establishing applicable asset rights. The `:openmed_pii` row is
an authoritative measurement of an experimental alias, not evidence that it
belongs in the stable product surface.

The implementation is not complete Presidio parity. Presidio still wins some
entity-specific comparisons, model-backed Obscura profiles require optional
assets and an accelerator for the measured operating point, and all three
corpora are synthetic. Production adoption still requires evaluation on the
deployment language, entity taxonomy, input distribution, hardware, and
false-positive tolerance.

## Privacy And Promotion Checks

- Prediction interchange files omitted source text and matched values.
- Human reports contain aggregate metrics, safe identifiers, and hashes only.
- Raw and transient prediction exports are not authoritative artifacts.
- Promotion rejected mismatched hashes, samples, policies, incomplete runs,
  fake/gold-derived output, and unstable repetitions.
- The benchmark verification task checks manifest/report integrity.
- The Python comparison script refuses reports not promoted in the manifest.

```sh
mix obscura.benchmarks.verify
```

## Reproduction

Follow `eval/presidio_adapter/README.md` to create the exact Python environment,
prepare selections, execute two Presidio repetitions, score them with the
Elixir evaluator, run the same Obscura profiles, and promote only after all
hash and repetition checks pass. The authoritative manifest is the final source
of truth; files under `eval/reports/` are working or historical artifacts.
