#!/usr/bin/env python3
"""Compare T-NER library output with Obscura/Bumblebee output on fixed samples.

This adapter is evaluation-only. It is intended to validate the CRF caveat on
the tner/roberta-large-ontonotes5 model card without adding Python dependencies
to Obscura.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from real_presidio_benchmark import git_sha, write_json


LABEL_MAP = {
    "PERSON": "person",
    "ORG": "organization",
    "GPE": "location",
    "LOC": "location",
    "FAC": "location",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare T-NER CRF-aware output with Obscura/Bumblebee output."
    )
    parser.add_argument("--samples", default="eval/tner_reference_samples.json")
    parser.add_argument("--obscura-predictions", default="eval/predictions/tner_bumblebee_reference.json")
    parser.add_argument("--out-dir", default="eval/reports")
    parser.add_argument("--run-suffix", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    run_id = "tner_crf_reference_check"
    if args.run_suffix:
        run_id = f"{run_id}_{safe_suffix(args.run_suffix)}"

    samples = read_json(Path(args.samples))
    obscura = read_json(Path(args.obscura_predictions))

    try:
        tner_predictions, latency_ms = run_tner(samples)
    except Exception as error:
        report = skipped_report(run_id, args, samples, obscura, error)
    else:
        report = completed_report(run_id, args, samples, obscura, tner_predictions, latency_ms)

    out_dir = Path(args.out_dir)
    write_json(out_dir / f"{run_id}.json", report)
    (out_dir / f"{run_id}.md").write_text(markdown(report), encoding="utf-8")
    print(json.dumps({"run_id": run_id, "status": report["status"]}, sort_keys=True))
    return 0


def run_tner(samples: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[float]]:
    try:
        from tner import TransformersNER
    except Exception as error:
        raise RuntimeError(f"missing optional dependency tner: {error}") from error

    model = TransformersNER("tner/roberta-large-ontonotes5")
    predictions = []
    latency_ms = []

    for sample in samples:
        started = time.perf_counter()
        raw = model.predict([sample["text"]])
        latency_ms.append((time.perf_counter() - started) * 1000)
        predictions.append(
            {
                "sample_id": sample["id"],
                "text": sample["text"],
                "raw": raw,
                "predictions": normalize_tner_output(sample["text"], raw),
            }
        )

    return predictions, latency_ms


def normalize_tner_output(text: str, raw: Any) -> list[dict[str, Any]]:
    candidates = raw
    if isinstance(raw, list) and len(raw) == 1:
        candidates = raw[0]
    if isinstance(candidates, dict):
        for key in ("entities", "prediction", "predictions"):
            if key in candidates:
                candidates = candidates[key]
                break

    predictions = []
    if not isinstance(candidates, list):
        return predictions

    for item in candidates:
        if not isinstance(item, dict):
            continue

        raw_label = item.get("type") or item.get("entity") or item.get("label") or item.get("tag")
        label = normalize_label(raw_label)
        entity = LABEL_MAP.get(label)
        if entity is None:
            continue

        start = item.get("start") or item.get("start_pos") or item.get("span_start")
        end = item.get("end") or item.get("end_pos") or item.get("span_end")
        value = item.get("text") or item.get("word") or item.get("mention")

        if start is None or end is None:
            if value:
                found = text.find(str(value))
                if found >= 0:
                    start = found
                    end = found + len(str(value))

        if not isinstance(start, int) or not isinstance(end, int) or start >= end:
            continue

        predictions.append(
            {
                "entity": entity,
                "source_entity": label,
                "char_start": start,
                "char_end": end,
                "value": text[start:end],
            }
        )

    return sorted(predictions, key=lambda item: (item["char_start"], item["char_end"], item["entity"]))


def normalize_label(label: Any) -> str:
    value = str(label or "")
    for prefix in ("B-", "I-", "E-", "S-"):
        if value.startswith(prefix):
            return value[len(prefix) :]
    return value


def completed_report(
    run_id: str,
    args: argparse.Namespace,
    samples: list[dict[str, Any]],
    obscura: dict[str, Any],
    tner_predictions: list[dict[str, Any]],
    latency_ms: list[float],
) -> dict[str, Any]:
    comparison = compare_predictions(obscura["samples"], tner_predictions)

    return {
        "run_id": run_id,
        "phase": "tner_crf_reference_check",
        "timestamp": "2026-06-08T00:00:00Z",
        "git_sha": git_sha(),
        "status": "completed",
        "adapter": "TNER.TransformersNER",
        "model": {
            "id": "tner/roberta-large-ontonotes5",
            "reference_runtime": "T-NER Python library",
            "compared_runtime": obscura.get("adapter"),
            "obscura_model": obscura.get("model"),
        },
        "dataset": {
            "name": "tner_reference_samples",
            "source": args.samples,
            "sample_count": len(samples),
            "sample_ids": [sample["id"] for sample in samples],
        },
        "comparison": comparison,
        "latency": latency_summary(latency_ms),
        "tner_predictions": safe_predictions(tner_predictions),
        "obscura_predictions_path": args.obscura_predictions,
        "limitations": [
            "Evaluation-only CRF caveat check for tner/roberta-large-ontonotes5.",
            "The sample set is synthetic and small; it proves output agreement shape, not benchmark accuracy.",
            "The Obscura/Bumblebee side uses the plain token-classification path, while T-NER is the model-card recommended library path.",
        ],
    }


def skipped_report(
    run_id: str,
    args: argparse.Namespace,
    samples: list[dict[str, Any]],
    obscura: dict[str, Any],
    error: Exception,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "phase": "tner_crf_reference_check",
        "timestamp": "2026-06-08T00:00:00Z",
        "git_sha": git_sha(),
        "status": "skipped",
        "adapter": "TNER.TransformersNER",
        "model": {
            "id": "tner/roberta-large-ontonotes5",
            "reference_runtime": "T-NER Python library",
            "compared_runtime": obscura.get("adapter"),
            "obscura_model": obscura.get("model"),
        },
        "dataset": {
            "name": "tner_reference_samples",
            "source": args.samples,
            "sample_count": len(samples),
            "sample_ids": [sample["id"] for sample in samples],
        },
        "comparison": empty_comparison(),
        "latency": latency_summary([]),
        "obscura_predictions_path": args.obscura_predictions,
        "limitations": [
            f"Skipped T-NER reference check: {error}",
            "Install optional Python dependencies in the evaluation venv to compare the CRF-aware T-NER path.",
            "This adapter is evaluation-only and is not a default Obscura runtime dependency.",
        ],
    }


def compare_predictions(
    obscura_samples: list[dict[str, Any]], tner_samples: list[dict[str, Any]]
) -> dict[str, Any]:
    obscura_by_id = {sample["sample_id"]: sample for sample in obscura_samples}
    tner_by_id = {sample["sample_id"]: sample for sample in tner_samples}
    rows = []

    exact_matches = 0
    obscura_total = 0
    tner_total = 0

    for sample_id in sorted(obscura_by_id):
        obscura_set = comparable_set(obscura_by_id[sample_id].get("predictions", []))
        tner_set = comparable_set(tner_by_id.get(sample_id, {}).get("predictions", []))
        matches = obscura_set & tner_set
        exact_matches += len(matches)
        obscura_total += len(obscura_set)
        tner_total += len(tner_set)
        rows.append(
            {
                "sample_id": sample_id,
                "obscura_prediction_count": len(obscura_set),
                "tner_prediction_count": len(tner_set),
                "exact_match_count": len(matches),
                "obscura_only_count": len(obscura_set - tner_set),
                "tner_only_count": len(tner_set - obscura_set),
            }
        )

    precision = exact_matches / tner_total if tner_total else None
    recall = exact_matches / obscura_total if obscura_total else None
    f1 = (
        2 * precision * recall / (precision + recall)
        if precision is not None and recall is not None and precision + recall > 0
        else None
    )

    return {
        "exact_matches": exact_matches,
        "obscura_prediction_count": obscura_total,
        "tner_prediction_count": tner_total,
        "agreement_precision_against_tner": precision,
        "agreement_recall_against_obscura": recall,
        "agreement_f1": f1,
        "samples": rows,
    }


def comparable_set(predictions: list[dict[str, Any]]) -> set[tuple[str, int, int]]:
    comparable = set()
    for prediction in predictions:
        entity = prediction.get("entity")
        if isinstance(entity, str):
            entity_value = entity
        else:
            entity_value = str(entity or "")
        comparable.add((entity_value, int(prediction["char_start"]), int(prediction["char_end"])))
    return comparable


def empty_comparison() -> dict[str, Any]:
    return {
        "exact_matches": 0,
        "obscura_prediction_count": 0,
        "tner_prediction_count": 0,
        "agreement_precision_against_tner": None,
        "agreement_recall_against_obscura": None,
        "agreement_f1": None,
        "samples": [],
    }


def latency_summary(values: list[float]) -> dict[str, float]:
    if not values:
        return {"mean_ms": 0.0, "p50_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0}

    ordered = sorted(values)
    return {
        "mean_ms": sum(values) / len(values),
        "p50_ms": percentile(ordered, 0.50),
        "p95_ms": percentile(ordered, 0.95),
        "max_ms": max(values),
    }


def percentile(ordered: list[float], pct: float) -> float:
    index = min(len(ordered) - 1, int(round((len(ordered) - 1) * pct)))
    return ordered[index]


def safe_predictions(samples: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "sample_id": sample["sample_id"],
            "prediction_count": len(sample["predictions"]),
            "predictions": [
                {key: value for key, value in prediction.items() if key != "value"}
                for prediction in sample["predictions"]
            ],
        }
        for sample in samples
    ]


def markdown(report: dict[str, Any]) -> str:
    comparison = report["comparison"]
    latency = report["latency"]
    return f"""# TNER CRF Reference Check

- Run ID: {report["run_id"]}
- Status: {report["status"]}
- Adapter: {report["adapter"]}
- Model: {report["model"]["id"]}
- Samples: {report["dataset"]["sample_count"]}
- Obscura predictions: {report["obscura_predictions_path"]}

## Agreement

| Metric | Value |
| --- | ---: |
| Exact matches | {comparison["exact_matches"]} |
| Obscura predictions | {comparison["obscura_prediction_count"]} |
| T-NER predictions | {comparison["tner_prediction_count"]} |
| Agreement precision vs T-NER | {format_metric(comparison["agreement_precision_against_tner"])} |
| Agreement recall vs Obscura | {format_metric(comparison["agreement_recall_against_obscura"])} |
| Agreement F1 | {format_metric(comparison["agreement_f1"])} |

## Latency

| Metric | Value |
| --- | ---: |
| Mean | {latency["mean_ms"]:.4f}ms |
| P50 | {latency["p50_ms"]:.4f}ms |
| P95 | {latency["p95_ms"]:.4f}ms |
| Max | {latency["max_ms"]:.4f}ms |

## Limitations

{limitation_lines(report["limitations"])}
"""


def format_metric(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.4f}"


def limitation_lines(limitations: list[str]) -> str:
    return "\n".join(f"- {item}" for item in limitations)


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def safe_suffix(value: str) -> str:
    return "".join(char.lower() if char.isalnum() else "_" for char in value).strip("_")


if __name__ == "__main__":
    sys.exit(main())
