# Urchade GLiNER Export

These tools reproducibly export `urchade/gliner_multi_pii-v1` for the optional
`Obscura.Recognizer.GLiNER.Ortex` adapter. Model assets are local runtime
inputs and must not be committed.

Create an isolated environment and export the pinned revision:

```bash
python3 -m venv .gliner-export-venv
source .gliner-export-venv/bin/activate
python -m pip install -r eval/gliner/requirements-urchade-export.lock
python eval/gliner/export_urchade.py \
  --allow-download \
  --output-dir "$HOME/.cache/obscura/urchade-gliner-multi-pii-v1"
```

The output directory contains the ONNX model, tokenizer assets, GLiNER
configuration, and `obscura_urchade_export_manifest.json`. The manifest records
immutable source revisions, source and generated asset hashes, package
versions, ONNX input/output names and shapes, and the tokenizer derivation.

## NVIDIA GLiNER PII Export

`nvidia/gliner-PII` is a separate, larger experimental checkpoint. Export its
pinned revision with:

```bash
python3 -m venv .gliner-nvidia-venv
source .gliner-nvidia-venv/bin/activate
python -m pip install -r eval/gliner/requirements-nvidia-export.lock
python eval/gliner/export_nvidia.py \
  --allow-download \
  --output-dir .cache/nvidia-gliner-export
```

Generate the Python PyTorch/ONNX parity corpus:

```bash
python eval/gliner/generate_nvidia_parity.py \
  --model-dir .cache/nvidia-gliner-export \
  --output eval/gliner/nvidia-parity-reference.json
```

Run the native parity test:

```bash
OBSCURA_GLINER_ORTEX=1 \
OBSCURA_GLINER_NVIDIA_MODEL_DIR=.cache/nvidia-gliner-export \
mix test --include gliner_nvidia \
  test/obscura/recognizer/gliner/nvidia_parity_test.exs
```

The source and generated hashes are in
`eval/gliner/nvidia-export-reference.json`. Do not commit the 1.78 GB ONNX
graph or checkpoint. The validation result and rejected promotion decision are
recorded in `nvidia-export-reference.json` and the generated parity artifacts.

On Apple Silicon, an x86 Rust toolchain may cross-compile Ortex incorrectly for
the arm64 BEAM. Compile the optional dependency explicitly for arm64:

```bash
OBSCURA_GLINER_ORTEX=1 \
CARGO_BUILD_TARGET=aarch64-apple-darwin \
mix deps.compile ortex --force
```
