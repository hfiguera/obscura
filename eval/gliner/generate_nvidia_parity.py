#!/usr/bin/env python3
"""Generate PyTorch/ONNX parity evidence for the NVIDIA GLiNER PII export."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
import torch
from gliner import GLiNER

from export_nvidia import MODEL_ID, MODEL_REVISION
from generate_urchade_parity import (
    INPUT_NAMES,
    LABEL_PROFILES,
    THRESHOLD,
    array_record,
    cases,
    compare_spans,
    normalize_spans,
    tensor_record,
)

NVIDIA_LABEL_PROFILES = {
    **LABEL_PROFILES,
    "nvidia_nemotron_core": [
        "first_name",
        "last_name",
        "city",
        "country",
        "county",
        "state",
        "coordinate",
        "credit_debit_card",
        "cvv",
        "email",
        "ipv4",
        "ipv6",
        "phone_number",
        "fax_number",
        "url",
        "ssn",
    ],
}


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
        str(args.model_dir), load_onnx_model=True, local_files_only=True
    )
    session = ort.InferenceSession(
        str(args.model_dir / "model.onnx"), providers=["CPUExecutionProvider"]
    )

    rows = []
    for profile, labels in NVIDIA_LABEL_PROFILES.items():
        for case in cases():
            batch = pytorch_model._build_dummy_batch(labels=labels, text=case["text"])
            model_inputs = {name: batch[name] for name in INPUT_NAMES}

            with torch.no_grad():
                pytorch_logits = pytorch_model.model(**model_inputs).logits.cpu().numpy()
            onnx_logits = session.run(
                ["logits"],
                {name: value.cpu().numpy() for name, value in model_inputs.items()},
            )[0]

            pytorch_spans = normalize_spans(
                case["text"],
                pytorch_model.predict_entities(
                    case["text"], labels, threshold=THRESHOLD, flat_ner=True, multi_label=False
                ),
            )
            onnx_spans = normalize_spans(
                case["text"],
                onnx_model.predict_entities(
                    case["text"], labels, threshold=THRESHOLD, flat_ner=True, multi_label=False
                ),
            )
            span_match, max_score_difference = compare_spans(pytorch_spans, onnx_spans)
            absolute_difference = np.abs(pytorch_logits - onnx_logits)

            rows.append(
                {
                    "id": case["id"],
                    "text": case["text"],
                    "label_profile": profile,
                    "labels": labels,
                    "threshold": THRESHOLD,
                    "inputs": {name: tensor_record(model_inputs[name]) for name in INPUT_NAMES},
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
        "max_logit_abs_difference": max(row["logit_max_abs_difference"] for row in rows),
        "max_decoded_score_difference": max(
            row["decoded_max_score_difference"] or 0.0 for row in rows
        ),
        "pytorch_onnx_logit_tolerance": 3.0e-3,
        "decoded_score_tolerance": 1.0e-5,
    }
    summary["passed"] = (
        summary["all_decoded_span_identities_match"]
        and summary["max_logit_abs_difference"] <= summary["pytorch_onnx_logit_tolerance"]
        and summary["max_decoded_score_difference"] <= summary["decoded_score_tolerance"]
    )

    report = {
        "schema_version": 1,
        "model": {"id": MODEL_ID, "revision": MODEL_REVISION},
        "onnx_sha256": hashlib.sha256((args.model_dir / "model.onnx").read_bytes()).hexdigest(),
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
