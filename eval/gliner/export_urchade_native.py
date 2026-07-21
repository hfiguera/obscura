#!/usr/bin/env python3
"""Export the pinned Urchade GLiNER checkpoint for native Obscura inference."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import platform
import shutil
from pathlib import Path
from typing import Any

import safetensors
import torch
from gliner import GLiNER
from safetensors.torch import save_file


MODEL_ID = "urchade/gliner_multi_pii-v1"
MODEL_REVISION = "1fcf13e85f4eef5394e1fcd406cf2ca9ea82351d"
ENCODER_ID = "microsoft/mdeberta-v3-base"
ENCODER_REVISION = "a0484667b22365f84929a935b5e50a51f71f159d"
COPIED_ASSETS = [
    "added_tokens.json",
    "gliner_config.json",
    "special_tokens_map.json",
    "spm.model",
    "tokenizer.json",
    "tokenizer_config.json",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_record(path: Path) -> dict[str, Any]:
    return {"bytes": path.stat().st_size, "sha256": sha256(path)}


def tensor_record(tensor: torch.Tensor) -> dict[str, Any]:
    return {
        "dtype": str(tensor.dtype).removeprefix("torch."),
        "shape": list(tensor.shape),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--tokenizer-dir", type=Path, required=True)
    args = parser.parse_args()

    missing = [name for name in COPIED_ASSETS if not (args.tokenizer_dir / name).is_file()]
    if missing:
        raise RuntimeError(f"tokenizer export is incomplete: {missing}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(20260720)
    model = GLiNER.from_pretrained(
        MODEL_ID,
        revision=MODEL_REVISION,
        local_files_only=True,
    )
    model.eval()

    state = {
        name: tensor.detach().cpu().contiguous()
        for name, tensor in model.model.state_dict().items()
    }
    weights_path = args.output_dir / "model.safetensors"
    save_file(state, weights_path)

    for name in COPIED_ASSETS:
        shutil.copy2(args.tokenizer_dir / name, args.output_dir / name)

    manifest = {
        "schema_version": 1,
        "status": "experimental_native_export",
        "model": {"id": MODEL_ID, "revision": MODEL_REVISION, "license": "Apache-2.0"},
        "encoder": {
            "id": ENCODER_ID,
            "revision": ENCODER_REVISION,
            "license": "MIT",
        },
        "weights": {
            "file": weights_path.name,
            **file_record(weights_path),
            "tensor_count": len(state),
            "tensors": {
                name: tensor_record(tensor) for name, tensor in sorted(state.items())
            },
        },
        "assets": {
            name: file_record(args.output_dir / name) for name in COPIED_ASSETS
        },
        "environment": {
            "python": platform.python_version(),
            "gliner": importlib.metadata.version("gliner"),
            "torch": torch.__version__,
            "safetensors": safetensors.__version__,
            "platform": platform.platform(),
            "machine": platform.machine(),
        },
    }
    manifest_path = args.output_dir / "obscura_native_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"manifest": str(manifest_path), "status": "ok"}))


if __name__ == "__main__":
    main()
