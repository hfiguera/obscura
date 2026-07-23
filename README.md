# Obscura

Obscura is a library-first PII detection and anonymization toolkit for Elixir.
It analyzes plain text and nested Elixir data before sensitive values cross
application boundaries such as logs, external APIs, and LLM providers.

The dependency-light core recognizes common deterministic identifiers:

- email
- phone
- credit card
- US SSN
- IBAN
- IP address
- URL
- domain

Optional local model profiles add person, location, and organization
recognition. Obscura does not require a hosted recognition service.

## Installation

Add Obscura to an Elixir project:

```elixir
def deps do
  [
    {:obscura, "~> 0.1.0"}
  ]
end
```

The base installation supports the `:fast` profile without model assets or
accelerator dependencies. See the
[optional dependencies and assets guide](docs/optional-dependencies-and-assets.md)
before enabling a model-backed profile.

## Analyze

```elixir
{:ok, results} = Obscura.analyze("Contact jane@example.com", entities: [:email])

[%Obscura.Analyzer.Result{entity: :email, start: 8, end: 24}] = results
```

Offsets are byte offsets. This is intentional because Elixir binaries are byte
indexed and anonymization uses binary slicing.

## Anonymize

Analyze once, then apply an operator to each detected entity:

```elixir
text = "Contact jane@example.com"
{:ok, detections} = Obscura.analyze(text, entities: [:email])

{:ok, result} =
  Obscura.anonymize(text, detections,
    operators: %{email: %{type: :replace, value: "[EMAIL]"}}
  )

result.text
#=> "Contact [EMAIL]"
```

Supported operators are:

- `:replace` - `%{type: :replace, value: "[REDACTED]"}`
- `:redact` - `%{type: :redact}`
- `:mask` - `%{type: :mask, char: "*", keep_last: 4}`
- `:hash` - secure random-salt or explicit deterministic hashing
- `:pseudonymize` - reversible vault-backed tokenization
- `:custom` - application module implementing `Obscura.Operator.Custom`

Operator configurations are validated before any replacement is applied.
Unknown operators, malformed options, callback failures, and missing vaults
return a value-safe `%Obscura.Anonymizer.Error{}`. See the
[operator guide](docs/operators.md) for complete schemas and hash migration
guidance.

## Redact

`Obscura.redact/2` combines detection and anonymization:

```elixir
{:ok, result} = Obscura.redact("Call 202-555-0188", entities: [:phone])

result.text
#=> "Call [PHONE]"
```

Nested maps, lists, tuples, and supported structs can be processed without
flattening them into text. Structured inputs return
`%Obscura.Structured.Result{}`:

```elixir
input = %{email: "jane@example.com", password: "secret"}

{:ok, result} =
  Obscura.redact(input,
    entities: [:email],
    field_policies: %{password: :drop}
  )

result.data
#=> %{email: "[EMAIL]"}
```

See [structured redaction](docs/structured-redaction.md) for traversal,
field-policy, and struct behavior.

## Product Profiles

Obscura exposes three stable user-facing profiles:

| Profile | Intended use | Runtime requirements |
| --- | --- | --- |
| `:fast` | Common deterministic identifiers and context-labeled PII | Dependency-light BEAM execution |
| `:balanced` | General text needing person, location, and organization recognition | One local TNER model |
| `:accurate` | Highest measured general accuracy with conditional location recovery | Two local NER models |

Use `:fast` when structured identifiers are sufficient:

```elixir
Obscura.analyze("Contact jane@example.com", profile: :fast)
```

`:balanced` is the practical model-backed recommendation when its external
asset terms are acceptable for the deployment. `:accurate` has the highest
measured general accuracy, but its second model increases preparation, memory,
and inference cost. Dataset-specific results and limitations are in the
[benchmark status](docs/benchmark-status.md).

Model profiles require explicit reusable runtime preparation. Ordinary calls
never download models:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:balanced,
    allow_download: true,
    real_model_backend: :emily,
    emily_fallback: :raise,
    compile: [batch_size: 1, sequence_length: 128]
  )

Obscura.analyze("Rachel works at Google in Paris.", profile: runtime)
```

The first online preparation must pass `allow_download: true`; cache-only is
the default. Prepare once during deployment or supervised application startup,
then reuse the returned runtime instead of preparing inside a request. The Mix
task provides progress and machine-readable output:

```sh
mix obscura.profile.prepare \
  --profile balanced \
  --backend emily \
  --allow-download \
  --timeout 1800000 \
  --inactivity-timeout 300000
```

Use `--offline` with pre-provisioned caches. Preparation, cache recovery,
readiness checks, backend selection, and deployment diagnostics are covered by
the [profile guide](docs/profiles.md),
[optional dependency guide](docs/optional-dependencies-and-assets.md), and
[runtime diagnostics](docs/runtime-diagnostics.md).

The model assets are third-party downloads that Obscura neither bundles nor
licenses. In direct correspondence on 2026-07-22, LDC confirmed that commercial
use of `tner/roberta-large-ontonotes5`, used by `:balanced` and `:accurate`,
requires an LDC for-profit membership. Obscura does not grant or verify that
authorization, and noncommercial use remains subject to the applicable LDC and
upstream terms. See
[model asset licensing](docs/model-asset-licensing.md).

Stable profile names have compatibility guarantees, but stability does not
mean universal production readiness or regulatory compliance. Additional
experimental adapters remain available for controlled evaluation outside the
stable compatibility promise. See
[model-backed recognition](docs/model-backed-recognition.md).

## Extensibility

Custom recognizer modules implement `Obscura.Recognizer`:

```elixir
defmodule TicketRecognizer do
  @behaviour Obscura.Recognizer

  alias Obscura.Analyzer.Result

  def name, do: :ticket
  def supported_entities, do: [:ticket]

  def analyze(text, _opts) do
    for [{start, length}] <- Regex.scan(~r/TKT-\d{4}/, text, return: :index) do
      %Result{
        entity: :ticket,
        start: start,
        end: start + length,
        byte_start: start,
        byte_end: start + length,
        score: 0.8,
        text: binary_part(text, start, length),
        source_entity: "TICKET",
        recognizer: :ticket,
        metadata: %{}
      }
    end
  end
end

Obscura.analyze("Ticket TKT-1234",
  entities: [:ticket],
  recognizers: [TicketRecognizer]
)
```

Inline pattern definitions and deny lists are available without modifying
Obscura source:

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

Obscura.analyze("Project ORCHID",
  entities: [:project_codename],
  deny_lists: [%{entity: :project_codename, values: ["orchid"], case_sensitive: false}]
)
```

Allow lists remove known-safe values after recognition:

```elixir
Obscura.analyze("support@example.com jane@example.com",
  entities: [:email],
  allow_list: [%{entity: :email, values: ["support@example.com"]}]
)
```

## Custom NER Integration

Low-level NER integration is opt-in. This example uses `FakeServing`, a
deterministic test double for custom adapter and pipeline tests. It is not a
real model and its output is not accuracy evidence.

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

Batch analysis preserves input order:

```elixir
Obscura.analyze_many(["Alice", "Denver"],
  entities: [:person, :location],
  recognizers: [{Obscura.Recognizer.NER, serving: serving}]
)
```

## Structs, Logger, and Plug

Structs can opt into field-aware redaction with `@derive`:

```elixir
defmodule User do
  @derive {Obscura.Redactable,
           fields: [email: {:entity, :email}, password_hash: :drop, profile: :traverse]}
  defstruct [:email, :password_hash, :profile]
end

Obscura.redact(%User{email: "jane@example.com"}, entities: [:email])
```

Logger helpers redact metadata and inspected terms before they are handed to
application logs:

```elixir
Obscura.Logger.redact_metadata([user: "jane@example.com", password: "secret"],
  entities: [:email]
)
```

`Obscura.Phoenix.Plug` can assign redacted request fields or replace them:

```elixir
plug Obscura.Phoenix.Plug,
  fields: [:params],
  mode: :assign_redacted,
  entities: [:email]
```

Telemetry events include durations, counts, entities, and statuses, but omit
raw text and span values. See [Logger and Plug integration](docs/logger-and-plug.md).

## Vaults and Rehydration

Vault-backed pseudonymization supports reversible workflows:

```elixir
{:ok, vault} = Obscura.Vault.Memory.start_link()

{:ok, result} =
  Obscura.redact("Email jane@example.com",
    entities: [:email],
    operators: %{email: %{type: :pseudonymize}},
    vault: vault
  )

result.text
#=> "Email <<EMAIL_001>>"

{:ok, original} = Obscura.rehydrate(result.text, vault: vault)
original
#=> "Email jane@example.com"
```

ETS-backed vaults are available for explicitly supervised local sessions:

```elixir
children = [
  {Obscura.Vault.ETS, name: MyApp.PiiVault}
]
```

Structured data can use the same operator:

```elixir
{:ok, result} =
  Obscura.redact(%{message: "Email jane@example.com"},
    entities: [:email],
    operators: %{email: %{type: :pseudonymize}},
    vault: vault
  )

Obscura.rehydrate(result.data, vault: vault)
```

Vaults intentionally retain raw values in memory so rehydration can work.
Protect vault access and clear vaults when a request, chat, or support session
no longer needs rehydration. See [vaults](docs/vaults.md) and
[rehydration](docs/rehydration.md).

## LLM Workflows

The LLM helpers operate on provider-independent message maps:

```elixir
messages = [
  %{role: "system", content: "Be concise."},
  %{role: "user", content: "Email jane@example.com"}
]

{:ok, safe_messages, vault} =
  Obscura.LLM.redact_messages(messages, vault: :memory, entities: [:email])

safe_messages
#=> [
#=>   %{role: "system", content: "Be concise."},
#=>   %{role: "user", content: "Email <<EMAIL_001>>"}
#=> ]

Obscura.LLM.rehydrate_response("I will contact <<EMAIL_001>>.", vault: vault)
```

For streaming responses, use the streaming rehydrator:

```elixir
{:ok, stream} = Obscura.Stream.Rehydrator.new(vault: vault)
{:ok, ready, stream} = Obscura.Stream.Rehydrator.feed(stream, "Hello <<EMA")
{:ok, ready2, stream} = Obscura.Stream.Rehydrator.feed(stream, "IL_001>>")
{:ok, rest} = Obscura.Stream.Rehydrator.flush(stream)
```

See [LLM workflows](docs/llm-workflows.md) and
[streaming rehydration](docs/streaming-rehydration.md).

## Benchmark Evidence

Obscura evaluates stable profiles on pinned, fingerprinted datasets and keeps
promoted release evidence under `eval/authoritative/`. The current matrix
covers `generated_large/template_heldout`, `synth_dataset_v2`, and
`nemotron_pii_test_subset`, with two measured runs per stable profile and
dataset.

Start with the [benchmark status](docs/benchmark-status.md) for current results,
methodology, and comparison scope. Read the
[known limitations](docs/known-limitations.md) before selecting a profile.
Development commands, fixture maintenance, and contribution checks belong in
[CONTRIBUTING.md](https://github.com/hfiguera/obscura/blob/main/CONTRIBUTING.md).

Pinned benchmark snapshots are committed under
`eval/datasets/presidio_research/` with checksums, provenance, and license
attribution. Generated files under ignored `eval/reports/` are working or
historical evidence unless promoted by the authoritative manifest.

## Maturity

Obscura `0.1.x` is an early release suitable for integration and controlled
deployment when its measured scope and residual risks fit the application. It
is not a compliance guarantee, a complete Presidio replacement, or evidence of
universal production readiness.

A stable profile means its public behavior and compatibility contract are
governed. It does not guarantee suitability for every dataset, jurisdiction,
latency target, or threat model.

## Security and Privacy

Obscura runs locally and does not include remote-provider recognizers. Model
profiles never download assets during `analyze/2` or `redact/2`. Reports,
telemetry, diagnostics, and prediction exports omit raw detected values by
default.

Public result structs can contain raw detected text by design. Use
`include_text: false` when source text is unnecessary. Vault pseudonymization
is reversible and retains original values until the vault is cleared or
stopped. Memory and ETS vaults are not encrypted persistent stores, and clearing
a vault cannot guarantee secure erasure from BEAM or native-runtime memory.

Callers remain responsible for input logging, vault access and retention,
credentials, model assets, trusted callbacks, and deployment controls. Review
the [security threat model](docs/security-threat-model.md),
[known limitations](docs/known-limitations.md), and
[security policy](https://github.com/hfiguera/obscura/blob/main/SECURITY.md).

Report suspected vulnerabilities privately through
[GitHub Private Vulnerability Reporting](https://github.com/hfiguera/obscura/security/advisories/new).
Do not include raw PII, credentials, production vault contents, or private
datasets in a report.

## Compatibility

Obscura defines compatibility guarantees for its stable `0.1.x` surface. See
the [public API stability policy](docs/public-api-stability.md) for the complete
classification of stable, experimental, and internal modules, along with option
schemas, struct guarantees, and the deprecation policy.

| Surface | `0.1.x` status |
| --- | --- |
| Core text, structured, vault, LLM, Logger, Plug, and operator APIs | Stable |
| `:fast` alias | Stable name and dependency-light contract |
| `:balanced` and `:accurate` aliases | Stable implementation contracts; commercial use of their OntoNotes-trained TNER checkpoint requires LDC for-profit membership |
| Experimental profiles and low-level model adapters | Controlled evaluation without compatibility guarantees |
| Evaluation, fixture, engine, registry, and model-math modules | Internal |

Patch releases preserve stable contracts. Stable breaking changes require at
least one subsequent minor release and 90 days of deprecation, except for an
urgent security or data-corruption fix. Human-readable error text and metadata
contents are not stable; branch on documented codes and fields.

## Why the Name?

`Obscura` evokes the camera obscura, a dark chamber that admits light through a
controlled opening to produce a useful representation. The name reflects the
library's purpose: transforming sensitive input before data crosses application
boundaries.

## Project Links

- [Documentation](https://hexdocs.pm/obscura)
- [Source](https://github.com/hfiguera/obscura)
- [Contributing](https://github.com/hfiguera/obscura/blob/main/CONTRIBUTING.md)
- [Security policy](https://github.com/hfiguera/obscura/blob/main/SECURITY.md)
- [MIT License](https://github.com/hfiguera/obscura/blob/main/LICENSE)
