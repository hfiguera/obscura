#!/usr/bin/env python3
"""Generate pinned Python oracles for the two native GLiNER feasibility spikes."""

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


def tensor_record(tensor: torch.Tensor) -> dict[str, Any]:
    array = np.ascontiguousarray(tensor.detach().cpu().numpy())
    return {
        "dtype": str(array.dtype),
        "shape": list(array.shape),
        "sha256": hashlib.sha256(array.tobytes()).hexdigest(),
    }


def clone_tensors(values: dict[str, torch.Tensor]) -> dict[str, torch.Tensor]:
    return {
        name: (
            value.to(torch.uint8)
            if value.dtype == torch.bool
            else value
        ).detach().cpu().contiguous().clone()
        for name, value in values.items()
    }


def prefixed_parameters(module: torch.nn.Module, prefix: str) -> dict[str, torch.Tensor]:
    return {
        f"{prefix}.{name}": parameter
        for name, parameter in module.named_parameters()
    }


def head_oracle(model: GLiNER, batch: dict[str, torch.Tensor]) -> dict[str, torch.Tensor]:
    core = model.model
    with torch.no_grad():
        token_embeddings = core.token_rep_layer(batch["input_ids"], batch["attention_mask"])
        prompts, prompt_mask, words, word_mask = (
            core._extract_prompt_features_and_word_embeddings(
                token_embeddings,
                batch["input_ids"],
                batch["attention_mask"],
                batch["text_lengths"],
                batch["words_mask"],
            )
        )
        rnn_output = core.rnn(words, word_mask)
        span_idx = batch["span_idx"] * batch["span_mask"].unsqueeze(-1)
        span_output = core.span_rep_layer(rnn_output, span_idx)
        prompt_output = core.prompt_rep_layer(prompts)
        logits = torch.einsum("BLKD,BCD->BLKC", span_output, prompt_output)

    tensors = {
        "head.input.words": words,
        "head.input.prompts": prompts,
        "head.input.span_idx": span_idx,
        "head.input.span_mask": batch["span_mask"],
        "head.expected.rnn": rnn_output,
        "head.expected.span": span_output,
        "head.expected.prompt": prompt_output,
        "head.expected.logits": logits,
    }
    tensors.update(prefixed_parameters(core.rnn, "head.param.rnn"))
    tensors.update(prefixed_parameters(core.span_rep_layer, "head.param.span"))
    tensors.update(prefixed_parameters(core.prompt_rep_layer, "head.param.prompt"))
    return clone_tensors(tensors)


def block_oracle(model: GLiNER, batch: dict[str, torch.Tensor]) -> dict[str, torch.Tensor]:
    bert = model.model.token_rep_layer.bert_layer.model
    encoder = bert.encoder
    layer = encoder.layer[0]

    with torch.no_grad():
        hidden = bert.embeddings(input_ids=batch["input_ids"])
        attention_mask = encoder.get_attention_mask(batch["attention_mask"])
        relative_pos = encoder.get_rel_pos(hidden)
        relative_embeddings = encoder.get_rel_embedding()
        self_context, attention_probs = layer.attention.self(
            hidden,
            attention_mask,
            output_attentions=True,
            relative_pos=relative_pos,
            rel_embeddings=relative_embeddings,
        )
        attention_output = layer.attention.output(self_context, hidden)
        intermediate = layer.intermediate(attention_output)
        output = layer.output(intermediate, attention_output)

    tensors = {
        "block.input.hidden": hidden,
        "block.input.attention_mask": attention_mask,
        "block.input.relative_pos": relative_pos,
        "block.input.relative_embeddings": relative_embeddings,
        "block.expected.self_context": self_context,
        "block.expected.attention_probs": attention_probs,
        "block.expected.attention_output": attention_output,
        "block.expected.intermediate": intermediate,
        "block.expected.output": output,
    }
    tensors.update(prefixed_parameters(layer, "block.param"))
    return clone_tensors(tensors)


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

    tensors = {}
    tensors.update(head_oracle(model, batch))
    tensors.update(block_oracle(model, batch))

    tensor_path = args.output_dir / "oracles.safetensors"
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
                name: tensor_record(tensor) for name, tensor in sorted(tensors.items())
            },
        },
    }
    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"manifest": str(manifest_path), "status": "ok"}))


if __name__ == "__main__":
    main()
