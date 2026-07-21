# Logger and Plug Helpers

Obscura includes small integration helpers for common Elixir application
boundaries. They wrap structured redaction and must not log raw PII in helper
diagnostics or telemetry metadata.

## Logger Helpers

```elixir
metadata = [user: "jane@example.com", password: "secret"]

{:ok, redacted} =
  Obscura.Logger.redact_metadata(metadata, entities: [:email])

redacted[:user]
#=> "[EMAIL]"
```

`Obscura.Logger.safe_inspect/2` redacts a term and then inspects the redacted result:

```elixir
{:ok, inspected} = Obscura.Logger.safe_inspect(metadata, entities: [:email])
```

Use these helpers before passing metadata or inspected terms to `Logger`.

Recognition is not a universal secret detector. Values outside the selected
entities, unsupported formats, and false negatives remain unchanged. The
original term also remains in caller memory after a redacted copy is produced,
so do not log it before or after calling the helper.

## Plug-Compatible Helper

`Obscura.Phoenix.Plug` depends on Plug, not Phoenix. It can be mounted in Phoenix or any Plug pipeline.

Assign mode keeps original request fields and stores redacted copies under `conn.assigns.obscura_redacted`:

```elixir
plug Obscura.Phoenix.Plug,
  fields: [:params],
  mode: :assign_redacted,
  entities: [:email]
```

Replace mode mutates configured connection fields:

```elixir
plug Obscura.Phoenix.Plug,
  fields: [:params],
  mode: :replace,
  entities: [:email]
```

Supported fields are the connection fields represented by the current Plug helper implementation, with `:params` covered by tests.

Assign mode intentionally preserves the original connection fields. Replace
mode overwrites selected fields in the returned connection, but cannot erase
copies already observed by earlier plugs, request logging, tracing, crash
reports, or caller variables. Place the helper before untrusted
instrumentation and treat the original connection as sensitive for its full
lifetime.
