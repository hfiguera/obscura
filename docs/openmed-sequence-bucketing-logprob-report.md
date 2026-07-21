# OpenMed Sequence Bucketing And Logit Decoding Report

## Conclusion

The OpenMed optimization succeeded for its intended workload.

Obscura now prepares `:openmed_pii` with:

- adaptive sequence-length buckets `[192, 256, 384, 512, 768]`;
- a `129`-token activation threshold, leaving shorter requests unpadded;
- direct raw-logit Viterbi decoding when no probability threshold is required;
- the existing reference log-probability path when callers request
  `:argmax` or `:privacy_filter_min_span_logprob`.

On the committed-source C4 matrix, the combined candidate reduced the
Nemotron subset p95 by `11.46%`, reduced p99 by `3.82%`, increased throughput
by `4.69%`, and reduced distinct measured shapes from `32` to `17`. Short
datasets remained within about `2%` run variance because the bucket threshold
made bucketing a no-op for their selected samples.

The clean 30-minute mixed C4 confirmation improved throughput by `21.08%` and
mean latency by `17.37%` against the previous matched operational soak. It
completed with zero failures, timeouts, rejections, or output mismatches.

This is a latency and capacity improvement. Within the controlled experiment,
exact output fingerprints prove bucketing and raw-logit conversion do not
change recognition results for the same context policy.

The later authoritative refresh found one important policy distinction: the
superseded accuracy rows explicitly used `n_ctx=128`, while the optimized
default uses adaptive full-request buckets. Generated and synth accuracy stayed
identical; Nemotron accuracy improved slightly because 128-token context
boundaries were removed. That is an explained context-policy change, not an
optimization mismatch or nondeterministic result.

## Provenance

| Field | Value |
| --- | --- |
| Implementation commit | `505eea09293086ec0f3e046e734442ea63c0ea19` |
| Matrix source worktree | clean |
| Long-soak source worktree | clean |
| Host | Apple M4 Max, 128 GiB |
| Backend | Emily GPU |
| Emily fallback | `raise` |
| Fallback observed | false |
| Checkpoint | pinned local `OpenMed/privacy-filter-nemotron-v2` |
| Concurrency | 4 |
| Matrix repetitions | 2 |
| Warm passes per report | 2 |
| Samples per dataset/report | 32, token-length stratified |
| Long confirmation | 30 minutes, all 2,648 authoritative samples |

Every matrix report records `actual_backend: emily`,
`actual_device: gpu`, `backend_proven: true`, and
`fallback_occurred: false`.

## Why Bucketing Works

The pinned tokenizer produced materially different sequence distributions:

| Dataset | Samples | Min | p50 | p95 | p99 | Max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `generated_large/template_heldout` | 648 | 4 | 20 | 46 | 57 | 65 |
| `synth_dataset_v2/all` | 1,500 | 4 | 19 | 53 | 78 | 97 |
| `nemotron_pii_test_subset/all` | 500 | 29 | 157 | 440 | 558 | 686 |

Padding every request to a global bucket harmed short-text latency. The
accepted policy therefore leaves lengths below `129` unchanged and buckets
only longer requests. On the stratified Nemotron sample, this reduced distinct
shapes from `32` to `17` with mean padding of `9.53%`.

This policy targets the proven first-seen-shape cost without forcing the
short datasets to execute substantially larger tensors.

## Why Raw Logits Are Correct For Viterbi

For each token, log-softmax converts a logit `z_i` to:

```text
log_softmax(z_i) = z_i - log(sum(exp(z)))
```

The subtracted value is the same for every label at that token. Every complete
Viterbi path includes exactly one emission from every token, so each path loses
the same sum of per-token constants. The path ordering and selected label
sequence are therefore unchanged.

Obscura permits `:raw_logits` only when:

- the decoder is Viterbi; and
- no `min_span_logprob` is configured.

Probability-based filtering still receives real log-probabilities. Contract
tests reject incompatible configurations, and real-model fingerprints verify
the mathematical equivalence on all three datasets.

Raw logits alone yield modest gains because `Nx.to_list/1` still synchronizes
and transfers the tensor to the host. The experiment removes log-softmax work;
it does not eliminate the host decoder or transfer.

## Controlled Matrix

Values are averages over four warm passes: two independent reports with two
warm passes each. Positive throughput deltas and negative latency deltas are
improvements.

### Combined Versus Baseline

| Dataset | Variant | Req/s | p50 ms | p95 ms | p99 ms | Mean ms | Shapes | Padding |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| generated heldout | baseline | 10.309 | 341.08 | 583.85 | 665.25 | 357.06 | 26 | 0% |
| generated heldout | combined | 10.387 | 347.68 | 580.11 | 670.78 | 353.64 | 26 | 0% |
| synth v2 | baseline | 9.790 | 335.63 | 687.32 | 848.17 | 364.23 | 29 | 0% |
| synth v2 | combined | 9.875 | 328.51 | 672.68 | 836.29 | 360.97 | 29 | 0% |
| Nemotron subset | baseline | 1.657 | 1,874.90 | 4,827.78 | 5,811.94 | 2,104.04 | 32 | 0% |
| Nemotron subset | combined | 1.735 | 1,807.00 | 4,274.62 | 5,589.86 | 1,989.29 | 17 | 9.53% |

### Combined Deltas

| Dataset | Throughput | p50 | p95 | p99 | Mean |
| --- | ---: | ---: | ---: | ---: | ---: |
| generated heldout | +0.76% | +1.94% | -0.64% | +0.83% | -0.96% |
| synth v2 | +0.87% | -2.12% | -2.13% | -1.40% | -0.89% |
| Nemotron subset | +4.69% | -3.62% | -11.46% | -3.82% | -5.45% |

The generated-heldout p50/p99 changes are sub-2% variance on an identical
unbucketed path, not evidence of a causal regression. The two-repetition
matrix contains no failures or timeouts.

### Isolated Experiments

On the Nemotron subset:

| Variant | Req/s | p95 ms | p99 ms | Logit/log-prob stage mean | Shapes |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline | 1.657 | 4,827.78 | 5,811.94 | 540.36 ms | 32 |
| bucketing only | 1.740 | 4,318.18 | 5,503.38 | 512.41 ms | 17 |
| raw logits only | 1.670 | 4,810.25 | 5,675.49 | 536.29 ms | 32 |
| combined | 1.735 | 4,274.62 | 5,589.86 | 513.20 ms | 17 |

Bucketing supplies most of the short matrix gain. Raw logits are retained
because they are exact, bounded by configuration checks, improve or remain
neutral across the clean matrix, and contribute to the sustained combined
result.

The `32 -> 17` distinct-shape result is evidence from this controlled,
32-sample optimization matrix only. The refreshed full operational schema does
not count backend-compiled shapes, so `17` is not presented as a current
full-dataset shape count. Current authority proves the configured bucket set
and output stability, not Emily's internal compiled-shape cardinality.

## Output And Accuracy Parity

All four variants produced one identical historical operational fingerprint
per dataset across every warm pass:

| Dataset | Output SHA-256 |
| --- | --- |
| generated heldout | `a557a37ba831b4d354e3e22c603b427565beb9f745240883b797fb2dc99f719f` |
| synth v2 | `3a45c0600369318ddd379c66fb80f95fe816d4ca9d9bdc6b98236873668f1586` |
| Nemotron subset | `708d1ee4828c30b01e54524967d7a9b5b4dc3c81e8e1293a58c4e38b0a82e349` |

The 30-minute run also covered every authoritative sample and recorded:

- `2,648` unique samples;
- `5,096` repeated fingerprint checks;
- `0` fingerprint mismatches;
- stable per-dataset probes;
- the same whole-workload fingerprint as the previous unoptimized soak.

The later authoritative accuracy rerun uses a canonical prediction fingerprint
that is stable across processes and prediction ordering:

| Dataset | Authoritative output SHA-256 |
| --- | --- |
| generated heldout | `72d4a3d9a414233c3b480b391622f5c94bd69cbb14afba7169d2466d33563c8a` |
| synth v2 | `de61778cac093240d4c1650021d0af8a07c70da43d990c71bebb013fc007de57` |
| Nemotron subset | `67d2e9e1e3a530385a66b44193d34bc78d15f2492238f09d9051037fab596e27` |

Two default repetitions and one explicit optimized-policy run produced the
same fingerprint for each dataset. Current common-protocol accuracy is:

| Dataset | Precision | Recall | F1 | F2 |
| --- | ---: | ---: | ---: | ---: |
| generated heldout | 0.3341 | 0.7826 | 0.4683 | 0.6170 |
| synth v2 | 0.3306 | 0.7920 | 0.4665 | 0.6192 |
| Nemotron subset | 0.4928 | 0.9825 | 0.6564 | 0.8196 |

The Python/OpenMed parity conclusion is unchanged. The Nemotron delta versus
the old authority is attributable to context length: TP `1646 -> 1680`, FN
`35 -> 30`, wrong type `7 -> 2`, and offset mismatch `37 -> 13`.

## Thirty-Minute Confirmation

The accepted candidate ran the mixed three-dataset order at C4 for 30 minutes.

| Metric | Previous matched soak | Optimized soak | Change |
| --- | ---: | ---: | ---: |
| Completed | 6,404 | 7,744 | +20.92% |
| Throughput | 3.553 req/s | 4.301 req/s | +21.08% |
| Mean latency | 1,125.33 ms | 929.82 ms | -17.37% |
| Weighted window p50 | 939.94 ms | 795.02 ms | -15.42% |
| Weighted window p95 | 2,667.64 ms | 2,037.98 ms | -23.60% |
| Weighted window p99 | 3,672.88 ms | 2,535.88 ms | -30.96% |
| Failures / timeouts / rejects | 0 / 0 / 0 | 0 / 0 / 0 | unchanged |

Weighted window percentiles are comparable summaries because the older soak
schema did not retain whole-run percentiles. The optimized run's direct
whole-run values are p50 `565` ms, p95 `2,650` ms, and p99 `4,650` ms.

The last full optimized minute recovered to `9.73` req/s with p95 `595` ms.
The runtime was prepared once, no per-request rebuild was detected, and
timeout, overload, serving-crash recovery, and report-privacy checks passed.

## Memory

The refreshed full operational matrix observed peak process RSS of
`48.303 GiB` and peak Emily allocator statistics of `41.293 GiB` across
different rows. Its 60-second mixed sustained run grew sampled RSS by
`7.4 MiB`. These values must not be summed.

The 30-minute memory classification was `inconclusive` for RSS and live
allocator trends. After the run:

- RSS fell from `972.5` MB before idle to `902.4` MB after idle and GC;
- clearing the Emily cache reduced RSS to `756.2` MB;
- Emily cache fell to zero;
- active Emily allocation remained about `2.80` GB.

These observations do not prove a leak, but neither the refreshed matrix nor
the historical 30-minute soak satisfies the project's production-duration
bounded-memory rule. The latency optimization is accepted; memory remains
explicitly **inconclusive**.

## Rejected Experiments

### Global Bucketing

Applying `[16, 32, 64, 128, 192, 256, 384, 512, 768]` to every request added
about `19%` padding on short datasets and regressed their latency and
throughput. It was replaced by the `129`-token adaptive gate.

### Compiled Log-Softmax

Wrapping log-softmax in `Nx.Defn` did not produce a repeatable `25%` stage
improvement and did not improve the full matrix. The extra implementation was
removed.

### Accelerator Viterbi

Dense and sparse Nx Viterbi implementations exactly matched the reference
decoder, but accelerator synchronization and backtracking moved cost from
log-prob conversion into decode. Short-dataset throughput fell by roughly
`10%`; the implementation was removed. This confirms the original diagnosis
that Viterbi itself was not the first bottleneck.

## Usage And Overrides

`Obscura.Profile.prepare(:openmed_pii, ...)` now selects the measured defaults.
These values are the machine-checked `openmed_latency_v1` policy:

| Setting | Default |
| --- | --- |
| Policy ID | `openmed_latency_v1` |
| Sequence-length buckets | `[192, 256, 384, 512, 768]` |
| Activation threshold | `129` tokens |
| Decoder | `:viterbi` |
| Log-probability conversion | `:raw_logits` |

Callers can disable bucketing explicitly:

```elixir
Obscura.Profile.prepare(:openmed_pii,
  privacy_filter_checkpoint: checkpoint,
  sequence_length_buckets: nil
)
```

Callers can restore normalized log-probabilities explicitly:

```elixir
Obscura.Profile.prepare(:openmed_pii,
  privacy_filter_checkpoint: checkpoint,
  logprob_conversion: :reference
)
```

Configuring `privacy_filter_min_span_logprob` automatically retains the
reference conversion unless the caller supplies an incompatible override,
which returns a structured configuration error.

## Reproduction

Set the pinned local environment:

```sh
export OBSCURA_REAL_MODEL_BACKEND=emily
export OBSCURA_PRIVACY_FILTER_BACKEND=emily
export OBSCURA_EMILY_DEVICE=gpu
export OBSCURA_EMILY_FALLBACK=raise
export OBSCURA_PRIVACY_FILTER_CHECKPOINT=.cache/privacy-filter/openmed-nemotron-v2
```

Run one matrix cell:

```sh
mix obscura.openmed.optimize \
  --variant combined \
  --dataset nemotron_pii_test_subset_all \
  --repetition 1 \
  --sample-count 32 \
  --concurrency 4
```

The controlled aggregate is
`eval/reports/openmed-optimization/matrix-summary.json`. The 30-minute report
is under `eval/reports/openmed-optimization/soak/`.

## Remaining Work

1. Repeat the matrix and 30-minute confirmation on Linux/EXLA.
2. Run additional Apple repetitions if sub-2% short-text differences must be
   resolved statistically.
3. Improve the soak memory classifier or run a longer memory-focused protocol
   before making a bounded-memory claim.
4. Investigate a fused backend output/host-transfer API only if the expected
   maintenance cost is justified; raw logits show that transfer, not
   log-softmax arithmetic alone, now dominates that boundary.
