# Recognizers

Recognizers return `%Obscura.Analyzer.Result{}` values with byte offsets.
Built-ins stay dependency-light, while controlled extension points support
project-specific identifiers.

## Built-In Recognizers

The registry supports:

- `:email`
- `:phone`
- `:credit_card`
- `:us_ssn`
- `:iban`
- `:ip_address`
- `:url`
- `:domain`

Built-ins remain regex and validator based. Optional NER uses explicit
recognizer configuration and is not enabled by default.

The `:deterministic_plus` evaluation profile adds conservative recognizers for generated-template quality coverage:

- Presidio-style date formats, including ISO timestamps, timezone timestamps, slash/dash/dot dates, and abbreviated month dates.
- Explicit address contexts such as contact blocks, return-address requests, restaurant-address sentences, and moved/lived-at address prompts.
- High-confidence person and location contexts where the surrounding words make boundaries clear.
- URL/domain duplicate handling for generated "posted photo" text, while still preserving explicit URL detection when callers request `entities: [:url]`.

These additions are intentionally narrow. They improve supported Presidio-Research compatibility without making broad arbitrary name, organization, location, or free-form address regexes the default strategy.

## Optional Phone Parser

The default phone recognizer remains dependency-light. For stronger international validation, callers can opt into `ex_phone_number` through the parser adapter:

```elixir
Obscura.analyze(text,
  entities: [:phone],
  phone_parser: Obscura.Recognizer.Phone.ExPhoneNumberValidator
)
```

The dependency is optional:

```elixir
{:ex_phone_number, "~> 0.4.11", optional: true}
```

Parser-backed candidate scanning is enabled only when `:phone_parser` or `:phone_validator` is configured. Without that option, the existing deterministic phone recognizer path is unchanged.

Promoted heldout evidence shows the tradeoff:

- phone recall improves from deterministic `0.6239` to filtered parser `0.8624`
- phone F1 improves from `0.7684` to `0.8744`
- phone false positives increase from `0` to `12`
- overall deterministic-plus F1 improves from `0.6631` to `0.6721`
- compared with the earlier parser policy, phone false positives drop from
  `39` to `12`

This is why the parser remains opt-in. It is useful for recall-focused or international-phone workflows, but the conservative default avoids the extra false positives.

Benchmark CLI:

```sh
mix obscura.eval --compatibility --dataset generated_large \
  --profile deterministic_plus \
  --full \
  --template-split template_heldout \
  --phone-parser ex_phone_number
```

Optional parser settings:

- `:phone_regions`: region list for national numbers, defaulting to `US`, `GB`, `DE`, `FR`, `IL`, `IN`, `CA`, `BR`, `JP`, and `CN`.
- Plus-prefixed numbers are parsed without a default region.
- Parser candidates are post-filtered with Presidio-like evidence rules: plus-prefixed numbers, extension-bearing numbers, or national numbers with phone context are accepted; date-like, repeated digit, sequential digit, too-short, and junk candidates are rejected.
- Parser metadata records `:validation`, `:phone_region`, `:phone_e164`, and
  `:phone_number_type`. `:phone_e164` is normalized PII and remains available
  when `include_text: false`; that option suppresses `Result.text`, not
  documented recognizer metadata.

## NER Recognizer

`Obscura.Recognizer.NER` supports open-class entities with caller-provided serving:

```elixir
serving =
  Obscura.Recognizer.NER.FakeServing.new(%{
    "Alice works at Acme." => [
      %{label: "PER", start: 0, end: 5, score: 0.94},
      %{label: "ORG", start: 15, end: 19, score: 0.91}
    ]
  })

Obscura.analyze("Alice works at Acme.",
  entities: [:person, :organization],
  recognizers: [{Obscura.Recognizer.NER, serving: serving}]
)
```

See `docs/model-backed-recognition.md` for label mapping, fake serving, optional analyzer-level NLP engines, Bumblebee/Nx serving hooks, and batch analysis.

## Custom Modules

A custom recognizer implements `Obscura.Recognizer`. The analyzer passes NLP artifacts in `opts[:nlp_artifacts]`, so custom recognizers can use token offsets, normalized tokens, and optional engine-populated model outputs without rebuilding tokenization or invoking model serving independently:

```elixir
defmodule TicketRecognizer do
  @behaviour Obscura.Recognizer

  alias Obscura.Analyzer.Result

  def name, do: :ticket
  def supported_entities, do: [:ticket]

  def analyze(text, opts) do
    artifacts = Keyword.fetch!(opts, :nlp_artifacts)

    for [{start, length}] <- Regex.scan(~r/TKT-\d{4}/, text, return: :index) do
      value = binary_part(text, start, length)

      %Result{
        entity: :ticket,
        start: start,
        end: start + length,
        byte_start: start,
        byte_end: start + length,
        score: 0.8,
        text: value,
        source_entity: "TICKET",
        recognizer: :ticket,
        metadata: %{token_count: length(artifacts.tokens)}
      }
    end
  end
end
```

Use it with analyzer options:

```elixir
Obscura.analyze("Ticket TKT-1234",
  entities: [:ticket],
  recognizers: [TicketRecognizer]
)
```

Returned fields must satisfy `Obscura.Analyzer.Result.t()`. In particular,
`recognizer` must be an atom or `nil`, `source_entity` must be a binary or
`nil`, and `explanation` must be a valid
`Obscura.Analyzer.Explanation`. Metadata may contain recursively transparent
Elixir values, but functions, improper terms, and excessive nesting are
rejected with a sanitized `:invalid_callback_result` error. Accepted binary
metadata is detached when it would otherwise retain an unrelated larger source
binary.

## Inline Patterns

Use `Obscura.Recognizer.PatternDefinition` for project-local regexes without creating a module:

```elixir
employee_id =
  Obscura.Recognizer.PatternDefinition.new!(
    name: :employee_id,
    entity: :employee_id,
    patterns: [%{name: :employee_id_v1, regex: ~r/EMP-\d{6}/, score: 0.65}],
    context: ["employee"]
  )

Obscura.analyze("employee EMP-123456",
  entities: [:employee_id],
  recognizers: [employee_id],
  context: ["employee"],
  explain: true
)
```

Pattern definitions must use compiled regexes and explicit atom entities. Do not create atoms from external user data.

## Pattern Validation And Invalidation

`Obscura.Recognizer.PatternDefinition` supports Presidio-inspired validation hooks:

- `validate` can accept a match with `true`, `:ok`, `:valid`, `{:ok, metadata}`, `{:score, score}`, or `{:ok, score, metadata}`.
- `validate` can reject a match with `false`, `:invalid`, or unsupported return values.
- `invalidate` can reject a match with `true`, `:invalid`, `{:invalid, metadata}`, or `{:error, reason}`.
- A pattern can set `invalid_score` to keep an invalid low-confidence result instead of dropping it.

Pattern maps may also include:

- `requires_context: true`
- `context_min_score: 0.55`
- `weak: true`

Context-required results are emitted as candidates but dropped after context enhancement unless a nearby context word matched. This supports weak patterns such as ZIP-like numbers without treating every five-digit number as PII.

## Conflict Resolution

Analyzer conflict resolution is now closer to Presidio's duplicate/contained-span behavior:

- exact duplicate spans are removed
- contained lower-score same-entity spans are removed
- nested different-entity spans are preserved by default
- `:aggressive` or `:prefer_longer` keeps the earlier behavior of dropping any overlap
- `:prefer_higher_confidence` keeps the highest-confidence non-overlapping candidates

The anonymizer still defaults to aggressive overlap removal because replacement operations cannot safely apply overlapping spans without corrupting output offsets.

## Deny Lists

Deny lists turn configured values into recognizer results:

```elixir
Obscura.analyze("Project ORCHID",
  entities: [:project_codename],
  deny_lists: [
    %{entity: :project_codename, values: ["orchid"], case_sensitive: false}
  ]
)
```

Deny lists are intended for known secrets, project codenames, tenant-specific identifiers, or values supplied by application configuration.

## Allow Lists

Allow lists remove known-safe values after recognition:

```elixir
Obscura.analyze("support@example.com jane@example.com",
  entities: [:email],
  allow_list: [%{entity: :email, values: ["support@example.com"]}]
)
```

Allow list entries may contain literal values or patterns, scoped by entity when needed.
