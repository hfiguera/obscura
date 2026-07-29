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

## Privacy-safe Phoenix request logging

`Obscura.Phoenix.Logger` is an opt-in telemetry handler that logs only the
redacted params assigned by `Obscura.Phoenix.Plug`. It never reads
`conn.params`.

Disable Phoenix's default telemetry logger so it cannot emit the original
parameters:

```elixir
config :phoenix, :logger, false
```

Mount the plug after `Plug.Parsers` and before the router. Keep assign mode so
controllers continue to receive the original params:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  json_decoder: Phoenix.json_library()

plug Obscura.Phoenix.Plug,
  mode: :assign_redacted,
  fields: [:params],
  profile: :fast,
  entities: [:email, :phone, :credit_card, :us_ssn, :iban, :url]

plug MyAppWeb.Router
```

Start the handler under the application supervisor:

```elixir
children = [
  {Obscura.Phoenix.Logger, assign: :obscura_redacted}
]
```

The handler logs the route template rather than the raw request path and omits
exception reasons. If the redacted assign is absent, it logs `[FILTERED]`
instead of falling back to the original params. Opaque values, including
multipart upload structs, are also logged as `[FILTERED]` so filenames and
temporary paths cannot bypass structured redaction through `Inspect`.

Recognition is still not a universal secret detector. Unsupported formats,
unselected entities, and false negatives can remain in otherwise ordinary
string values. Configure entities and field policies for the application's
request schema, and verify representative payloads before enabling parameter
logging in production.

This integration does not sanitize reverse-proxy logs, web-server access logs,
socket/channel parameter logs, traces installed before the plug, or arbitrary
application logs. Configure those boundaries independently.
