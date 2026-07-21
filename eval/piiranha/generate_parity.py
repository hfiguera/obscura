#!/usr/bin/env python3
"""Compare pinned Piiranha PyTorch and ONNX logits and emit an Elixir oracle."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np
import onnxruntime as ort
import torch
from transformers import AutoModelForTokenClassification, AutoTokenizer

CASES = [
    {"language": "en", "text": "Maria Lopez lives at 42 Oak Street in Madrid."},
    {"language": "es", "text": "Ana García vive en Calle Mayor 18, Madrid."},
    {"language": "fr", "text": "Élodie Dupont habite au 12 rue Victor Hugo à Paris."},
    {"language": "de", "text": "Lena Müller wohnt in der Hauptstraße 7 in Berlin."},
    {"language": "it", "text": "Giulia Rossi abita in Via Roma 25 a Milano."},
    {"language": "nl", "text": "Sophie de Vries woont aan Damrak 10 in Amsterdam."},
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", default=".cache/piiranha-v1-hf")
    parser.add_argument("--model-dir", default=".cache/piiranha-v1-onnx")
    parser.add_argument("--output", default="eval/piiranha/piiranha-parity-reference.json")
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def base_label(label: str) -> str:
    return label[2:] if len(label) > 2 and label[:2] in {"B-", "I-", "E-", "S-"} else label


def char_to_byte(text: str, offset: int) -> int:
    return len(text[:offset].encode("utf-8"))


def byte_offsets(text: str, offsets: list[list[int]]) -> list[list[int]]:
    return [[char_to_byte(text, start), char_to_byte(text, end)] for start, end in offsets]


def byte_spans(text: str, spans: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            **span,
            "start": char_to_byte(text, span["start"]),
            "end": char_to_byte(text, span["end"]),
        }
        for span in spans
    ]


def decode(logits: np.ndarray, offsets: list[list[int]], id2label: dict[int, str]) -> list[dict[str, Any]]:
    label_ids = np.argmax(logits, axis=-1)
    spans: list[dict[str, Any]] = []
    active: dict[str, Any] | None = None
    for index, label_id in enumerate(label_ids):
        start, end = offsets[index]
        label = id2label[int(label_id)]
        if label == "O" or start == end:
            active = None
            continue
        normalized = base_label(label)
        if active and active["label"] == normalized and label.startswith(("I-", "E-")):
            active["end"] = int(end)
        else:
            active = {"label": normalized, "start": int(start), "end": int(end)}
            spans.append(active)
    return spans


def main() -> int:
    args = parse_args()
    source_dir = Path(args.source_dir)
    model_dir = Path(args.model_dir)
    tokenizer = AutoTokenizer.from_pretrained(source_dir, use_fast=True)
    model = AutoModelForTokenClassification.from_pretrained(source_dir).eval()
    session = ort.InferenceSession(str(model_dir / "model.onnx"), providers=["CPUExecutionProvider"])
    id2label = {int(key): value for key, value in model.config.id2label.items()}

    cases = []
    global_max = 0.0
    global_mean = []
    for case in CASES:
        encoded = tokenizer(
            case["text"],
            return_offsets_mapping=True,
            return_tensors="pt",
            truncation=True,
            max_length=256,
        )
        offsets = encoded.pop("offset_mapping")[0].tolist()
        inputs = {name: value for name, value in encoded.items() if name in {"input_ids", "attention_mask"}}
        with torch.no_grad():
            pytorch_logits = model(**inputs).logits.detach().cpu().numpy()[0]
        onnx_logits = session.run(
            None,
            {name: value.detach().cpu().numpy().astype(np.int64) for name, value in inputs.items()},
        )[0][0]
        difference = np.abs(pytorch_logits - onnx_logits)
        global_max = max(global_max, float(np.max(difference)))
        global_mean.append(float(np.mean(difference)))
        pytorch_spans = byte_spans(case["text"], decode(pytorch_logits, offsets, id2label))
        onnx_spans = byte_spans(case["text"], decode(onnx_logits, offsets, id2label))
        cases.append(
            {
                **case,
                "input_ids": inputs["input_ids"][0].tolist(),
                "attention_mask": inputs["attention_mask"][0].tolist(),
                "char_offsets": offsets,
                "offsets": byte_offsets(case["text"], offsets),
                "pytorch_spans": pytorch_spans,
                "onnx_spans": onnx_spans,
                "spans_match": pytorch_spans == onnx_spans,
                "max_abs_logit_diff": float(np.max(difference)),
                "mean_abs_logit_diff": float(np.mean(difference)),
            }
        )

    report = {
        "source_model_sha256": sha256(source_dir / "model.safetensors"),
        "onnx_model_sha256": sha256(model_dir / "model.onnx"),
        "tolerance": {"max_abs_logit_diff": 0.001, "mean_abs_logit_diff": 0.00005},
        "max_abs_logit_diff": global_max,
        "mean_abs_logit_diff": sum(global_mean) / len(global_mean),
        "all_spans_match": all(case["spans_match"] for case in cases),
        "cases": cases,
    }
    report["parity_passed"] = (
        report["all_spans_match"]
        and report["max_abs_logit_diff"] <= report["tolerance"]["max_abs_logit_diff"]
        and report["mean_abs_logit_diff"] <= report["tolerance"]["mean_abs_logit_diff"]
    )
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: report[key] for key in ["parity_passed", "all_spans_match", "max_abs_logit_diff", "mean_abs_logit_diff"]}, sort_keys=True))
    return 0 if report["parity_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
