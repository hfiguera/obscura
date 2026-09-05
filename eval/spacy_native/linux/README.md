# Linux spaCy CPU validation

This Docker lane builds the actual Rust executable and Obscura profile on Debian
12 (glibc), using OpenBLAS and PCRE2. It covers Linux ARM64 and x86-64. Model
exports are portable and must already exist locally; neither Python nor network
access is needed during validation. Docker Desktop runs x86-64 under emulation
on Apple Silicon, so those timings are not a hardware performance benchmark.
See the [recorded Linux results](../results/LINUX.md) for the completed checks.

Run from the repository root with Docker Desktop running:

```sh
docker buildx build --platform linux/arm64 \
  -f eval/spacy_native/linux/Dockerfile -t obscura-spacy-cpu:linux-arm64 --load .
mkdir -p .cache/spacy_cpu/linux-arm64
docker run --rm --platform linux/arm64 --network none \
  -e OBSCURA_SPACY_MODEL_DIR=/models \
  -e OBSCURA_SPACY_RESULTS_DIR=/results \
  -v "$PWD/.cache/spacy_cpu/en_core_web_lg-3.8.0:/models:ro" \
  -v "$PWD/eval/datasets/presidio_research:/work/eval/datasets/presidio_research:ro" \
  -v "$PWD/.cache/obscura-research/datasets/nvidia-Nemotron-PII:/work/.cache/obscura-research/datasets/nvidia-Nemotron-PII:ro" \
  -v "$PWD/.cache/spacy_cpu/linux-arm64:/results" \
  obscura-spacy-cpu:linux-arm64
```

Repeat with `linux/amd64` and replace `linux-arm64` with `linux-amd64` in image
and output names. For x86-64 emulation on Apple Silicon, add
`--build-arg 'ERL_FLAGS=+JMsingle true'` to the build command. This validation-only
setting avoids Erlang JIT dual-mapping failures under emulation; it is retained
in that test image. See [Erlang's emulator flags](https://www.erlang.org/doc/apps/erts/erl_cmd.html).
Physical Linux hosts do not need it. Image builds may download the pinned Rust toolchain, Debian
libraries, locked Cargo/Hex dependencies, and dependency NIFs. No image is
published. The Dockerfile-specific ignore file restricts the build context to
source/tests and privacy-safe reference reports, excluding all model weights,
datasets, local environments, and host binaries. Model/dataset mounts are
read-only; results go to a separate writable directory.

The validation command fails if real assets or a compatible native executable
are missing. It runs the profile readiness CLI, native and lifecycle tests, and
the public profile benchmark. All final prediction fingerprints and strict F1
must equal the earlier macOS native baseline, on all 2,648 documents twice.
`profile.json` records model/binary/source hashes and CPU backend metadata;
`PROFILE.md` summarizes that run. Files contain counts, hashes, and timings,
without source text or per-document raw predictions.

This is a development validation image, not a minimal deployment image. Runtime
deployments can omit Rust, compilers, evaluation source, and Python, but must
provision the matching native binary, immutable model export, OpenBLAS, PCRE2,
and a compatible glibc. Alpine/musl and other architectures are unsupported.
