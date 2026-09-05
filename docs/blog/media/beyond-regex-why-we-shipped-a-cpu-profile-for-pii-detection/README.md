# Efficient CPU profile media

Publication assets for
`docs/blog/beyond-regex-why-we-shipped-a-cpu-profile-for-pii-detection.md`.

- `efficient-cpu-tradeoff.png`: 1440 by 900 article and social preview.
- `media-source.html`: editable HTML/CSS source. Render at a 1440 by 900 CSS
  pixel viewport, device scale factor 1, with browser fonts ready; capture
  the viewport as PNG. No external fonts or other network assets are used.

The synthetic example was executed with Obscura 0.2.0, a fresh memory vault
for each profile, and `entities: [:person, :location, :email]`. It demonstrates
these particular outputs, not an assertion that `:fast` can never detect
names or locations.

The aggregate differences come from `eval/efficient/results/heldout.json`:
6,394 − 4,401 = 1,993 fewer exact false negatives, and
4,286 − 1,242 = 3,044 additional exact false positives. They cover the full
eight-entity evaluation and are distinct from the three-entity example.
Exact false negatives include boundary/type mismatches; they are not a count
of completely unmasked values.
