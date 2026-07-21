#!/usr/bin/env python3
"""Export the pinned Urchade GLiNER checkpoint and record its asset contract."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import platform
import sys
from pathlib import Path
from typing import Any

import gliner
import huggingface_hub
import onnx
import onnxruntime
import tokenizers
import torch
import transformers
from gliner import GLiNER
from huggingface_hub import snapshot_download


MODEL_ID = "urchade/gliner_multi_pii-v1"
MODEL_REVISION = "1fcf13e85f4eef5394e1fcd406cf2ca9ea82351d"
ENCODER_ID = "microsoft/mdeberta-v3-base"
ENCODER_REVISION = "a0484667b22365f84929a935b5e50a51f71f159d"
OPSET = 19

PINNED_VERSIONS = {
    "gliner": "0.2.27",
    "huggingface_hub": "0.36.2",
    "onnx": "1.22.0",
    "onnxruntime": "1.26.0",
    "tokenizers": "0.21.4",
    "torch": "2.12.0",
    "transformers": "4.53.3",
}

MODEL_FILES = ["README.md", "gliner_config.json", "pytorch_model.bin"]
ENCODER_FILES = ["README.md", "config.json", "spm.model", "tokenizer_config.json"]
GENERATED_FILES = [
    "added_tokens.json",
    "gliner_config.json",
    "model.onnx",
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


def package_versions() -> dict[str, str]:
    return {
        "gliner": importlib.metadata.version("gliner"),
        "huggingface_hub": huggingface_hub.__version__,
        "onnx": onnx.__version__,
        "onnxruntime": onnxruntime.__version__,
        "tokenizers": tokenizers.__version__,
        "torch": torch.__version__.split("+", 1)[0],
        "transformers": transformers.__version__,
    }


def verify_versions(actual: dict[str, str]) -> None:
    mismatches = {
        name: {"expected": expected, "actual": actual.get(name)}
        for name, expected in PINNED_VERSIONS.items()
        if actual.get(name) != expected
    }
    if mismatches:
        raise RuntimeError(f"unpinned export environment: {json.dumps(mismatches, sort_keys=True)}")


def file_manifest(root: Path, names: list[str]) -> dict[str, dict[str, Any]]:
    result = {}
    for name in names:
        path = root / name
        if path.exists():
            result[name] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
    return result


def value_info(value: Any) -> dict[str, Any]:
    tensor = value.type.tensor_type
    shape = [
        dimension.dim_param or dimension.dim_value for dimension in tensor.shape.dim
    ]
    return {"name": value.name, "dtype": tensor.elem_type, "shape": shape}


def onnx_contract(path: Path) -> dict[str, Any]:
    model = onnx.load(str(path), load_external_data=False)
    onnx.checker.check_model(model)
    return {
        "ir_version": model.ir_version,
        "opsets": [
            {"domain": item.domain, "version": item.version}
            for item in model.opset_import
        ],
        "inputs": [value_info(item) for item in model.graph.input],
        "outputs": [value_info(item) for item in model.graph.output],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--allow-download", action="store_true")
    parser.add_argument("--skip-version-check", action="store_true")
    args = parser.parse_args()

    versions = package_versions()
    if not args.skip_version_check:
        verify_versions(versions)

    local_only = not args.allow_download
    model_snapshot = Path(
        snapshot_download(
            MODEL_ID,
            revision=MODEL_REVISION,
            allow_patterns=MODEL_FILES,
            local_files_only=local_only,
        )
    )
    encoder_snapshot = Path(
        snapshot_download(
            ENCODER_ID,
            revision=ENCODER_REVISION,
            allow_patterns=ENCODER_FILES,
            local_files_only=local_only,
        )
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    model = GLiNER.from_pretrained(
        MODEL_ID,
        revision=MODEL_REVISION,
        local_files_only=local_only,
    )
    if type(model).__name__ != "UniEncoderSpanGLiNER":
        raise RuntimeError(f"unexpected GLiNER class: {type(model).__name__}")

    export_result = model.export_to_onnx(
        str(args.output_dir),
        onnx_filename="model.onnx",
        quantize=False,
        opset=OPSET,
    )

    missing = [name for name in GENERATED_FILES if not (args.output_dir / name).exists()]
    if missing:
        raise RuntimeError(f"export omitted required assets: {missing}")

    generated_config = json.loads(
        (args.output_dir / "gliner_config.json").read_text(encoding="utf-8")
    )
    manifest = {
        "schema_version": 1,
        "status": "experimental_local_export",
        "model": {
            "id": MODEL_ID,
            "revision": MODEL_REVISION,
            "license": "Apache-2.0",
            "files": file_manifest(model_snapshot, MODEL_FILES),
        },
        "encoder": {
            "id": ENCODER_ID,
            "revision": ENCODER_REVISION,
            "license": "MIT",
            "files": file_manifest(encoder_snapshot, ENCODER_FILES),
        },
        "export": {
            "opset": OPSET,
            "result": export_result,
            "files": file_manifest(args.output_dir, GENERATED_FILES),
            "onnx_contract": onnx_contract(args.output_dir / "model.onnx"),
            "config_contract": {
                "model_type": generated_config.get("model_type"),
                "span_mode": generated_config.get("span_mode"),
                "words_splitter_type": generated_config.get("words_splitter_type"),
                "max_width": generated_config.get("max_width"),
                "max_len": generated_config.get("max_len"),
                "model_name": generated_config.get("model_name"),
            },
            "tokenizer_derivation": {
                "method": "GLiNER export_to_onnx save_pretrained",
                "source": f"{ENCODER_ID}@{ENCODER_REVISION}",
                "warning": (
                    "Transformers converts the SentencePiece tokenizer to a fast "
                    "tokenizer; byte-fallback parity requires separate validation."
                ),
            },
        },
        "environment": {
            "packages": versions,
            "python": sys.version,
            "platform": platform.platform(),
            "machine": platform.machine(),
            "gliner_module": str(Path(gliner.__file__).resolve()),
        },
    }
    manifest_path = args.output_dir / "obscura_urchade_export_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps({"manifest": str(manifest_path), "status": "ok"}, sort_keys=True))


if __name__ == "__main__":
    main()
