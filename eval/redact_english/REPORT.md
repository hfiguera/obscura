# Redact: retain as an external reference

Evaluated 13–14 September 2026. Redact has useful English address detection and
small model assets, but the measured benefits do not justify integration into
Obscura now. Keep this pinned version as an external comparison. Do not introduce
a profile or replace `:efficient` or `:balanced` on this evidence.

## What it adds

On the fresh synthetic English test, the complete Linux Redact pipeline achieved
**0.8587 exact typed-span F1**, compared with **0.8117 efficient**, **0.8267 balanced**
and **0.5309 fast**. It fully covered the identifying letters/digits in **177 of
195 primary gold spans**, versus 159 for efficient and 158 for balanced.
Full postal addresses are its clearest advantage: location F1 was 0.9524.
Balanced still detected more exact person spans (71 versus Redact's 67).

This is a small assistant-authored corpus with 44 primary test families, not an
independent sample of production traffic. Family resampling spans both positive
and negative F1 differences. The observed aggregate lead does not establish a
general winner. All 27 negative rows stayed unchanged, but they represent only
nine families. See [ACCURACY.md](ACCURACY.md) for precision, recall, per-entity
results, exposure, examples and unsupported entities.

## CPU and memory tradeoff

Matched external-worker workload on the physical Linux i5-1135G7, one worker:

| Pipeline | Requests/s | p95 round trip | Peak RSS |
| --- | ---: | ---: | ---: |
| fast | 912.75 | 3.02 ms | 90.4 MiB |
| efficient | 159.11 | 18.77 ms | 145.1 MiB |
| balanced | 0.94 | 1,529.27 ms | 2,083.9 MiB |
| Redact CPU | 17.89 | 97.66 ms | 186.7 MiB |

Redact was approximately 19 times faster than balanced and used about 91% less
peak RSS. Efficient was approximately nine times faster than Redact and used
less memory. At four workers, Redact reached 29.41 requests/s, efficient 355.43
and balanced 1.08. Redact scaled weakly beyond two workers in this run.

All 32 configurations ran at least five minutes, with equal input mixtures,
burst tests and deliberate worker replacement. Request error counters were zero;
recovery returned each pipeline to its original canary result. Mac CPU Redact's
canary remained defective, so its rates are excluded from successful NER claims.
The valid baselines' RSS decreased over the sampled intervals; Linux Redact's
did too. Mac CPU Redact increased by 4.5–14.9 MiB across configurations, but its
neural results were invalid. These observations do not establish leak freedom.

Startup is a fresh process with cached assets, followed by first-request and warm
timings. Each worker has its own language runtime. Background load, fixed run
order and one run per configuration limit causal performance comparisons. This
is not a reboot/cache-purged benchmark or a production endurance certification.
See [WORKLOAD_RESULTS.md](WORKLOAD_RESULTS.md) for all timings, memory, saturation,
recovery and hardware details.

## Why integration should wait

1. **Mac CPU neural inference fails.** With the supported CPU-only setting,
   all 22,784 logits per observed window were nonfinite. The SDK still returned
   emails without an error. The failure appears in native Core ML output before
   SDK tensor conversion and reproduces with the actual SDK release source.
   The precise failing model export/runtime operation remains unresolved.
2. **Longer context can expose names and cities.** Linux CPU and Mac default
   returned finite all-`O` predictions in repetitive passages despite correct
   tokenization and overlapping-window execution. In the separate frozen long
   test subset, Redact fully exposed nine of 48 spans; efficient exposed four
   completely and three partially. Sentence splitting fixes the specific
   repetitive probes on working backends, but is only a diagnostic workaround.
3. **Coverage has regressions.** Redact missed the tested IPv6 addresses and
   excluded the opening parenthesis of phone spans. The latter fails exact
   scoring while still covering the digits. Date/time and bare domains lack
   direct labels; organization is disabled by default. Do not conflate these
   different failures or extrapolate to untested formats.
4. **Local execution does not satisfy the offline contract.** The publisher's
   source-available license requires usage telemetry and restricts standalone
   SDK/model distribution. Attribution, downstream library distribution,
   disconnected deployment and device accounting need clarification. No vendor
   contact or telemetry modification was made. See [LICENSING.md](LICENSING.md).

## Installation and a possible future adapter

Redact's platform inference assets are **11.47 MiB on Mac and 23.77 MiB on Linux**,
versus efficient's 407.83 MiB of model files. The tested npm tree is 193.71 MiB;
including installed Node and platform assets gives roughly **425–431 MiB**.
These are installed file groups, not minimal release or compressed image sizes.
The model's small size does not translate directly into the same reduction in
application installation. See [FOOTPRINT.md](FOOTPRINT.md).

If the correctness and contract issues are resolved in a later release, a bounded
external worker would fit Obscura's existing Port architecture and preserve its
vault and replacement policies. Node is the measured entry point; a dedicated
Swift or C ABI wrapper could alter packaging costs, but has not been measured.
Rustler does not fix the model or license issues. See [INTEGRATION.md](INTEGRATION.md).

Reconsider integration only after the Mac CPU failure is corrected or an explicit
supported-platform policy is chosen, longer-input behavior improves, distribution
and disconnected-operation terms are clarified, and gains persist on broader
untouched English application data. Multilingual value is outside this decision.

The branch `eval/redact-english` contains evaluation artifacts only, based on
main `46428566`. No training, public profile changes, publication, push or PR
is part of this work. [COMPLETION.md](COMPLETION.md) maps the objective to evidence.
