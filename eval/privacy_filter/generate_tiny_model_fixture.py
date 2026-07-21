#!/usr/bin/env python3
"""Generate a tiny Python OPF model-forward parity fixture."""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path
from typing import Any

import torch
import torch.nn.functional as F
import tiktoken


ROOT = Path(__file__).resolve().parents[2]
PRIVACY_FILTER_SOURCE = ROOT / "inspiration" / "privacy-filter"
DEFAULT_OUTPUT = ROOT / "eval" / "privacy_filter" / "fixtures" / "tiny_model_parity.json"
PYTHON_ORIGINAL_RUNTIME_OUTPUT = (
    ROOT / "eval" / "privacy_filter" / "fixtures" / "python_original_runtime_reference.json"
)
PYTHON_ORIGINAL_QKV_MICRO_OUTPUT = (
    ROOT / "eval" / "privacy_filter" / "fixtures" / "python_original_qkv_micro.json"
)
sys.path.insert(0, str(PRIVACY_FILTER_SOURCE))

from opf._common.label_space import resolve_label_space_from_config  # noqa: E402
from opf._core.decoding import (  # noqa: E402
    resolve_viterbi_biases_from_calibration_path,
    ViterbiCRFDecoder,
    zero_viterbi_transition_biases,
)
from opf._core.runtime import load_inference_runtime  # noqa: E402
from opf._core.sequence_labeling import TokenizedExample, build_label_info, example_to_windows  # noqa: E402
from opf._core.spans import (  # noqa: E402
    decode_text_with_offsets,
    discard_overlapping_spans_by_label,
    labels_to_spans,
    token_spans_to_char_spans,
    trim_char_spans_whitespace,
)
from opf._model.model import ModelConfig, Transformer, sdpa, swiglu  # noqa: E402


def main() -> int:
    os.environ["OPF_MOE_TRITON"] = "0"
    torch.manual_seed(0)
    torch.set_float32_matmul_precision("highest")

    config = ModelConfig(
        model_type="privacy_filter",
        num_hidden_layers=1,
        num_experts=2,
        experts_per_token=1,
        vocab_size=5,
        num_labels=3,
        hidden_size=4,
        intermediate_size=2,
        swiglu_limit=7.0,
        packed_geglu=False,
        head_dim=2,
        num_attention_heads=2,
        num_key_value_heads=1,
        sliding_window=3,
        bidirectional_context=True,
        bidirectional_left_context=1,
        bidirectional_right_context=1,
        initial_context_length=16,
        rope_theta=10000.0,
        rope_scaling_factor=1.0,
        rope_ntk_alpha=1.0,
        rope_ntk_beta=32.0,
        torch_ops_batch=32,
        param_dtype="float32",
    )

    model = Transformer(config, device=torch.device("cpu"))
    model.eval()
    params = deterministic_params()
    assign_params(model, params)

    token_ids = torch.tensor([[0, 1, 2]], dtype=torch.long)
    with torch.inference_mode():
        logits = model(token_ids).detach().cpu()
        stages = debug_forward(model, token_ids)

    python_original = python_original_reference()

    output = {
        "source": "inspiration/privacy-filter/opf/_model/model.py",
        "description": "Tiny deterministic one-block OPF Transformer parity fixture.",
        "config": config_payload(config),
        "token_ids": token_ids.tolist(),
        "windows": tiny_windows(token_ids.squeeze(0).tolist(), window_size=2),
        "params": {name: tensor.detach().cpu().tolist() for name, tensor in params.items()},
        "python_logits": logits.tolist(),
        "python_stages": tensor_tree_to_json(stages),
        "postprocessing": postprocessing_fixture(),
        "real_checkpoint_reference": real_checkpoint_reference(),
        "python_original_reference": python_original,
        "tolerance": {"atol": 1.0e-4, "rtol": 1.0e-4},
    }

    DEFAULT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_OUTPUT.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    PYTHON_ORIGINAL_RUNTIME_OUTPUT.write_text(
        json.dumps(without_model_stages(python_original), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(DEFAULT_OUTPUT)
    print(PYTHON_ORIGINAL_RUNTIME_OUTPUT)
    return 0


def debug_forward(
    model: Transformer,
    token_ids: torch.Tensor,
    *,
    attention_mask: torch.Tensor | None = None,
) -> dict[str, Any]:
    embedding = model.embedding(token_ids)
    hidden = embedding
    blocks = []

    for block in model.block:
        block_debug = debug_block(block, hidden, attention_mask=attention_mask)
        blocks.append(block_debug)
        hidden = block_debug["output"]

    final_norm = model.norm(hidden)
    logits = F.linear(final_norm, model.unembedding.weight, None)

    return {
        "embedding": embedding,
        "blocks": blocks,
        "final_norm": final_norm,
        "logits": logits,
    }


def debug_block(
    block,
    hidden: torch.Tensor,
    *,
    attention_mask: torch.Tensor | None = None,
) -> dict[str, Any]:
    attention = debug_attention(block.attn, hidden, attention_mask=attention_mask)
    mlp = debug_mlp(block.mlp, attention["output"])
    return {"input": hidden, "attention": attention, "mlp": mlp, "output": mlp["output"]}


def debug_attention(
    attn,
    x: torch.Tensor,
    *,
    attention_mask: torch.Tensor | None = None,
) -> dict[str, torch.Tensor]:
    t = attn.norm(x)
    if t.dtype != attn.qkv.weight.dtype:
        t = t.to(attn.qkv.weight.dtype)

    qkv = F.linear(t, attn.qkv.weight, attn.qkv.bias)
    q_width = attn.num_attention_heads * attn.head_dim
    kv_width = attn.num_key_value_heads * attn.head_dim
    q = qkv[:, :, :q_width].contiguous()
    k = qkv[:, :, q_width : q_width + kv_width].contiguous()
    v = qkv[:, :, q_width + kv_width : q_width + kv_width + kv_width].contiguous()

    q_rotary, k_rotary = attn.rope(q, k)
    q_scaled = q_rotary * attn.qk_scale
    k_scaled = k_rotary * attn.qk_scale
    bsz, n_tokens, _ = q_scaled.shape

    q_view = q_scaled.view(
        bsz,
        n_tokens,
        attn.num_key_value_heads,
        attn.num_attention_heads // attn.num_key_value_heads,
        attn.head_dim,
    )
    k_view = k_scaled.view(bsz, n_tokens, attn.num_key_value_heads, attn.head_dim)
    v_view = v.view(bsz, n_tokens, attn.num_key_value_heads, attn.head_dim)

    attn_debug = debug_sdpa(
        q_view,
        k_view,
        v_view,
        attn.sinks,
        attn.sm_scale,
        attn.sliding_window,
        attention_mask=attention_mask,
        bidirectional_context=attn.bidirectional_context,
        bidirectional_left_context=attn.bidirectional_left_context,
        bidirectional_right_context=attn.bidirectional_right_context,
    )
    attn_out = attn_debug["output"]

    if attn_out.dtype != attn.out.weight.dtype:
        attn_out = attn_out.to(attn.out.weight.dtype)
    projection = F.linear(attn_out, attn.out.weight, attn.out.bias)
    projection = projection.to(x.dtype)
    output = x + projection

    return {
        "normalized": t,
        "qkv": qkv,
        "query_rotary": q_rotary,
        "key_rotary": k_rotary,
        "value": v,
        "query_scaled": q_scaled,
        "key_scaled": k_scaled,
        "attention_scores": attn_debug["scores"],
        "attention_weights": attn_debug["weights"],
        "attention": attn_out,
        "projection": projection,
        "output": output,
    }


def debug_sdpa(
    Q,
    K,
    V,
    S,
    sm_scale,
    sliding_window=0,
    *,
    attention_mask: torch.Tensor | None = None,
    bidirectional_context=False,
    bidirectional_left_context=0,
    bidirectional_right_context=0,
) -> dict[str, torch.Tensor]:
    if Q.dim() != 5:
        raise ValueError(
            "debug_sdpa expects batched Q with shape [batch, tokens, heads, q_mult, d_head]"
        )
    bsz, n_tokens, n_heads, q_mult, d_head = Q.shape
    assert K.shape == (bsz, n_tokens, n_heads, d_head)
    assert V.shape == (bsz, n_tokens, n_heads, d_head)
    if attention_mask is not None:
        attention_mask = attention_mask.to(device=Q.device, dtype=torch.bool)

    if bidirectional_context or sliding_window > 0:
        left_ctx = int(bidirectional_left_context) if bidirectional_context else int(sliding_window)
        right_ctx = int(bidirectional_right_context) if bidirectional_context else 0
        window = left_ctx + right_ctx + 1
        Kp = F.pad(K, (0, 0, 0, 0, left_ctx, right_ctx))
        Vp = F.pad(V, (0, 0, 0, 0, left_ctx, right_ctx))
        Kwin = Kp.unfold(1, window, 1).permute(0, 1, 4, 2, 3)
        Vwin = Vp.unfold(1, window, 1).permute(0, 1, 4, 2, 3)
        idx = torch.arange(window, device=Q.device) - left_ctx
        pos = torch.arange(n_tokens, device=Q.device)[:, None] + idx[None, :]
        valid = (pos >= 0) & (pos < n_tokens)
        scores = torch.einsum("bthqd,btwhd->bthqw", Q, Kwin).float()
        scores *= sm_scale
        score_valid = valid[None, :, None, None, :]
        if attention_mask is not None:
            padded_valid = F.pad(attention_mask, (left_ctx, right_ctx), value=False)
            key_valid = padded_valid.unfold(1, window, 1)
            score_valid = score_valid & key_valid[:, :, None, None, :]
        scores = scores.masked_fill(~score_valid, -float("inf"))
        sink_scores = (S * math.log(2.0)).reshape(n_heads, q_mult)
        sink_scores = sink_scores[None, None, :, :, None].expand(bsz, n_tokens, -1, -1, 1)
        scores = torch.cat([scores, sink_scores], dim=-1)
        weights = torch.softmax(scores, dim=-1)
        value_weights = weights[..., :-1].to(V.dtype)
        attn = torch.einsum("bthqw,btwhd->bthqd", value_weights, Vwin)
        return {
            "scores": scores.masked_fill(torch.isneginf(scores), -1.0e9),
            "weights": weights,
            "output": attn.reshape(bsz, n_tokens, -1),
        }

    output = sdpa(
        Q,
        K,
        V,
        S,
        sm_scale,
        sliding_window,
        attention_mask=attention_mask,
        bidirectional_context=bidirectional_context,
        bidirectional_left_context=bidirectional_left_context,
        bidirectional_right_context=bidirectional_right_context,
    )
    return {
        "scores": torch.empty(0, dtype=torch.float32, device=Q.device),
        "weights": torch.empty(0, dtype=torch.float32, device=Q.device),
        "output": output,
    }


def debug_mlp(mlp, x: torch.Tensor) -> dict[str, torch.Tensor]:
    batch_shape = x.shape[:-1]
    normalized = mlp.norm(x)
    flat = normalized.reshape(-1, x.shape[-1])
    gate_logits = F.linear(flat.float(), mlp.gate.weight.float(), mlp.gate.bias.float())
    experts = torch.topk(gate_logits, k=mlp.experts_per_token, dim=-1, sorted=True)
    expert_scores = experts.values
    expert_indices = experts.indices
    expert_weights = torch.nn.functional.softmax(expert_scores, dim=1)
    effective_expert_weights = expert_weights / mlp.experts_per_token

    t_expanded = flat.float().unsqueeze(1).expand(-1, expert_indices.shape[1], -1)
    mlp1_weight = mlp.mlp1_weight[expert_indices, ...].float()
    mlp1_bias = mlp.mlp1_bias[expert_indices, ...].float()
    hidden = batched_linear(t_expanded, mlp1_weight, mlp1_bias)
    hidden = swiglu(hidden, limit=mlp.swiglu_limit, packed=mlp.packed_geglu)

    mlp2_weight = mlp.mlp2_weight[expert_indices, ...].float()
    mlp2_bias = mlp.mlp2_bias[expert_indices, ...].float()
    expert_out = batched_linear(hidden.float(), mlp2_weight, mlp2_bias)
    expert_out = torch.einsum("bec,be->bc", expert_out, effective_expert_weights)
    expert_out = expert_out * mlp.experts_per_token
    expert_output = expert_out.reshape(*batch_shape, -1).to(x.dtype)
    output = x + expert_output

    return {
        "normalized": normalized,
        "flat": flat,
        "gate_logits": gate_logits,
        "expert_scores": expert_scores,
        "expert_indices": expert_indices,
        "expert_weights": expert_weights,
        "expert_output": expert_output,
        "output": output,
    }


def batched_linear(x: torch.Tensor, weight: torch.Tensor, bias: torch.Tensor) -> torch.Tensor:
    bsz, experts, k_dim = x.shape
    _, _, _, o_dim = weight.shape
    output = torch.bmm(
        x.reshape(bsz * experts, 1, k_dim),
        weight.reshape(bsz * experts, k_dim, o_dim),
    ).reshape(bsz, experts, o_dim)
    return output + bias


def postprocessing_fixture() -> dict[str, Any]:
    class_names = [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person",
        "B-private_email",
        "I-private_email",
        "E-private_email",
        "S-private_email",
    ]
    label_info = build_label_info(class_names)
    rows = [
        [-10.0, 8.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0],
        [-10.0, -10.0, -10.0, 8.0, -10.0, -10.0, -10.0, -10.0, -10.0],
        [8.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0],
        [-10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, 8.0],
    ]
    decoder = ViterbiCRFDecoder(label_info, **zero_viterbi_transition_biases())
    decoded_labels = decoder.decode(torch.tensor(rows, dtype=torch.float32))
    labels_by_index = {idx: label for idx, label in enumerate(decoded_labels)}
    token_spans = labels_to_spans(labels_by_index, label_info)
    text = "Ada Lovelace x ada@example.com"
    char_starts = [0, 4, 13, 15]
    char_ends = [3, 12, 14, len(text)]
    char_spans = token_spans_to_char_spans(token_spans, char_starts, char_ends)
    trimmed = trim_char_spans_whitespace(char_spans, text)
    kept = discard_overlapping_spans_by_label(trimmed)

    return {
        "text": text,
        "class_names": class_names,
        "token_logprobs": rows,
        "decoded_labels": decoded_labels,
        "labels_by_index": {str(key): value for key, value in labels_by_index.items()},
        "char_starts": char_starts,
        "char_ends": char_ends,
        "token_spans": [list(span) for span in token_spans],
        "char_spans": [list(span) for span in char_spans],
        "trimmed_char_spans": [list(span) for span in trimmed],
        "kept_char_spans": [list(span) for span in kept],
        "mapped_entities": [
            {
                "label": label_info.span_class_names[label_idx],
                "entity": "person" if label_info.span_class_names[label_idx] == "private_person" else "email",
                "start": start,
                "end": end,
                "text": text[start:end],
            }
            for label_idx, start, end in kept
        ],
    }


def tiny_windows(token_ids: list[int], window_size: int) -> list[dict[str, Any]]:
    example = TokenizedExample(
        tokens=tuple(token_ids),
        labels=tuple(0 for _ in token_ids),
        example_id="tiny-model",
        text="tiny"
    )

    return [
        {
            "example_id": window.example_id,
            "tokens": list(window.tokens),
            "labels": list(window.labels),
            "offsets": list(window.offsets),
            "token_example_ids": list(window.token_example_ids),
            "mask": list(window.mask),
        }
        for window in example_to_windows(example, window_size)
    ]


def real_checkpoint_reference() -> dict[str, Any]:
    text = "Ada Lovelace can be reached at ada@example.com or 415-555-0199."
    encoding_name = "o200k_base"
    encoding = tiktoken.get_encoding(encoding_name)
    token_ids = encoding.encode(text, allowed_special="all")

    return {
        "checkpoint": ".cache/privacy-filter/openai",
        "encoding": encoding_name,
        "text": text,
        "n_ctx": 128,
        "token_ids": token_ids,
        "windows": tiny_windows(token_ids, window_size=128),
        "full_logits_status": "not_compared",
        "full_logits_reason": (
            "Python OPF loads the original/ checkpoint contract while Obscura native "
            "loads the Hugging Face root checkpoint contract. Real-checkpoint logits "
            "should be compared only after a same-effective-weight loader or converter "
            "proves both runtimes consume identical tensors."
        ),
    }


def python_original_reference() -> dict[str, Any]:
    checkpoint = ROOT / ".cache" / "privacy-filter" / "openai-original"
    text = "Ada Lovelace can be reached at ada@example.com or 415-555-0199."
    n_ctx = 128

    required = [
        checkpoint / "config.json",
        checkpoint / "dtypes.json",
        checkpoint / "model.safetensors",
        checkpoint / "viterbi_calibration.json",
    ]

    if not all(path.exists() for path in required):
        return {
            "status": "skipped",
            "checkpoint": ".cache/privacy-filter/openai-original",
            "reason": "python-original checkpoint files are not all present",
        }

    os.environ["OPF_MOE_TRITON"] = "0"

    runtime = load_inference_runtime(
        checkpoint=str(checkpoint),
        device_name="cpu",
        n_ctx_override=n_ctx,
        trim_span_whitespace=True,
        discard_overlapping_predicted_spans=True,
        output_mode="typed",
    )

    token_ids = tuple(int(tok) for tok in runtime.encoding.encode(text, allowed_special="all"))
    background = int(runtime.label_info.background_token_label)
    example = TokenizedExample(
        tokens=token_ids,
        labels=tuple(background for _ in token_ids),
        example_id="python-original-reference",
        text=text,
    )
    windows = list(example_to_windows(example, n_ctx))
    first_window = windows[0]
    window_tokens = torch.tensor([list(first_window.tokens)], device=runtime.device, dtype=torch.int32)
    attention_mask = torch.ones_like(window_tokens, dtype=torch.bool)

    with torch.inference_mode():
        logits = runtime.model(window_tokens, attention_mask=attention_mask).float().cpu()
        stages = debug_forward(runtime.model, window_tokens, attention_mask=attention_mask)

    qkv_micro = python_original_qkv_micro(runtime.model, stages, checkpoint, text, n_ctx)
    PYTHON_ORIGINAL_QKV_MICRO_OUTPUT.write_text(
        json.dumps(qkv_micro, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    log_probs = F.log_softmax(logits, dim=-1)[0].cpu()
    biases = resolve_viterbi_biases_from_calibration_path(str(checkpoint / "viterbi_calibration.json"))
    decoder = ViterbiCRFDecoder(runtime.label_info, **biases)
    decoded_labels = decoder.decode(log_probs)
    labels_by_index = {idx: label for idx, label in enumerate(decoded_labels)}
    token_spans = labels_to_spans(labels_by_index, runtime.label_info)
    decoded_text, char_starts, char_ends = decode_text_with_offsets(token_ids, runtime.encoding)
    char_spans = token_spans_to_char_spans(token_spans, char_starts, char_ends)
    trimmed = trim_char_spans_whitespace(char_spans, decoded_text)
    kept = discard_overlapping_spans_by_label(trimmed)

    with (checkpoint / "config.json").open("r", encoding="utf-8") as handle:
        config_payload = json.load(handle)
    _version, _span_class_names, ner_class_names = resolve_label_space_from_config(
        config_payload,
        context=str(checkpoint / "config.json"),
    )

    return {
        "status": "completed",
        "checkpoint": ".cache/privacy-filter/openai-original",
        "encoding": runtime.active_encoding_name,
        "text": text,
        "n_ctx": n_ctx,
        "token_ids": list(token_ids),
        "windows": [
            {
                "example_id": window.example_id,
                "tokens": list(window.tokens),
                "labels": list(window.labels),
                "offsets": list(window.offsets),
                "token_example_ids": list(window.token_example_ids),
                "mask": list(window.mask),
            }
            for window in windows
        ],
        "ner_class_names": list(ner_class_names),
        "logits": logits.tolist(),
        "model_stages": tensor_tree_to_json(focused_real_model_stages(stages)),
        "qkv_micro_fixture": str(PYTHON_ORIGINAL_QKV_MICRO_OUTPUT.relative_to(ROOT)),
        "log_probs": log_probs.tolist(),
        "viterbi_biases": biases,
        "decoded_labels": decoded_labels,
        "labels_by_index": {str(key): value for key, value in labels_by_index.items()},
        "decoded_text": decoded_text,
        "decoded_mismatch": decoded_text != text,
        "char_starts": char_starts,
        "char_ends": char_ends,
        "token_spans": [list(span) for span in token_spans],
        "char_spans": [list(span) for span in char_spans],
        "trimmed_char_spans": [list(span) for span in trimmed],
        "kept_char_spans": [list(span) for span in kept],
        "detected_spans": [
            {
                "label": runtime.label_info.span_class_names[label_idx],
                "start": start,
                "end": end,
                "text": decoded_text[start:end],
            }
            for label_idx, start, end in kept
        ],
    }


def python_original_qkv_micro(
    model: Transformer,
    stages: dict[str, Any],
    checkpoint: Path,
    text: str,
    n_ctx: int,
) -> dict[str, Any]:
    attention = model.block[0].attn
    attention_stages = stages["blocks"][0]["attention"]
    normalized = attention_stages["normalized"].detach()
    qkv = attention_stages["qkv"].detach()
    weight = attention.qkv.weight.detach()
    bias = attention.qkv.bias.detach() if attention.qkv.bias is not None else None
    probe_indices = qkv_probe_indices(qkv)

    return {
        "status": "completed",
        "checkpoint": ".cache/privacy-filter/openai-original",
        "text": text,
        "n_ctx": n_ctx,
        "operation": "block.0.attention.qkv",
        "python_source": "torch.nn.functional.linear",
        "torch": {
            "version": torch.__version__,
            "device": str(normalized.device),
            "matmul_precision": torch.get_float32_matmul_precision(),
            "input_dtype": str(normalized.dtype),
            "weight_dtype": str(weight.dtype),
            "bias_dtype": str(bias.dtype) if bias is not None else None,
            "output_dtype": str(qkv.dtype),
        },
        "shapes": {
            "input": list(normalized.shape),
            "weight": list(weight.shape),
            "bias": list(bias.shape) if bias is not None else None,
            "output": list(qkv.shape),
        },
        "input": normalized.cpu().tolist(),
        "weight": weight.cpu().tolist(),
        "bias": bias.cpu().tolist() if bias is not None else None,
        "output": qkv.cpu().tolist(),
        "scalar_probes": [
            qkv_scalar_probe(normalized, weight, bias, qkv, index) for index in probe_indices
        ],
    }


def qkv_probe_indices(qkv: torch.Tensor) -> list[list[int]]:
    _batch, tokens, width = qkv.shape
    candidates = [
        [0, 0, 0],
        [0, 0, max(0, width // 3 - 1)],
        [0, 0, max(0, 2 * width // 3 - 1)],
        [0, 0, width - 1],
        [0, min(1, tokens - 1), 0],
    ]
    unique = []
    seen = set()
    for index in candidates:
        key = tuple(index)
        if key not in seen:
            unique.append(index)
            seen.add(key)
    return unique


def qkv_scalar_probe(
    normalized: torch.Tensor,
    weight: torch.Tensor,
    bias: torch.Tensor | None,
    qkv: torch.Tensor,
    index: list[int],
) -> dict[str, Any]:
    batch, token, output_index = index
    input_row = normalized[batch, token, :].detach()
    weight_row = weight[output_index, :].detach()
    bias_value = bias[output_index].detach() if bias is not None else torch.tensor(0.0)
    manual_sum = torch.sum(input_row.float() * weight_row.float())
    manual_with_bias = manual_sum + bias_value.float()
    single = F.linear(
        input_row[None, :].to(weight.dtype),
        weight_row[None, :],
        bias_value[None].to(weight.dtype) if bias is not None else None,
    )

    return {
        "index": index,
        "input_values": input_row.cpu().tolist(),
        "weight_values": weight_row.cpu().tolist(),
        "bias_value": float(bias_value.float().cpu().item()),
        "manual_f32_sum_without_bias": float(manual_sum.cpu().item()),
        "manual_f32_sum_with_bias": float(manual_with_bias.cpu().item()),
        "torch_single_linear_value": float(single.squeeze().float().cpu().item()),
        "torch_output_value": float(qkv[batch, token, output_index].float().cpu().item()),
    }


def deterministic_params() -> dict[str, torch.Tensor]:
    return {
        "embedding.weight": values((5, 4), 0.01, 0.03),
        "block.0.attn.norm.scale": values((4,), 0.90, 0.04),
        "block.0.attn.sinks": values((2,), -0.20, 0.15),
        "block.0.attn.qkv.weight": values((8, 4), -0.30, 0.02),
        "block.0.attn.qkv.bias": values((8,), 0.05, -0.01),
        "block.0.attn.out.weight": values((4, 4), 0.20, -0.015),
        "block.0.attn.out.bias": values((4,), -0.04, 0.02),
        "block.0.mlp.norm.scale": values((4,), 1.10, -0.03),
        "block.0.mlp.gate.weight": torch.tensor(
            [[0.25, -0.15, 0.05, 0.10], [-0.10, 0.20, 0.15, -0.05]],
            dtype=torch.float32,
        ),
        "block.0.mlp.gate.bias": torch.tensor([0.02, -0.01], dtype=torch.float32),
        "block.0.mlp.mlp1_weight": values((2, 4, 4), -0.12, 0.01),
        "block.0.mlp.mlp1_bias": values((2, 4), 0.03, 0.015),
        "block.0.mlp.mlp2_weight": values((2, 2, 4), 0.07, -0.012),
        "block.0.mlp.mlp2_bias": values((2, 4), -0.02, 0.01),
        "norm.scale": values((4,), 0.95, 0.02),
        "unembedding.weight": values((3, 4), -0.08, 0.025),
    }


def values(shape: tuple[int, ...], start: float, step: float) -> torch.Tensor:
    total = 1
    for dim in shape:
        total *= dim
    return (torch.arange(total, dtype=torch.float32) * step + start).reshape(shape)


def assign_params(model: Transformer, params: dict[str, torch.Tensor]) -> None:
    name_to_param = dict(model.named_parameters())
    for name, tensor in params.items():
        target = name_to_param[name]
        if tuple(target.shape) != tuple(tensor.shape):
            raise RuntimeError(f"shape mismatch for {name}: {tuple(target.shape)} != {tuple(tensor.shape)}")
        target.data.copy_(tensor)


def config_payload(config: ModelConfig) -> dict[str, Any]:
    return {
        "num_hidden_layers": config.num_hidden_layers,
        "num_experts": config.num_experts,
        "experts_per_token": config.experts_per_token,
        "vocab_size": config.vocab_size,
        "num_labels": config.num_labels,
        "hidden_size": config.hidden_size,
        "intermediate_size": config.intermediate_size,
        "swiglu_limit": config.swiglu_limit,
        "packed_geglu": config.packed_geglu,
        "head_dim": config.head_dim,
        "num_attention_heads": config.num_attention_heads,
        "num_key_value_heads": config.num_key_value_heads,
        "sliding_window": config.sliding_window,
        "bidirectional_context": config.bidirectional_context,
        "bidirectional_left_context": config.bidirectional_left_context,
        "bidirectional_right_context": config.bidirectional_right_context,
        "initial_context_length": config.initial_context_length,
        "rope_theta": config.rope_theta,
        "rope_scaling_factor": config.rope_scaling_factor,
        "rope_ntk_alpha": config.rope_ntk_alpha,
        "rope_ntk_beta": config.rope_ntk_beta,
    }


def tensor_tree_to_json(value):
    if isinstance(value, torch.Tensor):
        return value.detach().cpu().tolist()
    if isinstance(value, dict):
        return {key: tensor_tree_to_json(child) for key, child in value.items()}
    if isinstance(value, list):
        return [tensor_tree_to_json(child) for child in value]
    return value


def without_model_stages(reference: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in reference.items() if key != "model_stages"}


def focused_real_model_stages(stages: dict[str, Any]) -> dict[str, Any]:
    first_block = stages["blocks"][0]
    first_attention = first_block["attention"]

    return {
        "embedding": stages["embedding"],
        "blocks": [
            {
                "input": first_block["input"],
                "attention": {
                    "normalized": first_attention["normalized"],
                    "qkv": first_attention["qkv"],
                    "query_rotary": first_attention["query_rotary"],
                    "key_rotary": first_attention["key_rotary"],
                    "value": first_attention["value"],
                    "query_scaled": first_attention["query_scaled"],
                    "key_scaled": first_attention["key_scaled"],
                    "attention_scores": first_attention["attention_scores"],
                    "attention_weights": first_attention["attention_weights"],
                    "attention": first_attention["attention"],
                    "projection": first_attention["projection"],
                    "output": first_attention["output"],
                },
            }
        ],
    }


if __name__ == "__main__":
    raise SystemExit(main())
