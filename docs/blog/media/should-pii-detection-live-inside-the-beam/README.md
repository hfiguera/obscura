# Presidio And Obscura Comparison Media

Publication assets for
`docs/blog/should-pii-detection-live-inside-the-beam.md`.

- `presidio-obscura-boundary-choice.png`: 1440 by 900 article and social
  preview showing the two deployment boundaries.
- `media-source.html`: editable HTML and CSS source used to render the image.

The visual deliberately presents both architectures as valid. Presidio owns a
separate service boundary with independent operation and broad capabilities.
Obscura keeps the transformation inside the Elixir application and its BEAM
lifecycle.
