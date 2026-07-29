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
exception reasons. Standard HTTP methods are logged directly; bounded custom
methods must use valid HTTP token characters and are checked for high-confidence
PII; invalid or suspicious methods are replaced with `[FILTERED METHOD]`.
Dynamic log-level callback failures are contained without exposing their reason
or detaching the handler. The handler does not inherit request-process Logger
metadata, so metadata added earlier in the request cannot bypass the sanitized
message. If the redacted assign is absent, it logs `[FILTERED]` instead of
falling back to the original params. Opaque values, including
multipart upload structs and tuples, are also logged as `[FILTERED]` so
unchanged values cannot bypass structured redaction through `Inspect`.
Character lists are reconstructed and checked for high-confidence `:fast`
profile PII before inspection; ordinary integer arrays remain available to the
configured inspect policy. Atom and numeric scalar representations, including
map keys, receive the same check so inspection cannot turn an unanalyzed term
into visible PII.
Phoenix's configured `:filter_parameters` policy is applied to the redacted
copy as an additional safeguard. Binary parameter keys containing
high-confidence `:fast` profile PII are replaced with unique
`[FILTERED KEY n]` labels before inspection; controller params and the Plug
assign are not changed. Bare domain recognition is excluded from this key check
because ordinary dotted field names such as `user.name` are ambiguous. Add
application-specific dotted keys to Phoenix's filter policy when needed.
Parameter graphs exceeding 64 keys, 4 KiB of cumulative key text, 64 KiB of
cumulative scalar value text, 1,024 traversed values, 128 terms requiring PII
analysis, or 64 decimal digits in a single number fail closed as `[FILTERED]`
before key recognition. These limits bound synchronous logger work on
attacker-controlled request shapes.

Recognition is still not a universal secret detector. Unsupported formats,
unselected entities, and false negatives can remain in otherwise ordinary
string values. Configure entities and field policies for the application's
request schema, and verify representative payloads before enabling parameter
logging in production.

This integration does not sanitize reverse-proxy logs, web-server access logs,
socket/channel parameter logs, traces installed before the plug, or arbitrary
application logs. Configure those boundaries independently.
