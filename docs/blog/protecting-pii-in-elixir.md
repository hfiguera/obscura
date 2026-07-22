# Protecting PII in Elixir Before It Reaches Logs, APIs, and LLMs

Personal information rarely stays in one place.

An email address received by a Phoenix endpoint may also appear in request
logs, telemetry, a support event, an outbound API payload, and an LLM prompt.
Removing it at the database boundary is too late. The safer place to act is at
the application boundaries where data is about to leave your control.

Once a value has entered a log pipeline or crossed an API boundary, the
redaction step has already missed its best opportunity.

That is the problem [Obscura](https://github.com/hfiguera/obscura) is designed
to address. Obscura is a library-first PII detection and anonymization toolkit
for Elixir. It can detect structured identifiers, redact nested data, protect
Logger and Plug boundaries, and pseudonymize LLM messages without sending the
original values to a remote recognition service.

This article builds a practical protection layer from those pieces. It also
describes what the library cannot guarantee, because PII detection is a risk
control, not a proof that every sensitive value has been removed.

![Obscura workbench detecting email, phone, domain, and credit-card entities
with the fast profile](media/protecting-pii-in-elixir/obscura-workbench-fast-detection.jpg)

*The dependency-light `:fast` profile detects structured PII locally. All
values shown in this article are synthetic.*

## Start at the boundary

Consider a support request:

```text
Rachel asked us to reply to info@acme.example or call 202-555-0188.
```

The application may need the original request to perform its work. Most
downstream systems do not.

The biggest mistake is treating PII removal as one final cleanup step. A more
useful policy is:

1. Accept sensitive input only where it is required.
2. Detect and transform PII before passing data to a less trusted boundary.
3. Retain the original for as little time as the workflow permits.
4. Treat detection misses as an expected failure mode and test with your own
   data.

That transformation step is Obscura's role. Your application still controls
where it runs, which entities it looks for, and what happens to the original.

## Install Obscura

Obscura 0.1.0 is available from Hex:

```elixir
def deps do
  [
    {:obscura, "~> 0.1.0"}
  ]
end
```

The dependency-light `:fast` profile is a good starting point. It detects
structured PII such as email addresses, phone numbers, credit cards, US Social
Security numbers, IBANs, IP addresses, URLs, and domains without preparing a
machine-learning model.

```elixir
text = "Reply to info@acme.example or call 202-555-0188."

{:ok, detections} =
  Obscura.analyze(text,
    profile: :fast,
    entities: [:email, :phone]
  )

Enum.map(detections, &{&1.entity, &1.start, &1.end})
#=> [{:email, 9, 26}, {:phone, 35, 47}]
```

Analyzer offsets are UTF-8 byte offsets. That matches Elixir binary slicing
and avoids silently treating Unicode code points as byte positions.

Detection is useful for inspection and policy decisions. At an outbound
boundary, transformation is usually the safer default:

```elixir
{:ok, result} =
  Obscura.redact(text,
    profile: :fast,
    entities: [:email, :phone]
  )

result.text
#=> "Reply to [EMAIL] or call [PHONE]."
```

`Obscura.redact/2` combines detection and anonymization. You can also analyze
once and select a different operator for each entity:

```elixir
{:ok, detections} =
  Obscura.analyze(text,
    profile: :fast,
    entities: [:email, :phone]
  )

{:ok, result} =
  Obscura.anonymize(text, detections,
    operators: %{
      email: %{type: :replace, value: "[CONTACT_EMAIL]"},
      phone: %{type: :mask, char: "*", keep_last: 4}
    }
  )

result.text
#=> "Reply to [CONTACT_EMAIL] or call ********0188."
```

Other operators cover removal, secure or deterministic hashes,
pseudonymization, and application-defined callbacks. Every operator is
validated before the first replacement is applied. A malformed configuration
therefore returns a structured error instead of leaving behind a partially
transformed value, which is an especially dangerous failure mode at a privacy
boundary.

## Protect structured data before an API call

Outbound payloads are rarely plain strings. Obscura traverses maps and lists
while preserving their shape:

```elixir
payload = %{
  event: "support_ticket",
  customer: %{
    email: "info@acme.example",
    message: "Call 202-555-0188"
  },
  internal_note: "temporary escalation token"
}

{:ok, result} =
  Obscura.redact(payload,
    profile: :fast,
    entities: [:email, :phone],
    field_policies: %{internal_note: :drop}
  )

result.data
#=> %{
#=>   event: "support_ticket",
#=>   customer: %{
#=>     email: "[EMAIL]",
#=>     message: "Call [PHONE]"
#=>   }
#=> }
```

This makes the protection policy explicit at the call site:

```elixir
with {:ok, safe} <-
       Obscura.redact(payload,
         profile: :fast,
         entities: [:email, :phone]
       ),
     {:ok, response} <- MyAPI.create_event(safe.data) do
  {:ok, response}
end
```

Do not keep using `payload` after creating the redacted copy. Obscura cannot
erase references that the caller, an earlier plug, or another process already
retains.

## Put redaction before logging and instrumentation

Logs are often the easiest boundary to overlook. They are durable, widely
replicated, and commonly accessible to more people than the primary datastore.
Redact values before handing them to `Logger`:

```elixir
metadata = [user: "info@acme.example", ticket_id: "T-1042"]

{:ok, safe_metadata} =
  Obscura.Logger.redact_metadata(metadata,
    profile: :fast,
    entities: [:email]
  )

Logger.info("support request accepted", safe_metadata)
```

For inspected terms, use `Obscura.Logger.safe_inspect/2` before interpolation:

```elixir
{:ok, inspected} =
  Obscura.Logger.safe_inspect(metadata,
    profile: :fast,
    entities: [:email]
  )

Logger.debug("request metadata: #{inspected}")
```

Phoenix and other Plug applications can place the protection boundary early in
the pipeline. Assign mode retains the original request fields and stores a
redacted copy in `conn.assigns.obscura_redacted`:

```elixir
plug Obscura.Phoenix.Plug,
  fields: [:params],
  mode: :assign_redacted,
  profile: :fast,
  entities: [:email, :phone]
```

Replace mode overwrites configured fields in the returned connection:

```elixir
plug Obscura.Phoenix.Plug,
  fields: [:params],
  mode: :replace,
  profile: :fast,
  entities: [:email, :phone]
```

This is why plug order matters. Neither mode can retract values already
captured by request logging, tracing, exception reports, or an earlier plug.
Redaction after instrumentation may produce a safe controller payload while
the original request is already sitting in a trace.

## Pseudonymize an LLM conversation

LLM workflows often need identity consistency rather than irreversible
redaction. The model should see that the same person or email appears twice,
but it may not need the original value.

A useful compromise is to replace detected values with stable tokens inside a
session vault:

```elixir
messages = [
  %{role: "system", content: "Summarize the request."},
  %{
    role: "user",
    content: "Email info@acme.example. Send the answer to info@acme.example."
  }
]

{:ok, safe_messages, vault} =
  Obscura.LLM.redact_messages(messages,
    vault: :memory,
    profile: :fast,
    entities: [:email]
  )

safe_messages
#=> [
#=>   %{role: "system", content: "Summarize the request."},
#=>   %{
#=>     role: "user",
#=>     content: "Email <<EMAIL_001>>. Send the answer to <<EMAIL_001>>."
#=>   }
#=> ]
```

Send `safe_messages` to the provider, then rehydrate a response with the same
vault when the trusted side of the application needs the original value:

```elixir
provider_response = "The reply should be sent to <<EMAIL_001>>."

{:ok, original_response} =
  Obscura.LLM.rehydrate_response(provider_response, vault: vault)

original_response
#=> "The reply should be sent to info@acme.example."
```

Pseudonymization is reversible tokenization, not encryption. The vault retains
the original values in memory or ETS until it is cleared or stopped. Protect
access to it, scope it to a request or conversation, and dispose of it as soon
as rehydration is no longer needed.

Obscura does not call an LLM provider itself. Its message helpers operate on
provider-independent maps, so the application remains responsible for the
provider client, retention settings, authentication, and transport policy.

![Obscura replacing a synthetic email with a session token before a simulated
LLM provider call](media/protecting-pii-in-elixir/obscura-workbench-vault-llm.jpg)

*The example workbench makes no network call. The provider response is
simulated locally so the trust boundary remains visible.*

## Use model-backed recognition when the text is less structured

One lesson became clear while building and evaluating Obscura: structured
identifiers and prose entities are different detection problems. Regex and
parsers work well for the former. They are not general solutions for names,
locations, or organizations in prose:

```text
Rachel works at Google in Paris.
```

That distinction led to three stable profiles with different operating
constraints:

| Profile | Intended use | Runtime cost |
| --- | --- | --- |
| `:fast` | Structured and context-labelled PII with high precision | Dependency-light BEAM execution |
| `:balanced` | General text needing person, location, and organization recognition | One local NER model |
| `:accurate` | Highest measured general accuracy with conditional location recovery | Two local NER models |

Model-backed profiles require optional Nx, Bumblebee, and backend dependencies,
plus third-party model assets. Preparation is explicit. Ordinary analysis and
redaction never download a model:

```elixir
{:ok, runtime} =
  Obscura.Profile.prepare(:balanced,
    allow_download: true,
    real_model_backend: :emily,
    emily_fallback: :raise,
    compile: [batch_size: 1, sequence_length: 128]
  )

{:ok, detections} =
  Obscura.analyze(
    "Rachel works at Google in Paris.",
    profile: runtime,
    entities: [:person, :organization, :location]
  )
```

A multi-gigabyte model is application infrastructure, not a request-scoped
dependency. Prepare the runtime once during deployment or supervised
application startup, then reuse it. Constructing one for every request would
turn model loading into the dominant part of the request path:

```elixir
children = [
  {Obscura.Profile.Preparer,
   name: MyApp.ObscuraRuntime,
   profile: :balanced,
   prepare_options: [
     allow_download: true,
     real_model_backend: :emily,
     emily_fallback: :raise
   ]}
]

{:ok, runtime} =
  Obscura.Profile.Preparer.await(
    MyApp.ObscuraRuntime,
    :timer.minutes(30)
  )
```

Preparation is cache-only unless `allow_download: true` is passed. Production
deployments can pre-populate the cache and use `offline: true` to prohibit
network access at runtime. On the measured development setup, active cached
assets occupied about 1.4 GB for `:balanced` and 2.84 GB for `:accurate`, so
model storage belongs in deployment planning rather than request handling.

Emily provides the measured Apple Silicon GPU path. Backend availability and
actual device use should be verified during deployment; the presence of a
dependency alone is not proof that inference is accelerated.

## What the current measurements say

Model-card scores could not answer the question that mattered here: which
profile works best for Obscura's entity taxonomy and exact-span contract? The
project therefore evaluates profiles against fixed datasets using exact UTF-8
byte spans. The current [authoritative benchmark
report](https://github.com/hfiguera/obscura/blob/main/docs/benchmark-status.md)
records the protocol, dataset fingerprints, entity mapping, hardware, backend,
and two clean repetitions. Its Apple M4 Max results include:

| Dataset | `:fast` F1 | `:balanced` F1 | `:accurate` F1 |
| --- | ---: | ---: | ---: |
| Presidio generated heldout | 0.6667 | 0.7878 | 0.8024 |
| Synthetic PII v2 | 0.6382 | 0.8388 | 0.8423 |
| Nemotron PII subset | 0.4074 | 0.6954 | 0.6973 |

These numbers explain the profile split:

- `:fast` favors precision, low latency, and minimal dependencies, but misses
  open-class entities.
- `:balanced` is the practical general-text recommendation.
- `:accurate` adds a conditional location-recovery model and produces the
  highest measured general F1, with more preparation, memory, and latency.

The table is evidence for those particular datasets, entity mappings, and
hardware conditions. It is not evidence that Obscura is universally more
accurate than another detector, and synthetic corpora do not represent every
production distribution. Evaluate the selected profile against representative
application data before relying on it.

## The security boundary is larger than the library

This is the part worth stating plainly: Obscura reduces the chance that
selected PII reaches a downstream system. It does not make the surrounding
application automatically safe.

Keep these constraints explicit:

- Detection has false positives and false negatives. Unsupported formats and
  unselected entities remain unchanged.
- Analyzer results can contain source text when `include_text: true`. Avoid
  retaining or serializing it when offsets and entity types are sufficient.
- Redaction creates a new value. It cannot zeroize copies already present in
  BEAM or native-runtime memory.
- Memory and ETS vaults are reversible session stores, not encrypted persistent
  storage.
- Custom recognizers and operators are trusted code. They receive raw values
  and can leak them independently.
- Hashing is not encryption. Deterministic hashing reveals equality and still
  permits guessing attacks against low-entropy values.
- Model assets are not bundled or licensed by Obscura. Applications must review
  each checkpoint's terms before deployment.
- Obscura is not a regulatory compliance certification or a guarantee that all
  PII has been found.

The practical response is defense in depth: minimize collection, place Obscura
before logs and outbound calls, restrict vault lifetime, avoid raw values in
telemetry, apply provider retention controls, and test against the actual data
your system handles.

## Try the complete workflow

The [Obscura example
workbench](https://github.com/hfiguera/obscura_examples) is a Phoenix LiveView
application that exercises the published library API. It includes text and
structured redaction, operators, vault and LLM workflows, Logger and Plug
boundaries, and explicit model preparation.

Use synthetic values in the workbench. A local interface avoids a remote
recognition service, but submitted values still live in the browser, LiveView
process, and BEAM memory during the session.

![Short Obscura workflow showing detection, anonymization, and LLM
pseudonymization](media/protecting-pii-in-elixir/obscura-pii-boundary-workflow.gif)

The same ten-second walkthrough is available as a higher-resolution
[MP4](media/protecting-pii-in-elixir/obscura-pii-boundary-workflow.mp4).

The library source and installation instructions are available in the
[Obscura repository](https://github.com/hfiguera/obscura), with API
documentation on [HexDocs](https://hexdocs.pm/obscura/0.1.0/).

Protecting PII is most effective when it is treated as an application-boundary
decision. Detect what the next system does not need, transform it before the
handoff, and keep the original inside the smallest possible trust boundary.
