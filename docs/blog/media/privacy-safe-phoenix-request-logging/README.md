# Privacy-Safe Phoenix Request Logging Media

Publication assets for `docs/blog/privacy-safe-phoenix-request-logging.md`.

- `phoenix-safe-logging-boundary.png`: 1440 by 900 social preview and article
  architecture diagram.
- `media-source.html`: editable HTML/CSS source used to render the diagram.

The diagram must preserve the architectural distinction at the center of the
article: the controller receives the original request parameters, while the
logging path reads only the redacted assign and never falls back to raw input.
