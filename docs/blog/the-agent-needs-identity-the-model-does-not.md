# The Agent Needs Identity. The Model Does Not.

A support agent may need a customer's email address to perform a lookup. The
model does not.

The difficult part is preserving that distinction after the agent starts
calling tools.

Protecting the first prompt is useful, but an agent workflow has more than one
place where personal information can leave the application. A tool can restore
an identifier for a local query, return a raw customer record, and quietly put
the same identifier back into the next model request. A streamed answer can
cross the boundary again. Logs and telemetry can create copies outside the
conversation entirely.

I built a small support agent to test whether the boundary could survive the
complete workflow. It uses Phoenix LiveView, Jido, ReqLLM, Finch, OpenAI, and
Obscura. The customer records are synthetic and the tools are read only.

The result is not a claim that the model no longer needs context. It is a more
precise claim:

> An agent can retain useful identity relationships without sending the
> underlying identity to the model.

![A completed agent run showing a protected request and provider answer beside
a restored response in the trusted UI](media/the-agent-needs-identity-the-model-does-not/obscura-jido-agent-boundary.png)

*The provider payload uses stable tokens. Raw values appear only in the trusted
application view. Every value in the demonstration is synthetic.*

## The Result in One Minute

- **Problem:** personal information can escape through prompts, agent state,
  tool arguments, tool results, streamed responses, logs, or telemetry.
- **Rule:** the application owns identity. The model receives stable
  pseudonyms. A trusted tool restores a raw value only for a narrow local
  operation.
- **Prompt boundary:** Obscura transforms configured identifiers before Jido
  receives the request.
- **Tool boundary:** tools accept tokens, restore only the value required for a
  lookup, and protect their result before returning it to Jido.
- **Streaming boundary:** model output remains tokenized while it streams.
  Known values are restored only after the complete answer reaches the trusted
  LiveView.
- **Credential boundary:** an opaque reference travels through the agent. The
  OpenAI key is inserted only when Finch builds an approved request.
- **Evidence:** tests inspect the real Jido tool loop, streamed HTTP chunks,
  progress events, Logger output, telemetry, expired credentials, and rendered
  HTML for raw canary values.
- **Limit:** this is a reference architecture. It does not provide
  authorization, complete data loss prevention, or regulatory compliance.

This architecture is implemented in the
[Obscura Jido example application](https://github.com/hfiguera/obscura_jido_example).
You can run it in deterministic mode without an OpenAI key, or use OpenAI to
observe the protected request, tool flow, tokenized response, and final
restoration.

## An Agent Has More Than One Exit

The simple mental model for an LLM feature is often:

```text
prompt -> model -> answer
```

An agent has a larger path:

```text
user prompt
    -> application state
    -> agent state
    -> tool arguments
    -> tool results
    -> model response
    -> streaming UI
    -> logs and telemetry
```

Any one of those transitions can expose a raw value.

Consider the request used by the demonstration:

```text
Find rachel.chen@example.test and summarize her support cases.
Her phone is +1 202-555-0188.
```

Before Jido receives it, Obscura changes the configured identifiers:

```text
Find <<EMAIL_001>> and summarize her support cases.
Her phone is <<PHONE_001>>.
```

That protects the first model request. It does not yet protect the workflow.

The agent calls a customer tool with `<<EMAIL_001>>`. The tool needs the email
to query the local support store. If the tool returns this map directly, the
identity crosses the boundary on the next model turn:

```elixir
%{
  name: "Rachel Chen",
  email: "rachel.chen@example.test",
  phone: "+1 202-555-0188",
  plan: "Pro"
}
```

Nothing in prompt redaction automatically protects that tool result.

That was the failed simple solution: protect the input once and assume the
rest of the agent remains safe.

The earlier article
[Protecting PII in Elixir](protecting-pii-in-elixir.md) establishes application
boundaries and reversible pseudonymization for a single request. This agent
workflow extends that boundary across state, tools, streamed output, and local
restoration.

## The Ownership Rule

The implementation follows one rule:

> The application owns identity. The model receives pseudonyms. Trusted tools
> restore raw values only for narrowly scoped local operations.

That rule assigns responsibility to each part of the system:

| Component | Responsibility |
| --- | --- |
| Phoenix application | Accept raw input and define the trust boundary |
| Obscura | Detect configured identifiers, create stable tokens, and restore known mappings |
| Jido | Orchestrate the agent and its tools using protected values |
| Trusted tools | Restore only the lookup value they require and protect their result |
| ReqLLM and Finch | Stream the protected request to the model provider |
| OpenAI | Process the payload containing pseudonyms rather than the configured raw identifiers |

The complete path is:

```text
raw browser request
    -> Obscura creates stable pseudonyms
    -> Jido and OpenAI receive tokens
    -> trusted tool restores one lookup identifier locally
    -> tool protects the returned record
    -> model answers with tokens
    -> trusted LiveView restores known mappings
```

The framework is not the boundary. The application is.

## Create One Vault for the Session

Each connected LiveView starts an `Obscura.Vault.Memory` process. The same
vault follows one agent run from prompt protection through final restoration.

This matters because pseudonyms must be stable. The same email should remain
`<<EMAIL_001>>` in the prompt, the customer tool result, the case note, and the
model answer.

The prompt boundary uses the `:fast` profile and pseudonymization:

```elixir
@text_options [
  profile: :fast,
  entities: [:email, :phone, :credit_card, :us_ssn, :iban, :ip_address],
  operators: %{default: %{type: :pseudonymize}}
]

def protect_prompt(prompt, vault) do
  messages = [%{role: :user, content: prompt}]

  with {:ok, [%{content: protected}], ^vault} <-
         Obscura.LLM.redact_messages(
           messages,
           Keyword.put(@text_options, :vault, vault)
         ) do
    {:ok, protected}
  end
end
```

`Obscura.LLM.redact_messages/2` transforms the message structure and records
the mappings in the supplied vault. Jido receives `protected`, not `prompt`.

The raw request still existed in the browser, the HTTP request, and the
LiveView process. Pseudonymization does not erase copies that already exist.
Its job is to control the next handoff.

## Stable Pseudonyms Preserve Utility

Permanent removal would produce something like this:

```text
Find [REDACTED] and summarize her support cases.
```

That hides the email, but it also removes the reference the tool needs. A
stable pseudonym keeps the relationship:

```text
User request:  Find <<EMAIL_001>>
Tool argument: %{identifier: "<<EMAIL_001>>"}
Tool result:   %{email: "<<EMAIL_001>>"}
Model answer:  Contact <<EMAIL_001>>
```

The model can correlate the same customer across several steps without
receiving the email address.

Stability is scoped to the vault. Clearing the vault removes the mappings and
the visible conversation. When the LiveView process exits, its linked memory
vault exits with it.

That lifecycle is appropriate for this demonstration. A longer workflow may
need a different vault and an explicit retention policy.

## A Trusted Tool Restores One Identifier

The first tool accepts an email token, not an email address:

```elixir
schema:
  Zoi.object(%{
    identifier:
      Zoi.string(description: "An email pseudonym from the user request.")
  })
```

Its implementation crosses into trusted application code:

```elixir
def run(%{identifier: identifier}, %{vault: vault} = context) do
  with {:ok, restored} <- Privacy.restore_identifier(identifier, vault),
       {:ok, customer} <- Store.find_customer(restored),
       {:ok, protected} <- Privacy.protect_customer(customer, vault) do
    audit(context, :ok)
    {:ok, protected}
  else
    _reason ->
      audit(context, :not_found)
      {:error, :customer_not_found}
  end
end
```

The raw email exists briefly where it is required: inside the local lookup
path. It is not returned to Jido.

The vault PID is part of local tool context. It is not part of the tool schema
or the payload sent to the model. The model chooses a tool and supplies a
token. The application supplies the trusted context when it executes the tool.

This is also where authorization belongs. A token that can be restored is not
proof that the current user may access the underlying customer. The demo uses
a synthetic store and read only tools, so it intentionally does not present
its lookup as a production authorization design.

## Tool Results Are Another Outbound Boundary

The customer lookup protects its result before it returns:

```elixir
def protect_customer(customer, vault) do
  with {:ok, name} <- token(vault, :person, customer.name),
       {:ok, email} <- token(vault, :email, customer.email),
       {:ok, phone} <- token(vault, :phone, customer.phone) do
    {:ok,
     %{
       customer_ref: customer.customer_ref,
       name: name,
       email: email,
       phone: phone,
       plan: customer.plan,
       status: customer.status
     }}
  end
end
```

The model receives:

```elixir
%{
  customer_ref: "CUS-1042",
  name: "<<PERSON_001>>",
  email: "<<EMAIL_001>>",
  phone: "<<PHONE_001>>",
  plan: "Pro",
  status: "active"
}
```

Names use an explicit field policy because the local `:fast` profile does not
provide general contextual person recognition. Case notes use deterministic
recognition for configured structured identifiers before they return to Jido.

The second tool receives the synthetic customer reference and returns a
protected note:

```text
Send the corrected invoice to <<EMAIL_001>> or call <<PHONE_001>>.
```

This second protection step is what keeps trusted tools from reopening the
model boundary.

## Streaming Must Not Restore Too Early

Jido and ReqLLM stream the provider answer. The LiveView updates while the
request is running, but the streamed content remains tokenized:

```text
Found <<EMAIL_001>> (<<PERSON_001>>, active Pro customer).
```

Progress events carry only a small vocabulary of phases, allowed tool names,
protected text, and provider deltas. The LiveView stores those deltas in a
bounded buffer for display.

It does not restore each chunk.

Restoration happens after Jido returns the complete provider answer:

```elixir
with {:ok, provider_answer, tool_steps} <-
       execute(protected_prompt, vault, mode, opts),
     {:ok, display_answer} <-
       Privacy.restore(provider_answer, vault) do
  # provider_answer remains tokenized
  # display_answer belongs to the trusted UI
end
```

That creates two visible representations:

```text
Provider answer:
Contact <<EMAIL_001>>.

Trusted UI response:
Contact rachel.chen@example.test.
```

The final Markdown is rendered with HTML escaping and sanitization before it
is inserted into the page. Restoration decides which known values can return.
Sanitization decides which markup can render. They solve different problems.

## Credentials Are a Separate Boundary

The OpenAI key is not customer identity, but it is still a secret. Putting it
in Jido state or a provider options map would create another disclosure path.

The demo accepts the key through a CSRF protected form and copies it into a
private ETS table owned by one process. The browser session stores only an
opaque reference. The value expires after thirty minutes of inactivity and can
be deleted explicitly.

Jido and ReqLLM receive the opaque reference plus a harmless placeholder. A
ReqLLM Finch adapter resolves the real key immediately before transmission.
The adapter accepts only an approved method, host, port, and OpenAI path. It
removes the internal reference header and replaces exactly one expected
placeholder authorization header.

If the reference has expired or the destination is not approved, the request
fails before Finch contacts it.

This preserves direct streaming. There is no local HTTP proxy and no buffered
copy of the model response.

The credential store is demonstration code, not a replacement for a production
secret manager. Its purpose is to make ownership visible: the transport needs
the key, while the agent does not.

## Logs and Telemetry Need Their Own Policy

Pseudonymizing the provider payload does not automatically make every log
safe.
[Privacy-Safe Phoenix Request Logging Without Changing Controller Params](privacy-safe-phoenix-request-logging.md)
examines the HTTP side of the same problem: protecting data for one consumer
does not automatically protect what another logger can inspect. The demo
configures each dependency separately:

```elixir
config :jido, :telemetry,
  log_level: :info,
  log_args: :none

config :jido, :observability,
  debug_events: :off,
  redact_sensitive: true

config :req_llm,
  telemetry: [payloads: :none]
```

The agent also disables lifecycle signals, excludes model deltas from
telemetry, redacts tool arguments, and keeps ReqLLM payload telemetry off.

The sensitive LiveView uses `log: false` because Phoenix lifecycle records can
include event parameters. Phoenix parameter filtering keeps only its protocol
fields and filters the support prompt and CSRF token.

These choices reduce the disclosure surface of this application. They do not
sanitize another telemetry handler, an error reporter, a reverse proxy, or a
future `Logger` call. Every additional observer needs its own review.

## What the Evidence Proves

The demo includes a deterministic mode so the architecture can be exercised
without an OpenAI key. The model answer is scripted in that mode, but the Jido
runtime, agent process, tool selection, tool execution, vault, progress events,
and LiveView path are real.

The tests verify that:

- the protected prompt and provider answer exclude the raw email and phone;
- the final trusted response restores both values;
- the real Jido loop calls the expected tools in order;
- progress events contain protected text and allowed tool labels;
- the customer tool restores one token locally and returns protected fields;
- case notes are protected before they return to Jido;
- Logger output and observed Jido telemetry exclude raw canaries;
- the LiveView displays tokenized chunks before final restoration;
- Phoenix lifecycle logs exclude the prompt and credential reference;
- an HTTP test server receives real streamed SSE chunks through Finch;
- the OpenAI destination receives the real authorization header but not the
  internal reference header;
- an expired credential stops the request before the upstream server is
  contacted;
- rendered model Markdown cannot create scripts or unsafe links.

These tests do not ask whether one final string looks redacted. They inspect
each transition where the wrong representation could escape.

## What the Evidence Does Not Prove

The boundary is deliberately narrow.

The `:fast` profile recognizes configured structured entities. It can miss
unsupported formats and contextual identity. The demo handles names returned
by its own tools through an explicit field policy because those fields are
known.

The vault can restore known tokens. It cannot remove raw copies already held
by the browser, LiveView process, local store, or another process. Its memory
backend is not encrypted persistent storage.

The model can generate a new email address, name, or other sensitive value that
was never in the vault. Restoration protects known mappings; it is not an
output classifier.

The synthetic customer reference is treated as non sensitive in this dataset.
A production application must classify its own identifiers, authorize every
tool call, scope lookups to the current principal, and audit access.

The tests cover the configured Logger and telemetry paths. They do not prove
that every future dependency, callback, crash report, trace, proxy, or
deployment platform excludes sensitive data.

Finally, sending pseudonyms does not remove the need to review a provider's
retention, training, security, and contract terms. This architecture controls
the application payload. It does not control the provider.

## Where This Pattern Is Useful

The same boundary can support:

- customer support agents that summarize tickets and account history;
- SaaS assistants that query CRM or billing systems;
- incident assistants that process logs containing emails, phone numbers, or
  IP addresses;
- internal assistants that work with support and operational records;
- HR and healthcare administration workflows, with the required legal and
  security controls;
- gateways that protect prompts before they reach an external model;
- any agent that needs an identifier for a local lookup but does not need to
  reveal it to the model.

Without Obscura, the application would need to implement recognition,
pseudonym generation, stable mappings, nested message transformation, vault
lifecycle, and response restoration as separate mechanisms.

Obscura does not decide where the trust boundary belongs. It provides the
primitives that let the application build one consistently.

## Run the Complete Demonstration

The complete application is available in the
[Obscura Jido example repository](https://github.com/hfiguera/obscura_jido_example).
Deterministic mode runs without credentials and follows the same Jido and tool
path with a scripted model response.

[![Animated demonstration of the raw request, protected provider payload,
trusted tool execution, and restored LiveView response](media/the-agent-needs-identity-the-model-does-not/obscura-jido-agent-workflow.gif)](media/the-agent-needs-identity-the-model-does-not/obscura-jido-agent-workflow.mp4)

*The short preview shows the raw request becoming stable tokens, the trusted
tools completing their work, and the final response being restored locally.
Select it to watch the complete recording.*

The implementation uses [Obscura](https://github.com/hfiguera/obscura),
[Jido](https://hex.pm/packages/jido),
[ReqLLM](https://hex.pm/packages/req_llm), and
[Phoenix LiveView](https://hex.pm/packages/phoenix_live_view).

## The Model Does Not Need the Name

The support agent still finds the customer. It still calls two tools. It still
correlates the same person across the request, customer record, case note, and
answer.

The model does that work with `<<EMAIL_001>>`, `<<PERSON_001>>`, and
`<<PHONE_001>>`.

That is the useful property of reversible pseudonymization. It does not erase
identity from the application. It assigns identity an owner.

The agent needs a stable reference.

The model does not need the name behind it.
