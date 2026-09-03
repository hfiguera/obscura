#!/usr/bin/env python3
"""Score conservative Obscura plus Perplexity hybrid policies."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PRESIDIO_ADAPTER = ROOT / "eval" / "presidio_adapter" / "real_presidio_benchmark.py"
SELECTIONS = {
    "generated_large": ROOT
    / "eval"
    / "authoritative"
    / "selections"
    / "generated_large_template_heldout.json",
    "synth_dataset_v2": ROOT
    / "eval"
    / "authoritative"
    / "selections"
    / "synth_dataset_v2_all.json",
    "nemotron_pii_test_subset": ROOT
    / "eval"
    / "authoritative"
    / "selections"
    / "nemotron_pii_test_subset_all.json",
}

# The conservative policy is declared before benchmark execution. Structured
# recognizers remain authoritative, and the model cannot broaden the meaning of
# Obscura's location entity from private addresses to general locations.
POLICIES = {
    "base": frozenset(),
    "pplx_person": frozenset({"person"}),
    "pplx_contact": frozenset({"email", "phone", "url"}),
    "pplx_conservative": frozenset({"person", "email", "phone", "url"}),
    "pplx_broad_diagnostic": frozenset(
        {"person", "email", "phone", "url", "location"}
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=sorted(SELECTIONS), required=True)
    parser.add_argument("--base-profile", choices=["fast", "accurate"], required=True)
    parser.add_argument("--obscura-predictions", required=True)
    parser.add_argument("--pplx-predictions", required=True)
    parser.add_argument("--out-dir", default=str(ROOT / "eval" / "reports"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    presidio = load_python_module("obscura_presidio_adapter", PRESIDIO_ADAPTER)
    selection_path = SELECTIONS[args.dataset]
    loaded = presidio.load_dataset(args.dataset)
    selection = presidio.load_selection(str(selection_path), loaded)
    samples = presidio.selected_samples_from_selection(loaded.samples, selection)
    supported_entities = selection["entity_policy"]["entities"]

    obscura_artifact = load_artifact(
        Path(args.obscura_predictions), args.dataset, selection_path
    )
    pplx_artifact = load_artifact(
        Path(args.pplx_predictions), args.dataset, selection_path
    )
    obscura_rows = rows_by_id(obscura_artifact)
    pplx_rows = rows_by_id(pplx_artifact)

    policy_results = {}
    for name, admitted_entities in POLICIES.items():
        results, additions = build_results(
            samples,
            obscura_rows,
            pplx_rows,
            admitted_entities,
            supported_entities,
        )
        metrics = presidio.score_results(results, supported_entities)
        policy_results[name] = {
            "admitted_pplx_entities": sorted(admitted_entities),
            "metrics": compact_metrics(metrics),
            "per_entity": metrics["per_entity"],
            "latency": metrics["latency"],
            "additions": additions,
            "output_fingerprint_sha256": prediction_fingerprint(results),
        }

    report = {
        "schema_version": 1,
        "status": "complete",
        "phase": "pplx_pii_hybrid_candidate",
        "timestamp": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "dataset": args.dataset,
        "base_profile": args.base_profile,
        "sample_count": len(samples),
        "selection_sha256": sha256_file(selection_path),
        "merge_rule": "Obscura wins every overlap; Perplexity adds allowed nonoverlapping spans.",
        "primary_policy": "pplx_conservative",
        "best_observed_policy": best_observed_policy(policy_results),
        "policies": policy_results,
        "raw_text_omitted": True,
        "limitations": [
            "The hybrid runs Obscura and the Python model sequentially for this experiment.",
            (
                "The broad location policy is diagnostic because private_address "
                "and location differ semantically."
            ),
            (
                "Policy comparisons are exploratory and require a new untouched "
                "validation set before promotion."
            ),
        ],
    }
    assert_raw_omitted(report)
    out = Path(args.out_dir) / f"pplx_hybrid-{args.base_profile}-{args.dataset}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(out), "policies": summary(policy_results)}, sort_keys=True))
    return 0


def build_results(
    samples: list[dict[str, Any]],
    obscura_rows: dict[str, dict[str, Any]],
    pplx_rows: dict[str, dict[str, Any]],
    admitted_entities: frozenset[str],
    supported_entities: list[str],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    supported = set(supported_entities)
    accepted = rejected_overlap = rejected_entity = 0
    accepted_by_entity: dict[str, int] = {}
    results = []

    for sample in samples:
        sample_id = str(sample["id"])
        obscura_row = require_row(obscura_rows, sample_id, "Obscura")
        pplx_row = require_row(pplx_rows, sample_id, "Perplexity")
        predicted = list(obscura_row["predictions"])

        for candidate in pplx_row["predictions"]:
            if candidate["entity"] not in supported or candidate["entity"] not in admitted_entities:
                rejected_entity += 1
                continue
            if any(overlaps(candidate, current) for current in predicted):
                rejected_overlap += 1
                continue
            predicted.append(candidate)
            accepted += 1
            accepted_by_entity[candidate["entity"]] = (
                accepted_by_entity.get(candidate["entity"], 0) + 1
            )

        results.append(
            {
                "sample": {"id": sample["id"]},
                "expected": sample["spans"],
                "predicted": predicted,
                "latency_ms": obscura_row["latency_ms"]
                + (pplx_row["latency_ms"] if admitted_entities else 0.0),
            }
        )

    return results, {
        "accepted": accepted,
        "accepted_by_entity": dict(sorted(accepted_by_entity.items())),
        "rejected_entity": rejected_entity,
        "rejected_overlap": rejected_overlap,
    }


def overlaps(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return left["byte_start"] < right["byte_end"] and right["byte_start"] < left["byte_end"]


def load_artifact(path: Path, dataset: str, selection_path: Path) -> dict[str, Any]:
    artifact = json.loads(path.read_text(encoding="utf-8"))
    assert_raw_omitted(artifact)
    if artifact.get("dataset") != dataset:
        raise ValueError(f"artifact dataset mismatch: {path}")
    if artifact.get("selection_sha256") != sha256_file(selection_path):
        raise ValueError(f"artifact selection mismatch: {path}")
    return artifact


def rows_by_id(artifact: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = {str(row["sample_id"]): row for row in artifact["rows"]}
    if len(rows) != len(artifact["rows"]):
        raise ValueError("prediction artifact contains duplicate sample IDs")
    return rows


def require_row(rows: dict[str, dict[str, Any]], sample_id: str, producer: str) -> dict[str, Any]:
    try:
        return rows[sample_id]
    except KeyError as error:
        raise ValueError(f"{producer} artifact is missing sample {sample_id}") from error


def compact_metrics(metrics: dict[str, Any]) -> dict[str, Any]:
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
        "total_supported_expected_spans",
        "total_predicted_spans",
    ]
    return {key: metrics[key] for key in keys}


def prediction_fingerprint(results: list[dict[str, Any]]) -> str:
    predictions = [
        {
            "id": result["sample"]["id"],
            "spans": [
                {
                    "entity": span["entity"],
                    "byte_start": span["byte_start"],
                    "byte_end": span["byte_end"],
                }
                for span in result["predicted"]
            ],
        }
        for result in results
    ]
    return hashlib.sha256(canonical_json(predictions)).hexdigest()


def summary(policy_results: dict[str, Any]) -> dict[str, Any]:
    return {
        name: {
            "precision": result["metrics"]["precision"],
            "recall": result["metrics"]["recall"],
            "f1": result["metrics"]["f1"],
            "accepted": result["additions"]["accepted"],
        }
        for name, result in policy_results.items()
    }


def best_observed_policy(policy_results: dict[str, Any]) -> str:
    return max(
        policy_results,
        key=lambda name: policy_results[name]["metrics"]["f1"] or 0.0,
    )


def assert_raw_omitted(value: Any, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"text", "value"}:
                raise ValueError(f"raw report field is forbidden: {'.'.join((*path, key))}")
            assert_raw_omitted(child, (*path, key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_raw_omitted(child, (*path, str(index)))


def load_python_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
