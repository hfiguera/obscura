# Telemetry

Obscura emits telemetry events for integration with application metrics. Telemetry metadata must describe behavior without including raw text, span values, request parameters, or replacement source values.

## Events

Current events include:

- `[:obscura, :analyze, :start]`
- `[:obscura, :analyze, :stop]`
- `[:obscura, :anonymize, :stop]`
- `[:obscura, :structured, :redact, :stop]`
- `[:obscura, :logger, :redact, :stop]`
- `[:obscura, :vault, :token, :stop]`
- `[:obscura, :vault, :lookup, :stop]`
- `[:obscura, :rehydrate, :stop]`
- `[:obscura, :stream, :rehydrate, :stop]`
- `[:obscura, :llm, :redact_messages, :stop]`
- `[:obscura, :llm, :rehydrate_response, :stop]`
- `[:obscura, :analyzer, :analyze_many, :stop]`
- `[:obscura, :recognizer, :ner, :analyze, :stop]`
- `[:obscura, :recognizer, :ner, :analyze_many, :stop]`
- `[:obscura, :recognizer, :ner, :serving, :build, :stop]`
- `[:obscura, :recognizer, :ner, :real_model, :analyze, :stop]`
- `[:obscura, :eval, :real_model, :stop]`
- `[:obscura, :cli, :detect, :stop]`
- `[:obscura, :cli, :redact, :stop]`
- `[:obscura, :eval, :prediction_export, :stop]`
- `[:obscura, :profile, :preparation, :preparation_started]`
- `[:obscura, :profile, :preparation, :stage_started]`
- `[:obscura, :profile, :preparation, :stage_progress]`
- `[:obscura, :profile, :preparation, :stage_completed]`
- `[:obscura, :profile, :preparation, :stage_failed]`
- `[:obscura, :profile, :preparation, :preparation_completed]`

The dispatch boundary keeps only allowlisted numeric measurements, including
durations, latency, sample counts, and preparation byte/percentage progress.
Metadata is limited to known
operational keys and safe atom, number, boolean, or recursively safe list
values. Arbitrary binary metadata is replaced with `:redacted`; unknown keys
and unsupported values are dropped. Model IDs, paths, exception messages,
tokens, and arbitrary caller labels are therefore not emitted by this
boundary.

Preparation metadata may include safe profile/model aliases, model index/count,
stage, cache status/source, backend, status, and diagnostic code. It never
includes the effective cache path, repository URL, authentication token, or
low-level error text.

## Safety Rules

Telemetry metadata must not include:

- raw input text
- analyzer result values
- request params
- Logger metadata values
- replacement source values
- raw vault values
- LLM prompt or response content
- full vault entries
- model token text
- raw model outputs
- prompts
- authorization headers
- API keys or bearer tokens

Obscura filters unsafe metadata keys before delegating to
`:telemetry.execute/3`. The internal telemetry dispatch helper is not part of
the public API. Telemetry handlers execute in the caller process and are
trusted application code; keep handler failures and handler-owned state from
capturing sensitive arguments outside Obscura's sanitized event payload.

## Disabling Events

Most public APIs accept `telemetry: false` when tests or local callers need to disable events.
