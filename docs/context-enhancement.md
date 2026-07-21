# Context Enhancement

Context enhancement raises recognizer scores when configured words appear near a detected span. It does not create detections by itself and it does not claim Presidio score compatibility.

The current implementation is Presidio-inspired: Obscura builds dependency-light NLP artifacts once for the input string, then context scoring uses token offsets and normalized tokens instead of only raw substring windows.

## Usage

```elixir
Obscura.analyze("Phone 202-555-0188",
  entities: [:phone],
  profile: :context,
  context: ["phone"],
  explain: true
)
```

When context matches, the result score is boosted and clamped to `1.0`. Explanations record:

- `original_score`
- `context_words`
- `score_context_delta`

## NLP Artifacts

`Obscura.NLP.Artifacts` exposes:

- `tokens`
- `token_offsets`
- `normalized_tokens`
- `lemmas`
- `keywords`

The default artifact builder is deterministic and dependency-free. Lemmas currently equal normalized tokens; the field exists so future optional NLP engines can provide stronger language-specific normalization without changing analyzer contracts.

## Token Matching Options

Analyzer options now include:

- `:context_prefix_count`, default `5`
- `:context_suffix_count`, default `5`
- `:context_match`, default `:whole_word`
- `:context_min_score`, default `0.4`

Whole-word matching compares normalized context terms against surrounding token terms. `context_match: :substring` remains available for compatibility, but whole-word matching is preferred because it avoids accidental boosts such as matching `one` inside `phone`.

Weak pattern recognizers can set `metadata.requires_context` through `Obscura.Recognizer.PatternDefinition`. Such results are dropped unless context enhancement records `metadata.context_matched == true`.

Model-backed recognizers can use the same gate. In the explicit
`:hybrid_ner_org` profile, organization predictions below the configured
context-gate score require nearby organization context such as employment or
company wording. This reduces noisy organization false positives while keeping
high-confidence organization spans available for the opt-in profile.

## Context Policies

Recognizer-level context policies run before global context enhancement. They
can attach context words, require context for low-score spans, lower weak
scores, or reject spans below a threshold.

Example:

```elixir
Obscura.analyze(text,
  entities: [:organization],
  profile: :hybrid_ner_org,
  context_policies: %{
    organization: %{
      context_words: ["company", "employer", "works at"],
      require_context_below: 0.95,
      min_score: 0.85
    }
  }
)
```

Policy keys can be an entity, a recognizer, or `{recognizer, entity}`. Supported policy fields are:

- `:context_words`
- `:min_score`
- `:require_context_below`
- `:lower_below`
- `:low_score_multiplier`
- `:reject_below`

The policy action is recorded in result metadata under `:context_policy` and
related threshold/delta keys. Policy rejection uses the existing
`requires_context` metadata path, so rejected spans are removed by the internal
context acceptance step.

## Built-In Context

Some built-ins include conservative context words in metadata, such as phone and credit-card terms. Callers can add request-specific context with the `:context` analyzer option.

## Fixture Contract

Context fixtures compare baseline and context-enhanced texts. They assert that:

- the context score is higher than the baseline score
- the score stays at or below `1.0`
- matched context words are recorded
- raw PII is not written to generated reports

Context is a scoring aid only. It is not NER, semantic classification, or a remote model call.
