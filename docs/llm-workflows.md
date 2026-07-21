# LLM Workflows

Obscura includes provider-independent helpers for message lists. It does not
depend on OpenAI, Anthropic, Gemini, LangChain, or another provider SDK.

```elixir
messages = [
  %{role: "system", content: "Be concise."},
  %{role: "user", content: "Email jane@example.com"}
]

{:ok, safe_messages, vault} =
  Obscura.LLM.redact_messages(messages, vault: :memory, entities: [:email])
```

Only configured roles are redacted. The default role list is `[:user]`.

```elixir
safe_messages
#=> [
#=>   %{role: "system", content: "Be concise."},
#=>   %{role: "user", content: "Email <<EMAIL_001>>"}
#=> ]
```

Responses can be rehydrated with the same vault:

```elixir
Obscura.LLM.rehydrate_response("I will contact <<EMAIL_001>>.", vault: vault)
```

Message maps with atom keys and string keys are supported. Unknown keys are preserved.

Explicit experimental NER options pass through to message redaction:

```elixir
serving =
  Obscura.Recognizer.NER.FakeServing.new(%{
    "Alice" => [%{label: "PER", start: 0, end: 5, score: 0.9}]
  })

Obscura.LLM.redact_messages([%{role: :user, content: "Alice"}],
  vault: :memory,
  entities: [:person],
  recognizers: [{Obscura.Recognizer.NER, serving: serving}]
)
```

NER is never enabled implicitly.

## Safety

Vault-backed prompts are reversible. The application must protect vault access and avoid logging raw prompts before redaction.
