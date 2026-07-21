# Streaming Rehydration

LLM responses may split tokens across chunks. `Obscura.Stream.Rehydrator` buffers possible token fragments and emits text only when it can decide whether a token is complete.

```elixir
{:ok, stream} = Obscura.Stream.Rehydrator.new(vault: vault)

{:ok, ready1, stream} = Obscura.Stream.Rehydrator.feed(stream, "Hello <<EMA")
{:ok, ready2, stream} = Obscura.Stream.Rehydrator.feed(stream, "IL_001>>")
{:ok, rest} = Obscura.Stream.Rehydrator.flush(stream)

ready1 <> ready2 <> rest
#=> "Hello jane@example.com"
```

Unknown tokens are kept by default. Use `unknown: :error` to fail on unknown token-like text.

The streaming rehydrator is pure state plus vault lookups. It does not spawn processes and does not implement a full streaming pipeline framework.
