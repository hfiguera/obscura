# Obscura

Obscura is a library-first PII detection and anonymization toolkit for Elixir.

The supported `0.1.x` surface is explicitly frozen. See
`docs/public-api-stability.md` for stable modules, experimental adapters,
option schemas, struct guarantees, and the deprecation policy.

Obscura provides a dependency-light string API for common pattern-based entities:

- email
- phone
- credit card
- US SSN
- IBAN
- IP address
- URL
- domain

## Product Profiles

Obscura has three stable profiles:

| Profile | Stability | Use case |
| --- | --- | --- |
| `:fast` | stable | Dependency-light, high-precision structured PII |
| `:balanced` | stable | Deterministic PII plus the practical best-proven general NER model |
| `:accurate` | stable | Highest measured general accuracy through an output-aware two-model cascade |

```elixir
Obscura.analyze("Contact jane@example.com", profile: :fast)
```

Model profiles require explicit reusable runtime preparation. Ordinary analyze
and redact calls never download models:

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

Downloading third-party assets is never inferred from selecting a profile.
The first online preparation must pass `allow_download: true`; the default is
cache-only. These are large assets: the measured Apple/Emily cache used about
1.4 GB for `:balanced` and 2.84 GB of active files for `:accurate`. Network and
storage performance determine cold preparation time, so applications should
prepare during deployment or supervised startup, not while handling a request.
For visible stages, observed download bytes, model index, cache location,
timeouts, and a machine-readable mode, use:

```sh
mix obscura.profile.prepare \
  --profile balanced \
  --backend emily \
  --allow-download \
  --timeout 1800000 \
  --inactivity-timeout 300000
```

Use `--offline` in deployments with pre-provisioned caches. Interrupted
unreferenced cache files are quarantined on retry. Online preparation retries
one transient model or tokenizer load failure; offline preparation never
retries asset access. Quarantined files remain on disk for diagnosis until an
operator removes them. Prepare once and reuse the returned runtime; never
prepare inside a request. Setup, cache, recovery, and backend requirements are
documented in `docs/optional-dependencies-and-assets.md`.

Applications which must continue starting while models load can supervise
`Obscura.Profile.Preparer` and call `await/2` before accepting model-backed
work:

```elixir
children = [
  {Obscura.Profile.Preparer,
   name: MyApp.ObscuraRuntime,
   profile: :balanced,
   prepare_options: [allow_download: true, real_model_backend: :emily]}
]

{:ok, runtime} = Obscura.Profile.Preparer.await(MyApp.ObscuraRuntime, :timer.minutes(30))
```

Check readiness without analyzing PII:

```sh
mix obscura.profile.check --profile fast
mix obscura.profile.check --profile balanced --backend emily --json
```

See `docs/profiles.md`, `docs/benchmark-status.md`, and
`docs/optional-dependencies-and-assets.md` before selecting a model profile.
Current accuracy, startup, concurrency, p99, memory, recovery, sustained-load,
and capacity conclusions are summarized in `docs/benchmark-status.md`.
Runtime failures are covered by `docs/runtime-diagnostics.md`; residual risks
and deployment limits are in `docs/known-limitations.md`.

`:balanced` and `:accurate` are stable, technically production-oriented profile
contracts. `:accurate` has the highest measured general accuracy, while
`:balanced` remains the practical model-backed recommendation because it uses
one model and has lower latency. Their optional model assets are third-party:
Obscura neither bundles nor licenses them, and the TNER checkpoint license is
not established. Deployers must determine whether their selected assets and use
are permitted. See `docs/model-asset-licensing.md`.

`:accurate` conditionally invokes its location specialist only when the primary
model misses location. It beats `:balanced` F1 on all three authoritative
datasets, but the gain is small on Synth/Nemotron and the second model increases
cost. See `docs/benchmark-status.md`.

Additional experimental model adapters and benchmark profiles remain available
for research and controlled evaluation. They are outside the stable
compatibility promise. See `docs/profiles.md` and
`docs/model-backed-recognition.md`.

## Installation

Obscura is pre-release. When published, add it to an Elixir project with:

```elixir
def deps do
  [
    {:obscura, "~> 0.1"}
  ]
end
```

## Analyze

```elixir
{:ok, results} = Obscura.analyze("Contact jane@example.com", entities: [:email])

[%Obscura.Analyzer.Result{entity: :email, start: 8, end: 24}] = results
```

Offsets are byte offsets. This is intentional because Elixir binaries are byte indexed and anonymization uses binary slicing.

## Anonymize

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
return a value-safe `%Obscura.Anonymizer.Error{}`. See `docs/operators.md` for
the complete schemas and hash migration guidance.

## Redact

```elixir
{:ok, result} = Obscura.redact("Call 202-555-0188", entities: [:phone])

result.text
#=> "Call [PHONE]"
```

Structured inputs return `%Obscura.Structured.Result{}` instead of `%Obscura.Anonymizer.Result{}`:

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

Inline pattern definitions and deny lists are available without modifying Obscura source:

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

## Optional NER

Explicit NER/model-output support for open-class entities is opt-in and does not download or start models by default.

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

Logger helpers redact metadata and inspected terms before they are handed to application logs:

```elixir
Obscura.Logger.redact_metadata([user: "jane@example.com", password: "secret"],
  entities: [:email]
)
```

`Obscura.Phoenix.Plug` is Plug-compatible and can either assign redacted request fields or replace them:

```elixir
plug Obscura.Phoenix.Plug,
  fields: [:params],
  mode: :assign_redacted,
  entities: [:email]
```

Telemetry events include durations, counts, entities, and statuses, but omit raw text and span values.

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

ETS-backed vaults are also available for explicitly supervised local sessions:

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

Vaults intentionally retain raw values in memory so rehydration can work. Applications should protect vault access and clear vaults when a request, chat, or support session no longer needs rehydration.

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

## Evaluation

The fixture and evaluation harnesses are part of the library development workflow:

```sh
mix test
mix obscura.fixtures
mix obscura.eval --dataset synth_dataset_v2 --profile regex_only --smoke
mix obscura.eval --dataset synth_dataset_v2 --profile context --smoke
mix obscura.eval --dataset synth_dataset_v2 --profile llm_safe --smoke
mix quality
mix ci
```

Pinned Presidio-Research benchmark snapshots are committed under
`eval/datasets/presidio_research/` with checksums, provenance, and license
attribution, so dependency-light evaluation works from a fresh clone.

## Security And Privacy

Obscura is local and dependency-light. It does not include remote-provider
recognizers, and model profiles never download assets during `analyze/2` or
`redact/2`. Reports, telemetry, diagnostics, and prediction exports omit raw
detected values by default. Callers still own input logging, vault retention,
credentials, and deployment controls. Applications can implement external
integrations through the public custom-recognizer contract.

Vault pseudonymization is reversible and retains original values until the
vault is cleared or stopped. Obscura does not currently provide encrypted
persistent vault storage or compliance certification.

## Maturity

Obscura is suitable for pre-release integration and controlled evaluation. It
is not yet a production `1.0`, a compliance guarantee, or a complete Presidio
replacement. Select a profile from measured dataset-specific evidence and read
`docs/known-limitations.md` before deployment.

Current release-relevant evidence lives under `eval/authoritative/`. It includes
two measured runs per stable profile and dataset across
`generated_large/template_heldout`, `synth_dataset_v2`, and
`nemotron_pii_test_subset`. Files generated under ignored `eval/reports/` are
historical or working evidence unless promoted by that manifest.

Obscura remains pre-release. A stable profile means governed behavior and
evidence, not universal production readiness or regulatory compliance.

## Security

Obscura keeps errors, diagnostics, default inspection, telemetry, and
authoritative reports value-safe, but its public results can contain raw or
rehydrated values by design. Use `include_text: false` when detected source
text is unnecessary, supervise and clear reversible vaults, and treat custom
callbacks and optional model runtimes as trusted code.

Memory and ETS vaults are not encrypted persistent stores. Clearing or stopping
a vault removes accessible mappings but cannot guarantee secure erasure of
BEAM or native-runtime memory. See
`docs/security-threat-model.md`, `docs/known-limitations.md`, and `SECURITY.md`.

Report suspected vulnerabilities privately through
[GitHub Private Vulnerability Reporting](https://github.com/hfiguera/obscura/security/advisories/new).
Do not include raw PII, credentials, production vault contents, or private
datasets in a report.

## Compatibility

| Surface | `0.1.x` status |
| --- | --- |
| Core text, structured, vault, LLM, logger, Plug, and operator APIs | Stable |
| `:fast` alias | Stable name and dependency-light contract |
| `:balanced` and `:accurate` aliases | Stable implementation contracts; optional third-party assets require deployer licensing review |
| Experimental profiles and low-level model adapters | Research and controlled evaluation without compatibility guarantees |
| Evaluation, fixture, engine, registry, and model-math modules | Internal |

Patch releases preserve stable contracts. Stable breaking changes require at
least one subsequent minor release and 90 days of deprecation, except for an
urgent security or data-corruption fix. Human-readable error text and metadata
contents are not stable; branch on documented codes and fields.
