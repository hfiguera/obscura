# Efficient plus Redact address experiment

The live hybrid improves address coverage on this fresh Linux test. It is a useful research result, but does not justify a public integration yet. Mac CPU remains defective, and the full Redact runtime and licensing requirements still apply.

## Fresh English test

48 new synthetic texts, 59 gold PII spans, 14 negative texts. Of 26 location spans, 23 are full addresses; this deliberately emphasizes the proposed benefit. The test uses 12 address values and eight person names across different templates. Eight long texts reuse neutral context. This is not 48 independent samples of production traffic, and it does not estimate general English accuracy. The previous post-hoc 0.9019 F1 used a different, already inspected corpus and is not comparable to these absolute scores.

| Linux pipeline | Precision | Recall | Exact F1 | Fully covered | Partly exposed | Fully exposed | Negative texts changed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fast | 0.9231 | 0.2034 | 0.3333 | 13/59 | 0 | 46 | 0/14 |
| efficient | 0.4583 | 0.5593 | 0.5038 | 36/59 | 19 | 4 | 0/14 |
| redact_cpu | 0.6308 | 0.6949 | 0.6613 | 47/59 | 8 | 4 | 1/14 |
| hybrid | 0.7164 | 0.8136 | 0.7619 | 51/59 | 7 | 1 | 0/14 |

The hybrid retains efficient person F1 (0.8780) and exact email/phone/IP results, while location F1 rises from 0.0909 to 0.5902. Location false positives fall from 37 to 17 because many previous fragments become correct complete addresses. These are span-scoring false positives, not necessarily unrelated words incorrectly masked. Coverage counts letters/digits using original detections; it does not count inferred gaps as masked.

On Mac CPU, efficient F1 is 0.5038 and hybrid F1 is 0.4521. Hybrid fully covered counts rise from 36 to 39, but false positives rise from 39 to 54. Those changes do not make the known invalid neural output useful or safe. No default-accelerated Mac results are called CPU evidence.

## Matched operational follow-up

Each configuration ran 60 seconds with complete cycles over the same six short development inputs. Workers are reused; assets are cached. There are one and four logical workers. Each hybrid worker owns an efficient Elixir worker/native child and a Redact Node/native worker. The Python compositor invokes them sequentially. Measured latency includes both calls and merging; memory sums their child process trees, excluding the driver/compositor. PSS apportions shared pages on Linux. Background activity and one short run per configuration limit causal comparisons; these are not additional five-minute endurance tests.

| Host | Pipeline | Workers | Requests/s | p95 ms | Peak RSS MiB | RSS change MiB | Peak PSS MiB | Startup mean ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| macos | efficient | 1 | 1992.79 | 0.64 | 175.5 | -29.0 | — | 613.4 |
| macos | redact_cpu (invalid Redact CPU) | 1 | 238.67 | 4.58 | 97.5 | +0.9 | — | 53.5 |
| macos | hybrid (invalid Redact CPU) | 1 | 205.78 | 5.35 | 274.0 | -28.9 | — | 671.8 |
| macos | efficient | 4 | 6272.94 | 0.79 | 693.6 | -104.8 | — | 652.8 |
| macos | redact_cpu (invalid Redact CPU) | 4 | 658.48 | 6.77 | 386.2 | +0.1 | — | 53.1 |
| macos | hybrid (invalid Redact CPU) | 4 | 529.19 | 8.72 | 1078.7 | -117.9 | — | 743.4 |
| linux | efficient | 1 | 518.83 | 2.62 | 144.4 | -27.1 | 120.8 | 1839.8 |
| linux | redact_cpu | 1 | 22.92 | 49.55 | 185.6 | +10.5 | 177.7 | 352.7 |
| linux | hybrid | 1 | 21.67 | 52.34 | 312.5 | -11.8 | 281.0 | 3078.6 |
| linux | efficient | 4 | 1053.90 | 5.55 | 543.3 | -69.9 | 418.7 | 1884.2 |
| linux | redact_cpu | 4 | 43.88 | 141.37 | 743.7 | +38.6 | 476.3 | 524.9 |
| linux | hybrid | 4 | 33.61 | 202.47 | 1224.9 | -24.4 | 840.2 | 2788.0 |

All twelve runs completed without reported request errors, all bursts completed, and deliberate underlying-worker failure was observable. Replacing that worker restored the original predictions; surviving pipelines remained consistent. This is evaluator-managed recovery, not a new Elixir supervisor. Mac recovery restores the defective behavior too. Sampled memory growth does not establish leak freedom.

## Failure cases and decision

The hybrid fixes complete-address boundaries in test-00 (US street), test-01 (UK street), test-02 (apartment), test-06 (suite), test-08 (multiline) and other cases. It still partly exposes addresses in test-03/test-15 (Canadian street variants), test-05/test-17 (PO boxes), and several long contexts. Test-11 covers identifying characters but still misses the exact annotated full boundary. The single completely exposed hybrid span is a person, which address enrichment cannot repair. These examples were inspected after scoring; the rule was not tuned in response.

Always invoking Redact makes efficient pay the second inference and resident-runtime cost. Address-label selection occurs after full detection in the official SDK; it does not yield a small address-only model. An explicitly identified address field could support an optional call, but automatic routing based on clues could miss addresses. Neither routing nor sentence splitting is included or validated here.

Recommendation: keep address enrichment as an experimental direction, with this implementation as evidence. Do not promote this Redact dependency now: Mac CPU correctness and the distribution/offline terms remain unresolved. See [the original license review](../LICENSING.md) and [integration assessment](../INTEGRATION.md). No profile/default changes, training, vendor contact, push or publication were made.

See [POLICY.md](POLICY.md), [README.md](README.md), [manifest.json](manifest.json), and [results/analysis.json](results/analysis.json) for the frozen rule, reproduction and full measurements.
