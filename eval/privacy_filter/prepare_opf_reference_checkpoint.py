#!/usr/bin/env python3
"""Prepare Hugging Face privacy-filter checkpoints for the Python OPF runtime.

OpenMed/privacy-filter-nemotron publishes a Hugging Face-style
`openai_privacy_filter` config. The local OPF runtime in
`inspiration/privacy-filter` expects its internal `privacy_filter` encoder
artifact contract. This helper creates a reproducible reference view without
mutating the downloaded checkpoint:

* normalized `config.json`
* symlinked internal `.safetensors` files, or materialized internal tensor
  names when the source checkpoint uses Hugging Face naming
* symlinked optional `viterbi_calibration.json`
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create an OPF-compatible reference checkpoint view."
    )
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--encoding", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = prepare_checkpoint(
        Path(args.checkpoint),
        Path(args.out),
        encoding=args.encoding,
    )
    print(json.dumps(summary, sort_keys=True))
    return 0


def prepare_checkpoint(
    checkpoint: Path,
    output: Path,
    *,
    encoding: str | None = None,
) -> dict[str, Any]:
    checkpoint = checkpoint.resolve()
    output.mkdir(parents=True, exist_ok=True)

    config_path = checkpoint / "config.json"
    if not config_path.is_file():
        raise FileNotFoundError(f"missing checkpoint config: {config_path}")

    safetensors = sorted(checkpoint.glob("*.safetensors"))
    if not safetensors:
        raise FileNotFoundError(f"checkpoint has no .safetensors files: {checkpoint}")

    payload = json.loads(config_path.read_text(encoding="utf-8"))
    normalized = normalize_config(payload, encoding=encoding)
    (output / "config.json").write_text(
        json.dumps(normalized, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    weight_summary = prepare_weights(checkpoint, output, normalized, safetensors)

    calibration = checkpoint / "viterbi_calibration.json"
    if calibration.is_file():
        link_file(calibration, output / calibration.name)

    return {
        "checkpoint": str(checkpoint),
        "output": str(output),
        "model_type": normalized.get("model_type"),
        "encoding": normalized.get("encoding"),
        "num_labels": normalized.get("num_labels"),
        "ner_class_names": len(normalized.get("ner_class_names", [])),
        "weights": weight_summary,
    }


def normalize_config(payload: dict[str, Any], *, encoding: str | None = None) -> dict[str, Any]:
    normalized = dict(payload)
    hf_privacy_filter = normalized.get("model_type") == "openai_privacy_filter"

    if hf_privacy_filter:
        normalized["model_type"] = "privacy_filter"

    if not normalized.get("encoding"):
        inferred_encoding = encoding or infer_encoding(normalized)
        if inferred_encoding:
            normalized["encoding"] = inferred_encoding

    put_new_from(normalized, "num_experts", "num_local_experts")
    put_new_from(normalized, "experts_per_token", "num_experts_per_tok")

    if "num_labels" not in normalized and isinstance(normalized.get("id2label"), dict):
        normalized["num_labels"] = len(normalized["id2label"])

    rope = normalized.get("rope_parameters")
    if isinstance(rope, dict):
        normalized.setdefault("rope_theta", rope.get("rope_theta"))
        normalized.setdefault("rope_scaling_factor", rope.get("factor"))
        normalized.setdefault("rope_ntk_alpha", rope.get("beta_slow"))
        normalized.setdefault("rope_ntk_beta", rope.get("beta_fast"))
        normalized.setdefault("initial_context_length", rope.get("original_max_position_embeddings"))

    if "bidirectional_context" not in normalized and isinstance(
        normalized.get("sliding_window"), int
    ):
        context = normalized["sliding_window"]
        normalized["bidirectional_context"] = True
        normalized["bidirectional_left_context"] = context
        normalized["bidirectional_right_context"] = context
        normalized["sliding_window"] = context * 2 + 1

    if "ner_class_names" not in normalized and isinstance(normalized.get("id2label"), dict):
        normalized["ner_class_names"] = [
            label
            for _index, label in sorted(
                normalized["id2label"].items(),
                key=lambda item: int(item[0]),
            )
        ]

    put_new_from(normalized, "param_dtype", "dtype")

    return normalized


def infer_encoding(payload: dict[str, Any]) -> str | None:
    if payload.get("pad_token_id") == 199_999:
        return "o200k_base"
    return None


def put_new_from(payload: dict[str, Any], target: str, source: str) -> None:
    if target not in payload and source in payload:
        payload[target] = payload[source]


def link_file(source: Path, target: Path) -> None:
    if target.exists() or target.is_symlink():
        if target.resolve() == source.resolve():
            return
        target.unlink()

    relative_source = os.path.relpath(source, target.parent)
    target.symlink_to(relative_source)


def prepare_weights(
    checkpoint: Path,
    output: Path,
    config: dict[str, Any],
    safetensors: list[Path],
) -> dict[str, Any]:
    if checkpoint_has_internal_names(safetensors):
        linked = []
        for source in safetensors:
            target = output / source.name
            link_file(source, target)
            linked.append(source.name)

        return {"layout": "internal", "mode": "symlink", "files": linked}

    target = output / "model.safetensors"
    if checkpoint_has_internal_names([target]):
        return {"layout": "hf_materialized", "mode": "reuse", "files": [target.name]}

    if target.exists() or target.is_symlink():
        target.unlink()

    write_internal_safetensors(checkpoint, target, config)
    return {"layout": "hf_materialized", "mode": "write", "files": [target.name]}


def checkpoint_has_internal_names(safetensors: list[Path]) -> bool:
    if not safetensors:
        return False

    try:
        from safetensors import safe_open
    except Exception:
        return False

    for source in safetensors:
        if not source.exists():
            continue
        try:
            with safe_open(str(source), framework="pt", device="cpu") as handle:
                keys = set(handle.keys())
            if "embedding.weight" in keys and "unembedding.weight" in keys:
                return True
        except Exception:
            continue

    return False


def write_internal_safetensors(checkpoint: Path, target: Path, config: dict[str, Any]) -> None:
    try:
        import torch
        from safetensors.torch import load_file, save_file
    except Exception as error:
        raise RuntimeError(
            "materializing an OPF reference checkpoint requires torch and safetensors"
        ) from error

    source_path = checkpoint / "model.safetensors"
    if not source_path.is_file():
        raise FileNotFoundError(f"missing source model.safetensors: {source_path}")

    source = load_file(str(source_path), device="cpu")
    tensors: dict[str, torch.Tensor] = {
        "embedding.weight": source["model.embed_tokens.weight"],
        "norm.scale": source["model.norm.weight"],
        "unembedding.weight": source["score.weight"],
    }

    if "score.bias" in source:
        tensors["unembedding.bias"] = source["score.bias"]

    layers = int(config["num_hidden_layers"])
    for layer in range(layers):
        hf_attn = f"model.layers.{layer}.self_attn"
        hf_mlp = f"model.layers.{layer}.mlp"
        block_attn = f"block.{layer}.attn"
        block_mlp = f"block.{layer}.mlp"

        tensors[f"{block_attn}.norm.scale"] = source[
            f"model.layers.{layer}.input_layernorm.weight"
        ]
        tensors[f"{block_attn}.sinks"] = source[f"{hf_attn}.sinks"]
        tensors[f"{block_attn}.qkv.weight"] = torch.cat(
            [
                source[f"{hf_attn}.q_proj.weight"],
                source[f"{hf_attn}.k_proj.weight"],
                source[f"{hf_attn}.v_proj.weight"],
            ],
            dim=0,
        )
        tensors[f"{block_attn}.qkv.bias"] = torch.cat(
            [
                source[f"{hf_attn}.q_proj.bias"],
                source[f"{hf_attn}.k_proj.bias"],
                source[f"{hf_attn}.v_proj.bias"],
            ],
            dim=0,
        )
        tensors[f"{block_attn}.out.weight"] = source[f"{hf_attn}.o_proj.weight"]
        tensors[f"{block_attn}.out.bias"] = source[f"{hf_attn}.o_proj.bias"]

        tensors[f"{block_mlp}.norm.scale"] = source[
            f"model.layers.{layer}.post_attention_layernorm.weight"
        ]
        tensors[f"{block_mlp}.gate.weight"] = source[f"{hf_mlp}.router.weight"]
        tensors[f"{block_mlp}.gate.bias"] = source[f"{hf_mlp}.router.bias"]
        tensors[f"{block_mlp}.swiglu.weight"] = source[f"{hf_mlp}.experts.gate_up_proj"]
        tensors[f"{block_mlp}.swiglu.bias"] = source[f"{hf_mlp}.experts.gate_up_proj_bias"]
        tensors[f"{block_mlp}.out.weight"] = source[f"{hf_mlp}.experts.down_proj"]
        tensors[f"{block_mlp}.out.bias"] = source[f"{hf_mlp}.experts.down_proj_bias"]

    save_file(tensors, str(target))


if __name__ == "__main__":
    raise SystemExit(main())
