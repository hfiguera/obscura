#!/usr/bin/env python3
"""Record a complete pinned Python GLiNER trace for native parity validation."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import platform
from pathlib import Path
from typing import Any

import numpy as np
import safetensors
import torch
import transformers
from gliner import GLiNER
from safetensors.torch import save_file


MODEL_ID = "urchade/gliner_multi_pii-v1"
MODEL_REVISION = "1fcf13e85f4eef5394e1fcd406cf2ca9ea82351d"
TEXT = "Rachel works at Google in Paris."
LABELS = ["person", "organization", "location"]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def clone(tensor: torch.Tensor) -> torch.Tensor:
    if tensor.dtype == torch.bool:
        tensor = tensor.to(torch.uint8)
    return tensor.detach().cpu().contiguous().clone()


def record(tensor: torch.Tensor) -> dict[str, Any]:
    array = np.ascontiguousarray(tensor.detach().cpu().numpy())
    return {
        "dtype": str(array.dtype),
        "shape": list(array.shape),
        "sha256": hashlib.sha256(array.tobytes()).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    torch.manual_seed(20260720)
    model = GLiNER.from_pretrained(
        MODEL_ID,
        revision=MODEL_REVISION,
        local_files_only=True,
    )
    model.eval()
    batch = model._build_dummy_batch(labels=LABELS, text=TEXT)
    core = model.model
    bert = core.token_rep_layer.bert_layer.model

    with torch.no_grad():
        encoder = bert(
            input_ids=batch["input_ids"],
            attention_mask=batch["attention_mask"],
            output_hidden_states=True,
            return_dict=True,
        )
        projected = core.token_rep_layer.projection(encoder.last_hidden_state)
        prompts, prompt_mask, words, word_mask = (
            core._extract_prompt_features_and_word_embeddings(
                projected,
                batch["input_ids"],
                batch["attention_mask"],
                batch["text_lengths"],
                batch["words_mask"],
            )
        )
        rnn = core.rnn(words, word_mask)
        span_idx = batch["span_idx"] * batch["span_mask"].unsqueeze(-1)
        span = core.span_rep_layer(rnn, span_idx)
        prompt = core.prompt_rep_layer(prompts)
        logits = torch.einsum("BLKD,BCD->BLKC", span, prompt)

    tensors = {
        "input.input_ids": batch["input_ids"],
        "input.attention_mask": batch["attention_mask"],
        "input.words_mask": batch["words_mask"],
        "input.text_lengths": batch["text_lengths"],
        "input.span_idx": batch["span_idx"],
        "input.span_mask": batch["span_mask"],
        "expected.embedding": encoder.hidden_states[0],
        "expected.projected": projected,
        "expected.prompts": prompts,
        "expected.words": words,
        "expected.rnn": rnn,
        "expected.span": span,
        "expected.prompt": prompt,
        "expected.logits": logits,
    }
    for index, hidden in enumerate(encoder.hidden_states[1:]):
        tensors[f"expected.layer.{index}"] = hidden

    tensors = {name: clone(tensor) for name, tensor in tensors.items()}
    tensor_path = args.output_dir / "full_oracle.safetensors"
    save_file(tensors, tensor_path)

    manifest = {
        "schema_version": 1,
        "model": {"id": MODEL_ID, "revision": MODEL_REVISION},
        "input": {"text": TEXT, "labels": LABELS},
        "environment": {
            "python": platform.python_version(),
            "gliner": importlib.metadata.version("gliner"),
            "torch": torch.__version__,
            "transformers": transformers.__version__,
            "safetensors": safetensors.__version__,
        },
        "oracle": {
            "file": tensor_path.name,
            "sha256": sha256(tensor_path),
            "bytes": tensor_path.stat().st_size,
            "tensors": {
                name: record(tensor) for name, tensor in sorted(tensors.items())
            },
        },
    }
    manifest_path = args.output_dir / "full_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"manifest": str(manifest_path), "status": "ok"}))


if __name__ == "__main__":
    main()
