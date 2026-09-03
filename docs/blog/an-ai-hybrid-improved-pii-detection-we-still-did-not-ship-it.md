# An AI Hybrid Improved PII Detection. We Still Did Not Ship It.

When Perplexity released
[PII-TRACE](https://www.perplexity.ai/hub/blog/pii-trace-detecting-personal-data-before-it-leaves-the-device)
and its
[PII masking model](https://huggingface.co/perplexity-ai/pplx-pii-masking), I paid
attention.

The release described a compact local model built for personal data in long,
multiturn conversations. That problem is close to Obscura's work at application
and LLM boundaries. I was excited enough to ask whether the model could become
a new Obscura backend, or perhaps improve the existing accurate profile as part
of a hybrid.

The first benchmark said no.

The hybrid experiment said maybe. A narrow policy improved exact span F1 on
all three evaluation sets.

Then incremental error analysis changed the answer again.

The useful gains did not show that Obscura needed a model. They exposed phone
and URL formats that deterministic recognizers could learn to handle. The best
decision was not to ship the hybrid. It was to use the model as a research tool
and improve the smaller boundary.

![The incremental analysis behind the decision not to add the Perplexity model
dependency](media/an-ai-hybrid-improved-pii-detection-we-still-did-not-ship-it/incremental-error-analysis-decision.png)

*The hybrid improved the aggregate score. The added spans explained whether
that improvement justified the dependency.*

Unless noted otherwise, Obscura results in this article refer to version
`0.1.3` and experiments completed on September 2, 2026. The full reports and
scripts are in the
[Perplexity evaluation directory](https://github.com/hfiguera/obscura/tree/main/eval/pplx_pii).

## The Result in One Minute

- The standalone Perplexity model did not beat Obscura's accurate profile
  under Obscura's typed, exact span contract.
- A contact only hybrid improved exact F1 on all three selected datasets by
  `0.0067` to `0.0090`.
- That hybrid added 163 spans. Only 87 were new exact matches: 69 phones and
  18 URLs. It added no exact emails.
- A deterministic URL probe recovered all 18 URL gains and found six more,
  with no new false positives in that experiment.
- Obscura's existing optional phone parser recovered 37 of the 69 phone gains,
  but also confused many identifiers for phone numbers on one dataset.
- The evaluated hybrid used the model's published Python runtime. We did not
  attempt a native Elixir port because the incremental gains did not justify
  that engineering work. Sequential latency was about 1.8 times base on two
  selections and 2.6 times base on the third.
- The model still showed useful semantic signal for people and locations, but
  not with the precision required for promotion.
- The justified next step is better deterministic URL and phone recognition,
  followed by evaluation on untouched data.

The central lesson is simple:

> Measure the capability a model uniquely contributes, not only the score of
> the system that contains it.

## Why the Release Looked Relevant

Perplexity's release is interesting for reasons beyond a leaderboard number.

PII-TRACE contains 13,148 synthetic conversations rather than isolated
snippets. The published benchmark covers 13 languages, 10 writing systems, and
more than 37,000 identifier mentions. Its evaluation asks whether a detector
finds the same recurring identity across turns. That is a real concern for
assistants and agents, where the same person can appear in user messages, tool
results, and model responses.

The released model is also practical enough to test. It is available under the
MIT license and uses a roughly 600 million parameter Qwen3 encoder, with a
token classification head for nine privacy categories and a second head for
conversation sensitivity. It supports a 4,096 token context and the reference
pipeline includes a constrained BIOES decoder.

Perplexity reports strong character level results across the detectors it
tested. It also highlights recurring identifier consistency, which ordinary
span benchmarks often ignore.

Those properties made the model a credible candidate. They did not make it an
automatic fit for Obscura.

## Keep the Contract Fixed

A model can perform well under one privacy contract and still be a poor
replacement under another.

Obscura's current benchmark evaluates eight entity types with exact byte
boundaries. A prediction is correct only when both the type and the complete
span match the annotation.

That strictness matters because Obscura supports reversible pseudonymization.
Given this input:

```text
Contact rachel.chen@example.test.
```

the library needs the exact email span. Missing the first character or
absorbing the final period creates the wrong vault mapping. Character overlap
can describe partial coverage, but it is not sufficient for safe replacement
and restoration.

The Perplexity model uses a different taxonomy and target. Its `account_number`
label does not distinguish credit cards from US Social Security numbers. It
does not have a direct IP address label. Its address, person, and location
semantics are narrower and more privacy focused than Obscura's current entity
policy.

I did not try to make either contract look like the other. The benchmark kept
Obscura's dataset bytes, sample order, entity policy, and scorer fixed. It also
reported character F1 so the model's broader coverage remained visible.

This is not a reproduction or rejection of Perplexity's PII-TRACE leaderboard.
It answers a narrower product question:

> Can this released model satisfy Obscura's current exact span contract well
> enough to justify becoming a dependency?

## Pin Before Comparing

The experiment pinned both model repositories:

- `perplexity-ai/pplx-pii-masking` at
  revision `1e6bb1edd41e`;
- `perplexity-ai/pplx-embed-v1-0.6b` at
  revision `2c4d510dd4a7`.

The adapter verifies hashes for model weights, tokenizer files,
configurations, and executable Python sources before inference. A clean cache
download completed successfully. CPU and Apple Metal produced the same output
fingerprint on a parity selection, and the model card example produced its
documented person, email, and phone spans. The
[evaluation report](https://github.com/hfiguera/obscura/blob/main/eval/pplx_pii/RESULTS.md)
records the full revisions and asset hashes.

This work is not administrative detail. A moving model revision or tokenizer
can make a comparison impossible to reproduce later.

## The Standalone Model Did Not Win

The first experiment ran the model by itself on the same ordered selections
used for Obscura's existing comparisons.

| Dataset | Samples | Perplexity typed F1 | Obscura `:accurate` F1 | Perplexity character F1 |
| --- | ---: | ---: | ---: | ---: |
| `generated_large/template_heldout` | 648 | `0.5253` | `0.8024` | `0.8827` |
| `synth_dataset_v2/all` | 1,500 | `0.5725` | `0.8423` | `0.8459` |
| `nemotron_pii_test_subset/all` | 500 | `0.6719` | `0.6973` | `0.8173` |

The character scores confirm that the model often covered private text. The
typed exact scores show that type mapping and span boundaries remained a
problem for Obscura's contract.

One example made the difference concrete. The model returned
`aniels@meridiancap.com` where the annotated value began with `d`. Most of the
email was covered, so a character metric remained generous. The resulting
pseudonym would still be wrong.

The standalone result ruled out a direct replacement. It did not rule out a
hybrid.

## The Hybrid Result Was Tempting

The hybrid kept Obscura authoritative. When both systems found overlapping
spans, Obscura won. The model could add only allowed, nonoverlapping spans.

A broad policy for people, email addresses, phone numbers, and URLs was not
stable enough. On top of `:accurate`, it improved two datasets and reduced F1
on the third.

A narrower contact policy looked better:

```elixir
allowed_additions = [:email, :phone, :url]
overlap_policy = :prefer_obscura
```

| Dataset | Base F1 | Contact hybrid F1 | Change | Added spans |
| --- | ---: | ---: | ---: | ---: |
| `generated_large/template_heldout` | `0.8024` | `0.8113` | `+0.0090` | 45 |
| `synth_dataset_v2/all` | `0.8423` | `0.8512` | `+0.0089` | 77 |
| `nemotron_pii_test_subset/all` | `0.6973` | `0.7040` | `+0.0067` | 41 |

This was the best observed exact F1 on all three selections.

It was also exploratory. I found the contact policy while comparing policies
on those evaluation sets. Promoting it as a new champion would reuse the test
sets for selection. At minimum, the policy needed to be frozen and tested once
on new untouched data.

Before creating that data, a more important analysis remained.

## What Did the Model Actually Add?

The contact hybrid accepted 163 Perplexity spans that did not overlap an
Obscura prediction.

Their outcomes were:

| Outcome | Count |
| --- | ---: |
| New exact phone matches | 69 |
| New exact URL matches | 18 |
| New exact email matches | 0 |
| Boundary mismatches | 3 |
| Wrong entity types | 26 |
| False positives | 47 |

The aggregate gain came from 87 exact additions. Every one was a structured
contact format.

The errors were also systematic. On Nemotron, the model classified 15 MAC
addresses, three IP addresses, and two secrets as URLs. A phone prediction
covered a credit card. Other invalid phone candidates included short words and
punctuation.

A basic shape gate removed all 47 added false positives in this experiment and
raised F1 further. That did not make the model necessary. It showed that the
useful candidates had ordinary structured shapes that could be investigated
directly.

## The Phone Gains Were Real, but Structured

The 69 exact phone additions contained seven to twelve digits. They used
conventional spaces, dots, parentheses, or international prefixes.

Obscura already has an optional path based on
[`ex_phone_number`](https://hexdocs.pm/ex_phone_number/0.4.11/), an Elixir
library for parsing and validating international phone numbers. Run
independently, it recovered 37 of the 69 additions. That was useful evidence
that over half of the model's new phone matches did not require model
semantics.

The parser was not ready to enable broadly:

| Dataset | Base F1 | F1 with optional phone parser |
| --- | ---: | ---: |
| `generated_large/template_heldout` | `0.8024` | `0.8141` |
| `synth_dataset_v2/all` | `0.8423` | `0.8489` |
| `nemotron_pii_test_subset/all` | `0.6973` | `0.6537` |

On Nemotron it added 189 phone predictions over values that were not phones,
mostly generic IDs, patient IDs, Social Security numbers, and credit cards.

That failure is useful. The next phone recognizer should not simply accept more
digit layouts. It needs strict context and negative checks for competing
identifier types.

## The URL Result Was Clearer

All 18 exact URL additions shared a narrow pattern:

- 13 used HTTPS;
- five used FTP;
- 17 were followed by punctuation.

An independent deterministic probe added FTP support and normalized trailing
sentence punctuation. It recovered all 18 URLs found by Perplexity. It also
found six more exact URLs that the model missed.

On the Nemotron selection, the probe added 24 exact URLs with no new false
positives and moved aggregate F1 from `0.6973` to `0.7101`.

This is not yet a shipped recognizer change. It still needs focused tests and
an untouched validation set. But it is a much stronger product direction than
adding a model to recover the same formats.

## The Model Still Found Semantic Signal

The contact analysis does not prove that the model lacks semantic capability.
It only explains the policy that improved the aggregate score.

A separate broad diagnostic found 69 exact person spans and 149 exact location
spans that `:accurate` missed. Those gains came with 291 nonexact person
additions and 773 nonexact location additions.

That result matters. The model sees some private context that deterministic
recognizers will not reproduce easily. It may fit a future recall focused or
conversation focused profile with a different contract.

It did not support promotion into the current accurate profile. The precision
cost was too high, and the policies that admitted those categories did not
produce a consistent champion.

## Runtime Cost Belongs in the Decision

The evaluated contact hybrid used the published Python path, with Torch,
Transformers, a roughly 600 million parameter model, pinned assets, and a
process boundary from Elixir. We did not attempt a native Elixir port because
the incremental analysis did not show enough unique model value to justify the
integration and validation work.

Under the sequential experimental runner, mean latency changed as follows:

| Dataset | Base mean | Hybrid mean |
| --- | ---: | ---: |
| `generated_large/template_heldout` | `33.44 ms` | `62.05 ms` |
| `synth_dataset_v2/all` | `38.33 ms` | `68.06 ms` |
| `nemotron_pii_test_subset/all` | `41.84 ms` | `108.88 ms` |

These numbers describe the experimental machine. They are not a universal
runtime comparison, and the standalone rows used different execution devices.

The important point is not that Python or models are inherently too costly.
It is that a dependency must earn its operational surface. A small score gain
is not enough when the same contribution may be available through a cheaper,
more precise recognizer.

This is the same boundary question explored in
[Should PII Detection Live Inside the BEAM?](should-pii-detection-live-inside-the-beam.md).
Deployment, latency, and detection quality are separate decisions.

## What PII-TRACE Can Improve in Obscura

Rejecting this model as a current backend does not mean the release taught us
nothing. Its strongest ideas are in evaluation.

Obscura should add:

1. Multiturn fixtures with user, assistant, tool, and agent messages.
2. Cluster IDs that measure recurring identity detection across turns.
3. A dedicated false positive rate over conversations with no private data.
4. Results grouped by input length, with truncation and chunking made explicit.
5. Mixed language and mixed format conversations in the release matrix.
6. Tests for consistency before and after tool calls.
7. An evaluation of overlapping windows for long input, including their
   precision cost.

These ideas complement Obscura's existing vault behavior. Stable pseudonyms
preserve identity after detection, but a recurring mention that is missed can
still cross the boundary raw.

The model can also remain useful as a research oracle. It can scan evaluation
data for patterns that current recognizers miss, then help turn repeated,
well understood formats into deterministic fixtures and rules.

## What We Decided

The current evidence supports four decisions.

First, do not replace `:accurate` with the standalone model.

Second, do not promote the contact hybrid. Its gain is exploratory, its runtime
cost is meaningful, and its exact additions do not yet demonstrate a need for
a model.

Third, improve URL handling first. Trailing punctuation and FTP support have a
clear deterministic path.

Fourth, investigate phone formats with strict negative checks. The broad phone
parser result shows exactly what can go wrong when recall is added without
enough type discrimination.

After those changes, evaluate once on a new untouched selection. Only then can
the profile comparison support a new champion claim.

## What This Does Not Prove

This work has important limits:

- The three selections are synthetic or derived from synthetic data.
- They use Obscura's eight entity contract, not the full PII-TRACE contract.
- The contact policy was selected on the same data used to report it.
- The deterministic URL probe is analysis code, not a production recognizer.
- The latency rows are descriptive and do not compare identical devices or
  deployment designs.
- The experiment does not evaluate every language, long conversation, or
  recurring identity behavior advertised by PII-TRACE.
- A different application may value recall enough to accept the model's cost
  and taxonomy.

The conclusion is about Obscura's current product boundary. It is not a general
claim that models are unnecessary for PII detection.

## Conclusion

The Perplexity release deserved a serious test. The standalone model showed
strong character coverage. A narrow hybrid improved every aggregate exact F1
score. Stopping there would have produced an attractive announcement.

The incremental analysis produced a better result.

It showed that the winning policy added only phone numbers and URLs, that an
existing parser could recover many of the phones, and that a simple URL probe
could recover every URL plus six more. It also showed where deterministic
phone expansion would create dangerous type confusion.

The model did not become Obscura's new champion. It became a useful instrument
for finding the next recognizer work.

That is not a disappointing benchmark outcome. It is what evaluation is for.

> A higher score tells us that a system changed. Incremental error analysis
> tells us whether the new dependency earned its place.

The complete standalone, hybrid, and incremental reports are available in
[`eval/pplx_pii`](https://github.com/hfiguera/obscura/tree/main/eval/pplx_pii).
