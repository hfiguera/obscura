# Privacy-Safe Phoenix Realtime Logging Media

Publication assets for
`docs/blog/privacy-safe-phoenix-realtime-logging.md`.

- `phoenix-realtime-logging-boundary.png`: 1440 by 900 social preview and
  article architecture diagram.
- `media-source.html`: editable HTML/CSS source used to render the diagram.

The diagram must preserve the article's central distinction: Phoenix telemetry
contains raw client-controlled realtime values, while the logging boundary
emits only application-owned labels, omitted or bounded-redacted parameters,
and optional validated UUID correlation metadata.
