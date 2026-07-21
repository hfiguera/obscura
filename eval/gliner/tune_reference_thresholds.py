#!/usr/bin/env python3
"""Select GLiNER per-entity thresholds from saved train predictions."""

from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path
from typing import Any

import sys

ADAPTER_DIR = Path(__file__).resolve().parents[1] / "presidio_adapter"
sys.path.insert(0, str(ADAPTER_DIR))

from real_presidio_benchmark import load_dataset, score_results  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--predictions", type=Path, required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--entities", default="person,organization,location")
    parser.add_argument(
        "--thresholds", default="0.3,0.5,0.7,0.8,0.9,0.95,0.98,0.99,0.995,0.999"
    )
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def load_predictions(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def metric_summary(metrics: dict[str, Any]) -> dict[str, Any]:
    keys = [
        "precision",
        "recall",
        "f1",
        "f2",
        "true_positives",
        "false_positives",
        "false_negatives",
        "offset_mismatches",
        "wrong_entity_type",
        "unsupported_expected_spans",
    ]
    return {key: metrics[key] for key in keys}


def main() -> None:
    args = parse_args()
    entities = [item.strip() for item in args.entities.split(",") if item.strip()]
    thresholds = [float(item) for item in args.thresholds.split(",")]
    loaded = load_dataset(args.dataset)
    samples_by_id = {str(sample["id"]): sample for sample in loaded.samples}
    prediction_rows = load_predictions(args.predictions)

    rows = []
    for values in itertools.product(thresholds, repeat=len(entities)):
        policy = dict(zip(entities, values))
        results = []
        for row in prediction_rows:
            sample = samples_by_id[str(row["sample_id"])]
            predictions = [
                prediction
                for prediction in row["predictions"]
                if prediction["entity"] in policy
                and prediction["score"] >= policy[prediction["entity"]]
            ]
            results.append(
                {
                    "expected": sample["spans"],
                    "predicted": predictions,
                    "latency_ms": row["latency_ms"],
                }
            )

        metrics = score_results(results, entities)
        rows.append({"thresholds": policy, "metrics": metric_summary(metrics)})

    rows.sort(
        key=lambda row: (
            row["metrics"]["f1"],
            row["metrics"]["precision"],
            row["metrics"]["recall"],
        ),
        reverse=True,
    )
    report = {
        "schema_version": 1,
        "selection_dataset": args.dataset,
        "selection_source": str(args.predictions),
        "entities": entities,
        "candidate_thresholds": thresholds,
        "candidate_count": len(rows),
        "best": rows[0],
        "top_20": rows[:20],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(report["best"], sort_keys=True))


if __name__ == "__main__":
    main()
