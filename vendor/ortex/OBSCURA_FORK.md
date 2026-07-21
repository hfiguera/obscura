# Obscura Ortex Fork

This directory is a minimal fork of Ortex 0.1.10, licensed under the MIT
license in `LICENSE`. The upstream project is:

- https://github.com/elixir-nx/ortex
- upstream release: `0.1.10`
- upstream commit: `450dbe6d3ce9c42cf79d26ff62ef0630fa86cfda`

Obscura maintains this fork because the released API accepts execution-provider
names but does not expose CoreML provider options or ONNX Runtime profiling.
The fork preserves the original API and adds:

- `Ortex.load_with_options/3`
- fail-fast CoreML registration through ONNX Runtime's CoreML provider API
- CoreML `ModelFormat`, `MLComputeUnits`, `RequireStaticInputShapes`, and
  `EnableOnSubgraphs` options
- `Ortex.end_profiling/1`

Keep changes limited to those capabilities so a future upstream Ortex release
can replace this fork without changing Obscura's recognizer API.
