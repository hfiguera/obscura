# Animated article scenes

All ten articles use a continuous SVG scene in the blog's charcoal, teal, and
pale green palette. Original article figures and captions are automatic fallbacks; the Markdown
and social images are unchanged. There is no original-figure disclosure.

The scenes use locally authored geometry and the articles' examples and evidence.
They are explanatory sequences, not recordings or new benchmark results. Identity
examples are synthetic. The hybrid scene's 163 squares and the CPU scene's
tradeoff counts come from the corresponding article, with qualifications in the
captions and accessible descriptions. Memory release means an allocation can be
reclaimed when references disappear; it does not imply zeroization.

## Sources

- `request-scene.html.eex`: the approved Phoenix HTTP logging scene.
- `request-scene.css`: shared visual language and responsive controls.
- `request-scene.js`: shared eleven-second player, HTTP animation, and declarative
  timeline evaluator for the other scenes.
- `scenes/generate.py`: the nine other article compositions, their separate
  desktop/mobile layouts, and editorial captions. Uses Python's standard library.
- `scenes/*.html` and `scenes/catalog.json`: committed generated artwork and copy.
- `scenes/figure.html.eex`: common figure shell. Source generator and catalog are
  not copied to the published site.

After editing a composition, regenerate its committed artwork:

```sh
python3 docs/blog/scenes/generate.py
```

The normal Elixir build reads the generated files and does not require Python.

## Motion contract

The original image and its caption are the default HTML state. The scene starts
hidden and replaces the image only after its player, SVG support, and stylesheet
are available and its first render succeeds. On first entering view, the player
runs once; it never loops. Play/pause/replay and a keyboard-accessible
scrubber permit inspection at any moment. Playback pauses offscreen and when the
browser tab is hidden. Reduced motion, disabled or blocked JavaScript, missing
SVG/animation support, and a missing scene stylesheet retain the original image.
Changing the motion preference during playback pauses and swaps representations.
Printed pages always use the original image and caption.

The general scenes use numeric SVG attributes: `data-show` / `data-hide` for
opacity intervals, `data-shift` / `data-drift` for movement relative to the authored
position, `data-draw` for line progression, `data-mask` for a cover-and-uncover
redaction, and `data-flight` for a transient value moving between two points.
Times are milliseconds. The SVG geometry carries the meaning; captions explain
qualifications. Keep the default markup consistent with the finished timeline,
including invisible transient packets and removed raw values.

## Build and review

```sh
mise exec -- mix run --no-start scripts/build_pages.exs
mise exec -- mix run --no-start scripts/verify_pages.exs
python3 -m http.server 4186 --bind 127.0.0.1 --directory _site
```

The builder recreates `_site/`. Open `http://127.0.0.1:4186/` for the preview.
Check desktop, phone and narrow phone widths, intermediate and final states,
play/pause/replay, timeline keyboard controls, offscreen pausing, reduced motion,
JavaScript disabled or blocked, unavailable animation support, missing scene CSS,
and print rendering. Only one representation should be visible. Keep boundary labels
truthful: a trusted tool handling raw identity belongs outside the model boundary.
Publishing continues through the existing GitHub Pages workflow.
