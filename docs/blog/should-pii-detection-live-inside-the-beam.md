# Should PII Detection Live Inside the BEAM?

A Python service can find an email address. An Elixir library can find one too.

The harder question is where the privacy boundary should live.

I started thinking about that distinction after someone asked what Obscura adds
over [Presidio](https://presidio.dataprivacystack.org/). It is a fair question.
Presidio is a mature privacy framework with a broad recognizer ecosystem,
multiple NLP engines, structured data support, image redaction, and several
deployment options. Obscura is an early Elixir library.

The honest answer is not that Obscura replaces Presidio. It does not.

The useful difference is architectural. Presidio gives teams a broad privacy
framework, usually through Python or a separately operated service. Obscura
puts a smaller privacy toolkit inside the BEAM, next to the Elixir values,
processes, logs, Phoenix telemetry, and LLM messages that need protection.

That difference changes deployment, failure handling, latency, data movement,
and who owns the final boundary.

![Two valid privacy architectures: a central Presidio service and a native
Obscura boundary inside an Elixir application](media/should-pii-detection-live-inside-the-beam/presidio-obscura-boundary-choice.png)

*Both architectures can be correct. The decision is where the application
wants to own detection, policy, and protected representations.*

Unless noted otherwise, statements about Obscura's capabilities and
limitations refer to version `0.1.3`, the current release when this article was
published on August 21, 2026. Check the
[current documentation](https://hexdocs.pm/obscura/) when evaluating a later
release.

## The Result in One Minute

- **Presidio is broader.** It supports more deployment patterns, languages,
  NLP integrations, and media types. It is the stronger general privacy
  framework today.
- **Obscura is closer to Elixir application boundaries.** Its fast profile runs
  inside the BEAM without a Python service. It works directly with Elixir data,
  Logger metadata, Phoenix request and realtime logging, vaults, and LLM
  messages.
- **A service boundary has benefits.** Presidio can be isolated, scaled, and
  governed independently from the application.
- **A local boundary has benefits.** Obscura avoids a network call and keeps the
  transformation in the same supervision and data flow as the caller.
- **The accuracy evidence is mixed.** Obscura's accurate profile has higher
  exact span F1 on the three pinned comparison datasets. Presidio still wins
  some entity categories, while Obscura's fast profile trades recall for high
  precision and low latency.
- **Neither result is universal.** The datasets are synthetic, the entity
  policy is limited, and the model rows used different execution devices.
- **The choice depends on the system.** A Python application may have little
  reason to adopt Obscura. An Elixir application may not want to operate a
  separate Python service for request, logging, or LLM boundaries.

The short version is:

> Presidio is a broader privacy platform. Obscura is a native Elixir boundary.

## Start With Architecture, Not a Feature Checklist

A feature checklist makes the projects look more interchangeable than they
really are.

Both can recognize PII. Both support deterministic rules, NLP models, custom
recognizers, and anonymization. Both require applications to evaluate their
own data and risk tolerance.

The first practical difference appears before detection begins.

For an Elixir application, Presidio commonly introduces another runtime:

```text
Phoenix or Elixir process
    -> serialize text and policy
    -> call Presidio
    -> receive detections or transformed text
    -> map the result back into application data
```

That service can become a deliberate organizational boundary. One team can
operate it, update recognizers, centralize policy, and scale it independently.
It can also isolate Python and model failures from the BEAM.

The application must then own the service contract:

- authentication and authorization;
- request and response schemas;
- timeouts, retries, and overload behavior;
- network encryption and service discovery;
- version compatibility;
- policy consistency between callers;
- serialization and offset conversion;
- observability that does not copy the original payload.

None of those costs make the design wrong. They are simply part of choosing a
service boundary.

Obscura uses a different shape for its dependency light path:

```text
Phoenix or Elixir process
    -> call Obscura with an Elixir value
    -> receive detections or protected Elixir data
    -> continue inside the same application
```

There is no network hop and no second service for the fast profile. Calls use
ordinary Elixir APIs, failures return Elixir values, and vaults can be
supervised with the rest of the application.

The cost moves rather than disappears. The Elixir application now owns
capacity, upgrades, policy, and any optional model runtime. A large local model
can place meaningful pressure on memory and schedulers. Keeping execution
inside the BEAM is not automatically safer or simpler.

## What Presidio Already Provides

Presidio is not merely a collection of regular expressions. Its documented
surface includes:

- predefined and custom recognizers using NER, regular expressions, rules,
  checksums, and context;
- multiple languages and configurable NLP engines;
- integrations with external detection models;
- anonymization operators and custom operators;
- Python, PySpark, Docker, Kubernetes, and HTTP usage;
- analysis of structured and partly structured data;
- text redaction in images through OCR;
- encryption, decryption, and mapping based pseudonymization examples.

That breadth matters. A team processing scans, DICOM images, many languages,
or large Python data workloads should not treat a native Elixir API as an
automatic improvement.

Presidio also makes a careful claim about its own limits: automated detection
cannot guarantee that every sensitive value will be found. That warning
applies equally to Obscura.

## What Obscura Adds for Elixir

Obscura's value is not a new definition of PII. It is placing privacy controls
at common Elixir boundaries without requiring a second application.

### Native Elixir Data

The input can be a binary, nested maps and lists, tuples, or supported structs.
Field policy can complement detection when the application already knows the
meaning of a field:

```elixir
input = %{
  customer: %{
    email: "jane@example.com",
    password_hash: "not-for-logs"
  }
}

{:ok, result} =
  Obscura.redact(input,
    entities: [:email],
    field_policies: %{password_hash: :drop}
  )

result.data
#=> %{customer: %{email: "[EMAIL]"}}
```

Presidio has structured data support. The distinction is that Obscura applies
policy directly to Elixir terms and struct protocols, without flattening or
serializing them first.

### Logger and Phoenix Boundaries

Obscura includes Logger metadata helpers and optional Phoenix handlers for HTTP
requests, sockets, and channels. These integrations exist because
detecting a value and preventing a framework logger from emitting it are
different problems.

The earlier articles about
[Phoenix request logging](privacy-safe-phoenix-request-logging.md) and
[Phoenix realtime logging](privacy-safe-phoenix-realtime-logging.md) explain
why the consumer of a protected representation must be explicit.

A central Presidio service can still support those workflows. The Elixir
application would need to build and operate the integration that decides when
to call it, which representation the logger receives, and how failure behaves.

### Reversible LLM References

Obscura vaults map raw values to stable references and back:

```elixir
messages = [
  %{role: "user", content: "Email jane@example.com about the invoice"}
]

{:ok, protected, vault} =
  Obscura.LLM.redact_messages(messages,
    vault: :memory,
    entities: [:email]
  )

protected
#=> [%{role: "user", content: "Email <<EMAIL_001>> about the invoice"}]

Obscura.LLM.rehydrate_response(
  "I will contact <<EMAIL_001>>.",
  vault: vault
)
```

The model can preserve a relationship without receiving the underlying
identity. The application decides when the original value may return.

This is the boundary demonstrated in
[The Agent Needs Identity. The Model Does Not.](the-agent-needs-identity-the-model-does-not.md).

Presidio can implement pseudonymization through mappings or custom operators.
Obscura adds an explicit session vault API, message helpers that do not depend
on a provider, and streaming restoration as governed Elixir interfaces.

## A Practical Capability Comparison

| Question | Presidio | Obscura |
| --- | --- | --- |
| Primary runtime | Python, Spark, containers, or HTTP service | Elixir library inside the BEAM |
| Deterministic detection | Broad predefined and custom recognizers | Fast profile plus custom recognizers and patterns |
| General NER | Multiple configurable NLP engines and external models | Optional local profiles through Elixir model runtimes |
| Languages | Documented multilingual support | Current stable evidence is primarily English |
| Structured values | Structured and partly structured data modules | Nested Elixir terms, field policy, and supported structs |
| Images and OCR | Supported | Not supported |
| Reversible values | Operators and application managed mappings | Session vaults and rehydration APIs |
| Elixir logging | Application integration required | Logger and Phoenix integrations included |
| LLM messages and streams | Application integration required | Message protection and stream restoration included |
| Operational maturity | Mature and broad | Early `0.1.x` release |

The table does not identify a universal winner. It identifies which work each
application would need to own.

## What the Benchmark Actually Compared

Architecture cannot answer whether either detector works well enough.
Detection evidence needs its own protocol.

The current Obscura comparison used a fresh, locked Presidio environment:

- CPython `3.11.15`;
- `presidio-analyzer` `2.2.363`;
- spaCy `3.8.13`;
- `en_core_web_lg` `3.8.0`;
- pinned source revisions, dependency hashes, model hash, dataset hashes, and
  ordered sample IDs.

Every system received the same selected text and the same eight entity policy:
credit card, email, IP address, location, person, phone, URL, and US SSN.
Offsets were scored as half-open UTF-8 byte spans. An exact result required
both the entity and its boundaries to match.

The matrix contains three datasets and 2,648 total samples. Each row ran once
for warmup and twice for measurement. Accuracy counts were identical between
the measured repetitions.

The primary exact span F1 results were:

| System | Generated heldout | Synth V2 | Nemotron subset |
| --- | ---: | ---: | ---: |
| Presidio spaCy | 0.6809 | 0.7211 | 0.6254 |
| Obscura `:fast` | 0.6667 | 0.6382 | 0.4074 |
| Obscura `:balanced` | 0.7878 | 0.8388 | 0.6954 |
| Obscura `:accurate` | 0.8024 | 0.8423 | 0.6973 |

Obscura `:accurate` has the highest exact span F1 in this protocol. That is a
measured result, not a general claim that Obscura is more accurate than
Presidio.

The datasets are synthetic and taxonomy dependent. Presidio remains stronger
for some entity categories. On the generated and Synth V2 corpora, Presidio
has better phone F1 than Obscura `:balanced`. On Nemotron it remains better for
location and IP address. Obscura `:balanced` is better for person, phone, URL,
and US SSN on that same subset.

That mixed entity evidence matters more than the simple ranking. An
application concerned primarily with international phone numbers can reach a
different decision from one concerned with names in English support messages.

The complete protocol, counts, hashes, and entity results are in the
[authoritative comparison report](https://github.com/hfiguera/obscura/blob/main/docs/authoritative-presidio-comparison-report.md).

## Latency Needs a Separate Qualification

Presidio spaCy and Obscura `:fast` both ran on CPU on the same Apple M4 Max.
Those rows are directly comparable:

| Dataset | Presidio median | Obscura `:fast` median |
| --- | ---: | ---: |
| Generated heldout | 3.2025 ms | 0.0710 ms |
| Synth V2 | 3.1656 ms | 0.0690 ms |
| Nemotron subset | 20.7062 ms | 0.2410 ms |

The speed difference comes with a detection tradeoff. The fast profile has
high precision and limited recall. It intentionally does not attempt broad
name, organization, location, or arbitrary address recognition.

The Obscura balanced and accurate rows ran on Apple Metal GPU. Presidio ran on
CPU. Their latency values describe each tested operating point, but they do not
support a fair speed ranking. A CPU to GPU comparison would turn different
hardware paths into a misleading product claim.

This separation is important:

> Detection quality, request latency, and deployment complexity are three
> different decisions.

## When Presidio Is the Better Choice

Presidio is the stronger choice when:

- the primary application or data platform already uses Python;
- one privacy service must serve applications in several languages;
- image or OCR redaction is required;
- broad multilingual support is required;
- the team wants Presidio's recognizer and model ecosystem;
- independent scaling and failure isolation matter more than avoiding a
  network boundary;
- the team already knows how to operate Python model services.

Choosing Presidio in those conditions is not a compromise. It is using the
broader tool for the broader job.

## When Obscura Is the Better Fit

Obscura becomes useful when:

- the application is primarily Elixir and wants a local API;
- common structured identifiers are the main synchronous workload;
- nested Elixir values need field policy before logging or transmission;
- Logger or Phoenix telemetry is part of the privacy boundary;
- an LLM workflow needs stable pseudonyms and controlled restoration;
- the team wants supervision and lifecycle control inside the BEAM;
- operating a separate Python service would add more complexity than value.

Those benefits do not remove the need to evaluate detection. Obscura's fast
profile will miss broad contextual entities. Its model profiles require
optional dependencies, model assets, backend preparation, memory, and license
review.

## Using Both Is Also a Design

The choice does not have to be exclusive.

An application can use local deterministic protection for common request and
logging boundaries, then call a Presidio service for text that needs broader
language or media coverage. Obscura can also host a custom recognizer that
integrates an external service.

That design adds its own work:

- consistent entity names and score policy;
- offset conversion and conflict resolution;
- timeout and partial failure behavior;
- control over which raw text may cross the service boundary;
- tests proving that local and remote transformations do not disagree.

Combining two detectors does not automatically improve safety. It creates a
larger policy that must be measured as one system.

## The Evaluation Cannot Be Outsourced

Neither project's benchmark can answer whether it will find the identifiers in
your application.

Support messages, clinical notes, financial records, logs, and international
addresses have different language, formatting, and error costs. A false
positive can destroy useful text. A false negative can expose a person.

Before selecting either system:

1. define the entity taxonomy the application actually needs;
2. build a representative private evaluation set;
3. measure exact boundaries, not only overlapping spans;
4. review failures by entity and source type;
5. measure the complete transformation path under expected concurrency;
6. test logs, telemetry, retries, and error reports for raw values;
7. document what happens when detection or a service is unavailable.

Presidio's own documentation warns that automated detection cannot guarantee
complete coverage. Obscura makes the same limitation explicit. Neither tool is
a compliance result by itself.

## What Each Project Should Claim

Presidio can reasonably claim breadth, maturity, and an extensible privacy
framework across several workloads and deployment models.

Obscura can reasonably claim measured PII protection at native BEAM
application boundaries, including Elixir data, Logger, Phoenix, vaults, and
LLM workflows.

Neither claim cancels the other. Obscura does not have Presidio's OCR,
language, or recognizer ecosystem. Presidio's breadth does not remove the
operational cost of placing a separate service between an Elixir application
and its data.

## The Boundary Is the Product Decision

The original question was what Obscura adds over Presidio.

My answer is narrower than “another PII detector.”

Obscura adds a boundary shaped for Elixir: direct application data,
supervision, Logger and Phoenix integrations, session vaults, and LLM
transformations that remain inside the BEAM. Presidio adds a much broader
framework and ecosystem that can serve far more workloads.

If an application already lives in Python, Obscura may add little. If an
Elixir application needs image redaction or broad multilingual analysis,
Presidio may be the obvious choice. If the problem is protecting Elixir values
before they reach logs, Phoenix telemetry, APIs, or LLM providers, a native
boundary can remove an entire service from that path.

The useful difference is not that one project can find an email address and
the other cannot.

> It is where the application chooses to own the privacy boundary.
