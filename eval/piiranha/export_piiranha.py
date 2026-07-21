#!/usr/bin/env python3
"""Download a pinned Piiranha checkpoint and export it for local Ortex evaluation."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
from pathlib import Path
from typing import Any

import numpy
import onnx
import onnxruntime
import optimum
import tokenizers
import torch
import transformers
from huggingface_hub import snapshot_download
from optimum.exporters.onnx import main_export

MODEL_ID = "iiiorg/piiranha-v1-detect-personal-information"
REVISION = "255acde67a2f34cf452eb42e365b24d2957352fc"
ASSET_PATTERNS = [
    "config.json",
    "model.safetensors",
    "sentencepiece.bpe.model",
    "special_tokens_map.json",
    "spm.model",
    "tokenizer.json",
    "tokenizer_config.json",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", default=".cache/piiranha-v1-hf")
    parser.add_argument("--output-dir", default=".cache/piiranha-v1-onnx")
    parser.add_argument(
        "--reference", default="eval/piiranha/piiranha-export-reference.json"
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def version(module: Any) -> str:
    return str(getattr(module, "__version__", "unknown"))


def main() -> int:
    args = parse_args()
    source_dir = Path(args.source_dir)
    output_dir = Path(args.output_dir)
    source_dir.mkdir(parents=True, exist_ok=True)

    snapshot_download(
        MODEL_ID,
        revision=REVISION,
        local_dir=source_dir,
        allow_patterns=ASSET_PATTERNS,
    )

    if output_dir.exists():
        shutil.rmtree(output_dir)

    main_export(
        model_name_or_path=str(source_dir),
        output=output_dir,
        task="token-classification",
        do_validation=True,
        no_post_process=True,
    )

    required = [output_dir / name for name in ["model.onnx", "config.json", "tokenizer.json"]]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError(f"export omitted required assets: {missing}")

    model = onnx.load(output_dir / "model.onnx", load_external_data=False)
    onnx.checker.check_model(model)
    session = onnxruntime.InferenceSession(
        str(output_dir / "model.onnx"), providers=["CPUExecutionProvider"]
    )

    reference = {
        "model_id": MODEL_ID,
        "revision": REVISION,
        "license": "cc-by-nc-nd-4.0",
        "redistribution": "Local evaluation only; do not commit or redistribute converted weights.",
        "source_dir": str(source_dir),
        "output_dir": str(output_dir),
        "assets": {
            path.name: {"sha256": sha256(path), "bytes": path.stat().st_size}
            for path in required
        },
        "onnx": {
            "ir_version": model.ir_version,
            "opset": [{"domain": item.domain, "version": item.version} for item in model.opset_import],
            "inputs": [item.name for item in session.get_inputs()],
            "outputs": [item.name for item in session.get_outputs()],
            "providers": session.get_providers(),
        },
        "environment": {
            "python": platform.python_version(),
            "numpy": version(numpy),
            "onnx": version(onnx),
            "onnxruntime": version(onnxruntime),
            "optimum": version(optimum),
            "tokenizers": version(tokenizers),
            "torch": version(torch),
            "transformers": version(transformers),
        },
    }

    reference_path = Path(args.reference)
    reference_path.parent.mkdir(parents=True, exist_ok=True)
    reference_path.write_text(json.dumps(reference, indent=2, sort_keys=True) + "\n")
    print(json.dumps(reference, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
