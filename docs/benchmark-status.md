# Authoritative Benchmark Status

The source of truth for current product evidence is
`eval/authoritative/manifest.json`. Reports under ignored `eval/reports/` are
historical or working artifacts unless the manifest promotes them.

The current matrix was generated on an Apple M4 Max with 128 GiB memory and
macOS 26.5.2 under `presidio_obscura_common_v1`. Every row uses the same
ordered sample IDs, dataset bytes, eight-entity policy, mapping policy, UTF-8
byte offsets, and exact/IoU evaluator. Every row has two measured repetitions
with identical accuracy counts. Model profiles used Emily/Metal GPU with
fallback set to `raise`; Presidio spaCy and `:fast` used CPU.

| Dataset | Profile | Precision | Recall | F1 | F2 | Mean ms | P95 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `generated_large/template_heldout` | Presidio spaCy | 0.7338 | 0.6351 | 0.6809 | 0.6527 | 3.4169 | 6.2047 |
| `generated_large/template_heldout` | `:fast` | 0.9618 | 0.5101 | 0.6667 | 0.5630 | 0.1338 | 0.2970 |
| `generated_large/template_heldout` | `:balanced` | 0.8237 | 0.7550 | 0.7878 | 0.7678 | 21.4730 | 23.6370 |
| `generated_large/template_heldout` | `:accurate` | 0.8249 | 0.7810 | 0.8024 | 0.7894 | 34.4296 | 48.5730 |
| `generated_large/template_heldout` | `:openmed_pii` | 0.3341 | 0.7826 | 0.4683 | 0.6170 | 231.5783 | 317.5720 |
| `synth_dataset_v2` | Presidio spaCy | 0.6993 | 0.7442 | 0.7211 | 0.7348 | 3.7588 | 7.0820 |
| `synth_dataset_v2` | `:fast` | 0.9349 | 0.4844 | 0.6382 | 0.5361 | 0.1208 | 0.3960 |
| `synth_dataset_v2` | `:balanced` | 0.8297 | 0.8480 | 0.8388 | 0.8443 | 22.3443 | 24.7180 |
| `synth_dataset_v2` | `:accurate` | 0.8266 | 0.8586 | 0.8423 | 0.8520 | 39.7342 | 49.0420 |
| `synth_dataset_v2` | `:openmed_pii` | 0.3306 | 0.7920 | 0.4665 | 0.6192 | 234.0717 | 350.2980 |
| `nemotron_pii_test_subset` | Presidio spaCy | 0.5970 | 0.6565 | 0.6254 | 0.6437 | 24.4653 | 57.9023 |
| `nemotron_pii_test_subset` | `:fast` | 0.8037 | 0.2729 | 0.4074 | 0.3144 | 0.3189 | 0.6170 |
| `nemotron_pii_test_subset` | `:balanced` | 0.8703 | 0.5790 | 0.6954 | 0.6206 | 24.3216 | 26.7610 |
| `nemotron_pii_test_subset` | `:accurate` | 0.8716 | 0.5811 | 0.6973 | 0.6226 | 66.0605 | 86.3340 |
| `nemotron_pii_test_subset` | `:openmed_pii` | 0.4928 | 0.9825 | 0.6564 | 0.8196 | 919.5933 | 2063.1230 |

Accuracy values are directly comparable. Latency is directly comparable only
between Presidio CPU and `:fast` CPU. Balanced, accurate, and OpenMed latency is
descriptive because those profiles used Emily GPU. No CPU-vs-GPU speed claim is
made.

## Decisions

- `:fast` is the high-precision, low-latency structured PII choice. Its recall
  is intentionally limited.
- `:accurate` has the highest measured general F1 on all three shared datasets.
  Its stable profile contract uses two large models. Commercial use requires an
  LDC for-profit membership because TNER is its primary model.
- `:balanced` remains the practical model-backed recommendation for
  noncommercial evaluation or LDC-authorized deployments. Its F1 is slightly
  lower, but it uses one model and has materially lower latency.
- `:hybrid_gliner_urchade` is the public experimental CPU-only general NER
  alternative. Its reproducible adapter and clearer Apache-2.0 provenance chain
  support that scoped recommendation, but its lower F1 prevents replacing
  `:balanced` as the accuracy recommendation.
- Stable `:accurate` runs an output-aware location cascade. It beats
  `:balanced` by `0.0145`, `0.0035`, and `0.0019` F1, but is not the default
  recommendation because it uses a second model and has higher operating cost.
- Experimental `:openmed_pii` has the highest Nemotron recall and F2, but low
  precision, high operational cost, and unresolved production risks prevent a
  stable or general recommendation.

The matrix does not establish universal accuracy, production fitness, or
regulatory compliance. The corpora are synthetic and taxonomy-dependent.

## Promoted Accurate Cascade

Stable `:accurate` now resolves to
`:hybrid_ner_tner_jean_location_cascade`. Its policy is locked to missing
location, Jean `LOC=0.999`, and no secondary context gate. Two clean Emily GPU
repetitions through the actual alias produced identical fingerprints and F1
`0.8024`, `0.8423`, and `0.6973`. The full operational matrix also passed.
The former `:hybrid_ner_tner_jean_location` implementation remains explicitly
callable but is no longer the alias. The promoted policy and repetitions are
recorded in `eval/authoritative/manifest.json`.

The refreshed OpenMed rows use the default `openmed_latency_v1` context policy:
adaptive `[192, 256, 384, 512, 768]` sequence buckets above `129` tokens,
Viterbi decoding, and raw-logit conversion. Two default repetitions and an
explicit equivalent configuration produced identical output fingerprints on
all three datasets. Generated and synth accuracy counts are unchanged from
the superseded authority. Nemotron changed because the old authority used
explicit `n_ctx=128` boundaries; under the new default, TP increased from
`1646` to `1680`, FN fell from `35` to `30`, wrong types fell from `7` to `2`,
and offset mismatches fell from `37` to `13`.

## Comparison With Presidio

Presidio spaCy is now an external baseline in the authoritative manifest, not
an Obscura profile. On exact-span F1, `:accurate` exceeds Presidio on
generated-large heldout (`0.8024` vs `0.6809`), synth (`0.8423` vs `0.7211`),
and Nemotron (`0.6973` vs `0.6254`). This is evidence for this exact protocol,
not universal Presidio superiority.

Presidio remains stronger than `:fast` on recall and F2. It also has better
broad-data precision than OpenMed. Entity-level evidence shows `:balanced`
improves person and location F1 on generated/synth, while Presidio remains
better on generated/synth phone F1. The complete exact, IoU, count, per-entity,
repetition, environment, and artifact evidence is in
`eval/authoritative/manifest.json` and `eval/authoritative/comparisons/`.

## Regression Policy

- Deterministic fixtures and operator outputs are blocking exact contracts.
- Report shape, hashes, profile identity, and backend proof are blocking.
- Accuracy changes up to 0.005 absolute F1 are review alerts. Changes above
  0.010 require an explicit accepted-regression note or a fix.
- Critical structured entities must not lose exact deterministic fixture
  coverage.
- Latency comparisons are valid only on the same hardware, backend, device,
  compile settings, and dataset fingerprint.
- A repeated latency increase above 15% is an alert. Accelerator latency is
  scheduled-run evidence and does not block dependency-light pull requests.
- Train-split tuning may select policy, but only heldout/external datasets may
  support final accuracy claims.

Promote new evidence with:

```sh
mix obscura.benchmarks.promote
```

Promotion rejects
skipped or fake/gold-derived runs, mismatched metrics, missing revisions/hashes,
unsafe raw values, and inconsistent repetitions.

Operational startup, concurrency, throughput, p99, memory, sustained-load, and
recovery evidence is governed separately by
`eval/operational/manifest.json`.
Accuracy-report latency is not a substitute for that production-style load
protocol.

The current OpenMed optimization and default-versus-explicit parity evidence
is promoted in the authoritative manifests.

The Apple/Emily operational matrix is promoted for all 12 measured
profile/dataset combinations. Stable `:balanced` is the practical best-measured
general model-backed operating point. Stable `:accurate` uses the highest-F1
cascade; C1 is the interactive
choice and C2-C4 are bounded throughput options depending on workload.
Experimental `:openmed_pii` requires bounded specialized execution because of high tail
latency and transient memory pressure.

The separate long-soak manifest contains four same-revision Apple rows.
Its classifier labels OpenMed C1 and C4 as allocator caching, and no row
classifies as a probable leak. The release conclusion remains
**inconclusive**, however: neither the historical soak nor the refreshed
operational matrix proves bounded growth over a production-duration workload.
`:fast` and `:balanced` memory are also inconclusive. OpenMed's historical
first/last latency difference is primarily an ordered input-length/shape
cycle, while `:balanced` slowdown is localized to model serving.

Experimental adapters which are absent from the authoritative manifest are not
product accuracy claims. Their asset and compatibility contracts remain
available for controlled evaluation through `profiles.md` and
`optional-dependencies-and-assets.md`.
