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

The Plug validates its mode, fields, assign name, telemetry flag, and
declarative redaction configuration during `init/1`, before the application
serves requests. Supported fields are `:params` and `:req_headers`; duplicate
fields are normalized to their first occurrence. Invalid modes, unsupported or
improper field lists, invalid assign names, and invalid redaction options raise
an `ArgumentError` during Plug initialization.

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

Both supported fields are covered by integration tests. Header assign mode
stores a redacted map while preserving the original `conn.req_headers` list.
Replace mode rebuilds the request-header list from that map, so applications
that depend on duplicate request-header entries should use assign mode.

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

The Obscura request logger refuses to start if any corresponding Phoenix HTTP
logger handler remains attached, including the endpoint-start handler that can
emit a raw request path. This turns a missing `config :phoenix, :logger, false`
setting into a startup error instead of allowing raw and sanitized records to
run side by side.

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
traces installed before the plug, or arbitrary application logs. Configure
those boundaries independently.

## Privacy-safe Phoenix socket logging

Disabling Phoenix's default logger also disables its socket connection and
socket drain records. `Obscura.Phoenix.SocketLogger` restores those records
without logging `connect_info` and omits connection parameters by default:

```elixir
children = [
  {Obscura.Phoenix.Logger, assign: :obscura_redacted},
  {Obscura.Phoenix.SocketLogger, connect_params: :omit}
]
```

The connection result, socket module, transport, serializer, and duration are
validated before logging. Drain records contain only validated counts, the
socket module, and the configured interval. Invalid identifiers and
measurements become fixed filtered or unknown labels.

Applications can explicitly include a bounded redacted copy of connection
parameters:

```elixir
{Obscura.Phoenix.SocketLogger,
 connect_params:
   {:redact,
    entities: [:email, :phone, :credit_card, :us_ssn]}}
```

Realtime parameter redaction accepts only the dependency-light `:fast` profile
and a narrow set of declarative redaction options. It does not accept
model-backed profiles, custom recognizers, parser callbacks, or automatic asset
preparation. Parameter graphs retain the request logger's structural limits and
add a stricter 4 KiB ceiling across cumulative key and scalar value text. A
payload over that realtime analysis ceiling fails closed as `[FILTERED]` before
PII recognition runs. This bounds work in Phoenix's synchronous telemetry path
without changing the parameters delivered to the socket or channel. Structs
and tuple-bearing terms, including keyword lists, fail closed without invoking
application protocol implementations.

Phoenix parameter-filter configuration is bounded as part of the same path.
Discard and keep policies accept at most 256 nonempty parameter names and
4 KiB of cumulative name text. Keep policies are compiled into map lookups
before telemetry events are handled. Invalid or oversized filter configuration
prevents a realtime logger with parameter redaction from starting.

## Privacy-safe Phoenix channel logging

`Obscura.Phoenix.ChannelLogger` restores channel join and incoming-event logs.
Raw channel topics and event names are client-controlled, so they are not
logged directly. Configure the static topic patterns and event names that are
safe to expose:

```elixir
children = [
  {Obscura.Phoenix.ChannelLogger,
   topic_patterns: ["room:*", "users:*", "system"],
   events: ["new_message", "typing", "mark_read"]}
]
```

The logger emits the matched configured pattern, not the raw topic. Unmatched
topics become `[FILTERED TOPIC]`, and unconfigured event names become
`[FILTERED EVENT]`. Oversized topics are filtered before UTF-8 validation or
pattern matching. Configured labels containing control or directional
formatting codepoints fail startup. Allowed event names are emitted from owned
startup configuration rather than client-frame binaries. Phoenix's internal
`"phoenix"` topics remain silent. The handler preserves the channel's
`:log_join` and `:log_handle_in` levels.

Join and incoming-event parameters are independently omitted by default. A
bounded redacted copy can be enabled explicitly:

```elixir
{Obscura.Phoenix.ChannelLogger,
 topic_patterns: ["room:*"],
 events: ["new_message"],
 join_params: {:redact, entities: [:email, :phone]},
 handle_in_params: {:redact, entities: [:email, :phone]}}
```

An application may opt in to include one validated UUID-valued socket assign
as Logger metadata, allowing related channel events to be correlated:

```elixir
{Obscura.Phoenix.ChannelLogger,
 topic_patterns: ["room:*"],
 events: ["new_message"],
 correlation: {:socket_assign, :chat_id, :uuid}}
```

The assign name becomes the Logger metadata key. It must be a bounded static
identifier and must not collide with Logger-reserved metadata such as `:pid`,
`:gl`, `:time`, or `:domain`. Keys containing high-confidence PII recognized
by the `:fast` profile are also rejected; invalid keys fail startup.

The assign is included only for successful joins and handled events, and only
when it is a canonical UUID string. Missing, malformed, or non-binary values
are omitted. Phoenix's join telemetry contains the socket from before
`join/3` runs. The assign must therefore exist before `join/3` to appear on the
join record. An assign added by `join/3` is available to subsequent handled
events, but not to that join record.

This supports log correlation only: it does not create spans, propagate trace
context, or provide distributed tracing. Apart from this opt-in field, the
handler never inspects socket assigns, application-private socket data, socket
identifiers, message references, callback results, or outbound messages. It
clears channel-process Logger metadata while emitting its record and then adds
only the validated correlation metadata. Any failure produces only fixed safe
labels or suppresses the record; it never falls back to raw values.

All three Phoenix handlers refuse to start while Phoenix's corresponding
default logger handler is attached. This prevents an apparently safe handler
from running beside the raw default logger. Keep
`config :phoenix, :logger, false` when using any of the Obscura Phoenix
loggers.

Phoenix telemetry metadata contains raw socket and channel parameters before
Obscura receives the event. These handlers protect only the Logger records they
produce. Other telemetry handlers attached to the same Phoenix events can
still observe the raw metadata and must be reviewed independently. The
integration also does not cover LiveView-specific telemetry, custom transport
instrumentation, channel callback logs, broadcasts, pushes, reverse-proxy
logs, or arbitrary application logs.
