# Perplexity PII Candidate Results

Evaluation date: 2026-09-02

## Decision

`perplexity-ai/pplx-pii-masking` is **not a new Obscura champion** under the
current eight-entity, typed exact-span protocol.

It remains a useful research candidate for a separate privacy-context profile
or a recall-oriented hybrid. That would be a new contract, not a replacement
for `:balanced` or `:accurate`.

## Pinned Assets

- Masking model: `perplexity-ai/pplx-pii-masking` at
  `1e6bb1edd41e03668c6931122be96df893141965`
- Backbone: `perplexity-ai/pplx-embed-v1-0.6b` at
  `2c4d510dd4a732063c31a0f70193e35067b51fd8`
- License: MIT
- Runtime: Python 3.11.15, Torch 2.12.1, Transformers 5.11.0, Apple Metal
- Decoder: the model repository's constrained BIOES Viterbi implementation
- Nemotron source: `nvidia/Nemotron-PII` at
  `b70ffaf5ff39e079776134c5bf4381f00a9fd1ed`

The adapter verifies the SHA-256 of the model weights, backbone weights,
tokenizer, configurations, and executable Python sources before inference.

## Full Results

| Dataset | Samples | Typed P | Typed R | Typed F1 | Untyped exact F1 | Character F1 | Mean ms | P95 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `generated_large/template_heldout` | 648 | 0.4826 | 0.5763 | 0.5253 | 0.3566 | 0.8827 | 34.84 | 55.07 |
| `synth_dataset_v2/all` | 1,500 | 0.5407 | 0.6084 | 0.5725 | 0.4914 | 0.8459 | 34.87 | 55.49 |
| `nemotron_pii_test_subset/all` | 500 | 0.7969 | 0.5808 | 0.6719 | 0.6854 | 0.8173 | 76.41 | 139.72 |

Current `:accurate` typed exact F1 is `0.8024`, `0.8423`, and `0.6973` on the
same ordered selections. The Perplexity model trails by `0.2771`, `0.2698`,
and `0.0254` respectively.

Accuracy is comparable because dataset bytes, sample order, entity policy,
and scoring fingerprints match the authoritative selections. Latency is
descriptive only and is not promoted operational evidence.

## Interpretation

The character metric confirms that the model often covers private text. It
does not establish compatibility with reversible pseudonymization, which
needs exact boundaries and a stable entity type.

The taxonomy is intentionally privacy-oriented:

- `account_number` does not distinguish credit cards from US Social Security
  numbers.
- no model label maps directly to Obscura's IP address contract.
- `private_address` is narrower than a general location entity.
- public people, organizations, and ordinary public locations are outside the
  model's stated target.

A perfect label remap would not close the gap. Label-agnostic exact F1 is only
`0.3566` and `0.4914` on the two Presidio-Research selections, so span
boundaries and target semantics also differ.

Structured refinement alone cannot rescue the overall promotion case. Even
granting perfect recovery of every missed credit card, IP address, and US
Social Security number in `synth_dataset_v2`, with no additional false
positives, would raise the candidate to only about `0.659` typed F1. Current
`:accurate` reaches `0.8423` there.

The strongest strict typed results appear on Nemotron email (`0.9913` F1),
phone (`0.9730`), and URL (`0.7837`). Person and location are weaker, and the
broad account label needs deterministic refinement before it can satisfy
Obscura's contract.

## Verification

- The model's published README example produced the documented person, email,
  and phone spans.
- CPU and Metal produced the same output fingerprint over a 20-sample parity
  selection.
- Published and `fix_mistral_regex=True` tokenizers produced the same output
  fingerprint over 100 selected samples.
- The documented clean-cache download path completed and all pinned hashes
  passed.
- Reports omit raw source text and detected values.

One wording variant exposed a real exact-boundary error: the model returned
`aniels@meridiancap.com` instead of `daniels@meridiancap.com`. This is one
example, not an aggregate claim, but it illustrates why character coverage
cannot replace exact-span evaluation.

## Ideas To Bring Into Obscura

The strongest contribution from
[PII-Trace](https://www.perplexity.ai/hub/blog/pii-trace-detecting-personal-data-before-it-leaves-the-device)
is its evaluation design rather than this model as a drop-in backend.

1. Add multi-turn conversation fixtures that include user, assistant, tool,
   and agent messages.
2. Assign entity cluster IDs across turns and report recurring detection
   consistency, including mixed-language mentions of the same identity.
3. Add a dedicated PII-free false-positive rate with public figures,
   documentation examples, ordinary URLs, and public locations.
4. Report performance by input length and make truncation, chunking, and
   overlapping-window policy explicit.
5. Test 50% overlapping windows for long inputs and measure the precision cost
   rather than assuming chunking is neutral.
6. Add mixed-language and mixed-format conversations to the release matrix.
7. Evaluate an optional conversation sensitivity signal for routing or review,
   but never use it as a substitute for span detection.
8. Measure consistency before and after tool calls. Obscura's vault preserves
   stable pseudonyms after detection, but a missed recurring mention can still
   cross the boundary raw.

The model's own sensitivity head is not calibrated for Obscura's current
single-document corpora: very few selected samples crossed `0.5` despite
containing annotated PII. It needs conversation-level validation before any
product use.

## Next Candidate Path

The defensible follow-up is an experimental hybrid, not promotion:

1. Keep deterministic recognizers authoritative for email, phone, card, SSN,
   IP, and other structured entities.
2. Use the model only for privacy-context categories that add recall.
3. Refine `account_number` locally before assigning an Obscura entity.
4. Normalize model boundaries, then evaluate on a train selection before one
   untouched heldout run.
5. Require improvement on all three authoritative datasets and add the new
   conversation consistency suite before considering a stable profile.

The model card and reference implementation are available from the
[pplx-pii-masking repository](https://huggingface.co/perplexity-ai/pplx-pii-masking).
