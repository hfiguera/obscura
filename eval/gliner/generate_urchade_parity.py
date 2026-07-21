#!/usr/bin/env python3
"""Generate Python/PyTorch/ONNX parity evidence for the Urchade export."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import random
from pathlib import Path
from typing import Any

import numpy as np
import onnxruntime as ort
import torch
from gliner import GLiNER

from export_urchade import MODEL_ID, MODEL_REVISION


INPUT_NAMES = [
    "input_ids",
    "attention_mask",
    "words_mask",
    "text_lengths",
    "span_idx",
    "span_mask",
]
LABEL_PROFILES = {
    "open_class": ["person", "organization", "location"],
    "hybrid_core": [
        "person",
        "organization",
        "location",
        "email address",
        "phone number",
        "credit card number",
        "iban code",
        "social security number",
        "ip address",
        "domain name",
        "url",
    ],
}
THRESHOLD = 0.5


def tensor_record(value: Any) -> dict[str, Any]:
    array = np.ascontiguousarray(value.detach().cpu().numpy())
    return {
        "dtype": str(array.dtype),
        "shape": list(array.shape),
        "sha256": hashlib.sha256(array.tobytes(order="C")).hexdigest(),
    }


def array_record(value: np.ndarray, include_data: bool = False) -> dict[str, Any]:
    array = np.ascontiguousarray(value)
    record = {
        "dtype": str(array.dtype),
        "shape": list(array.shape),
        "sha256": hashlib.sha256(array.tobytes(order="C")).hexdigest(),
    }
    if include_data:
        record["base64"] = base64.b64encode(array.tobytes(order="C")).decode("ascii")
    return record


def byte_offset(text: str, character_offset: int) -> int:
    return len(text[:character_offset].encode("utf-8"))


def normalize_spans(text: str, spans: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for span in spans:
        rows.append(
            {
                "byte_start": byte_offset(text, span["start"]),
                "byte_end": byte_offset(text, span["end"]),
                "text": span["text"],
                "label": span["label"],
                "score": float(span["score"]),
            }
        )
    return sorted(rows, key=lambda row: (row["byte_start"], row["byte_end"], row["label"]))


def span_identity(span: dict[str, Any]) -> tuple[Any, ...]:
    return (span["byte_start"], span["byte_end"], span["text"], span["label"])


def compare_spans(
    left: list[dict[str, Any]], right: list[dict[str, Any]]
) -> tuple[bool, float | None]:
    identities_match = [span_identity(row) for row in left] == [
        span_identity(row) for row in right
    ]
    if not identities_match:
        return False, None
    differences = [
        abs(left_row["score"] - right_row["score"])
        for left_row, right_row in zip(left, right)
    ]
    return True, max(differences, default=0.0)


def cases() -> list[dict[str, str]]:
    fixed = [
        {
            "id": "ascii",
            "text": "Rachel Green works at Ralph Lauren in New York City.",
        },
        {
            "id": "punctuation",
            "text": "Dr. Alice O'Brien joined ACME, Inc.; she moved to Paris.",
        },
        {
            "id": "unicode_latin",
            "text": "José Álvarez joined Acme GmbH in München.",
        },
        {
            "id": "unicode_decomposed",
            "text": "Jose\u0301 works for Cafe\u0301 Europa in Sa\u0303o Paulo.",
        },
        {
            "id": "unicode_cjk_emoji",
            "text": "Dr. 李明 works for 東京病院 in 東京都. Contact team \U0001f512.",
        },
        {
            "id": "long_text",
            "text": (
                "Background context without an entity. " * 60
                + "Rachel Green works at Ralph Lauren in New York City."
            ),
        },
    ]

    randomizer = random.Random(20260720)
    people = ["Ada Lovelace", "Renée Faßbinder", "李 雷", "O'Connor-Smith"]
    organizations = ["Northwind Labs", "ACME GmbH", "東京病院", "Université de Montréal"]
    locations = ["Denver", "München", "São Paulo", "東京都"]
    connectors = ["works at", "joined", "consults for", "left"]
    randomized = []
    for index in range(12):
        person = randomizer.choice(people)
        organization = randomizer.choice(organizations)
        location = randomizer.choice(locations)
        connector = randomizer.choice(connectors)
        randomized.append(
            {
                "id": f"random_{index:02d}",
                "text": f"{person} {connector} {organization} in {location}.",
            }
        )
    return fixed + randomized


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    pytorch_model = GLiNER.from_pretrained(
        MODEL_ID,
        revision=MODEL_REVISION,
        local_files_only=True,
    )
    onnx_model = GLiNER.from_pretrained(
        str(args.model_dir),
        load_onnx_model=True,
        local_files_only=True,
    )
    session = ort.InferenceSession(
        str(args.model_dir / "model.onnx"),
        providers=["CPUExecutionProvider"],
    )

    rows = []
    for profile, labels in LABEL_PROFILES.items():
        for case in cases():
            batch = pytorch_model._build_dummy_batch(labels=labels, text=case["text"])
            model_inputs = {name: batch[name] for name in INPUT_NAMES}

            with torch.no_grad():
                pytorch_logits = (
                    pytorch_model.model(**model_inputs).logits.detach().cpu().numpy()
                )
            onnx_logits = session.run(
                ["logits"],
                {
                    name: value.detach().cpu().numpy()
                    for name, value in model_inputs.items()
                },
            )[0]

            pytorch_spans = normalize_spans(
                case["text"],
                pytorch_model.predict_entities(
                    case["text"],
                    labels,
                    threshold=THRESHOLD,
                    flat_ner=True,
                    multi_label=False,
                ),
            )
            onnx_spans = normalize_spans(
                case["text"],
                onnx_model.predict_entities(
                    case["text"],
                    labels,
                    threshold=THRESHOLD,
                    flat_ner=True,
                    multi_label=False,
                ),
            )
            span_match, max_score_difference = compare_spans(
                pytorch_spans, onnx_spans
            )
            absolute_difference = np.abs(pytorch_logits - onnx_logits)

            rows.append(
                {
                    "id": case["id"],
                    "text": case["text"],
                    "label_profile": profile,
                    "labels": labels,
                    "threshold": THRESHOLD,
                    "inputs": {
                        name: tensor_record(model_inputs[name]) for name in INPUT_NAMES
                    },
                    "pytorch_logits": array_record(pytorch_logits),
                    "onnx_logits": array_record(onnx_logits, include_data=True),
                    "logit_max_abs_difference": float(absolute_difference.max()),
                    "logit_mean_abs_difference": float(absolute_difference.mean()),
                    "decoded_span_identity_match": span_match,
                    "decoded_max_score_difference": max_score_difference,
                    "pytorch_spans": pytorch_spans,
                    "onnx_spans": onnx_spans,
                }
            )

    summary = {
        "case_count": len(rows),
        "input_tensor_count": len(rows) * len(INPUT_NAMES),
        "all_decoded_span_identities_match": all(
            row["decoded_span_identity_match"] for row in rows
        ),
        "max_logit_abs_difference": max(
            row["logit_max_abs_difference"] for row in rows
        ),
        "max_decoded_score_difference": max(
            row["decoded_max_score_difference"] or 0.0 for row in rows
        ),
        "pytorch_onnx_logit_tolerance": 2.0e-3,
        "decoded_score_tolerance": 1.0e-5,
    }
    summary["passed"] = (
        summary["all_decoded_span_identities_match"]
        and summary["max_logit_abs_difference"]
        <= summary["pytorch_onnx_logit_tolerance"]
        and summary["max_decoded_score_difference"]
        <= summary["decoded_score_tolerance"]
    )

    report = {
        "schema_version": 1,
        "model": {"id": MODEL_ID, "revision": MODEL_REVISION},
        "onnx_sha256": hashlib.sha256(
            (args.model_dir / "model.onnx").read_bytes()
        ).hexdigest(),
        "seed": 20260720,
        "summary": summary,
        "rows": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, sort_keys=True))
    if not summary["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
