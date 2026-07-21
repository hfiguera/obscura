#!/usr/bin/env python3
"""Create a side-by-side report from Presidio and Obscura JSON reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare Presidio and Obscura eval reports.")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-md", required=True)
    parser.add_argument("--manifest", default="eval/authoritative/manifest.json")
    parser.add_argument(
        "--report",
        action="append",
        required=True,
        help="LABEL=PATH. Example: presidio_spacy=eval/reports/report.json",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    entries = [load_entry(spec, manifest, manifest_path) for spec in args.report]
    baseline = entries[0]
    entries = [qualify_latency(entry, baseline) for entry in entries]
    sample_sets = {
        entry["label"]: entry["dataset"].get(
            "sample_ids", entry["dataset"].get("ordered_sample_ids", [])
        )
        for entry in entries
    }
    same_samples = all(ids == next(iter(sample_sets.values())) for ids in sample_sets.values())
    fingerprint_sets = {
        entry["label"]: entry.get("comparison_protocol", {}) for entry in entries
    }
    same_fingerprints = all(
        fingerprints == next(iter(fingerprint_sets.values()))
        for fingerprints in fingerprint_sets.values()
    )
    if not same_samples:
        raise SystemExit("report sample IDs differ")
    if not same_fingerprints:
        raise SystemExit("report comparison protocol fingerprints differ")

    report = {
        "run_id": args.run_id,
        "phase": "presidio_vs_obscura_comparison",
        "same_samples": same_samples,
        "same_fingerprints": same_fingerprints,
        "sample_sets": sample_sets,
        "fingerprint_sets": fingerprint_sets,
        "entries": entries,
        "limitations": limitations(entries),
    }
    write_json(Path(args.out_json), report)
    Path(args.out_md).write_text(markdown(report), encoding="utf-8")
    print(json.dumps({"run_id": args.run_id, "same_samples": same_samples}, sort_keys=True))
    return 0


def limitations(entries: list[dict[str, Any]]) -> list[str]:
    items = [
        "All entries are loaded from generated JSON reports.",
        "same_samples is true only when every report declares the same dataset.sample_ids list.",
    ]

    if any(entry["profile"] == "nlp" or "fake" in entry["label"] for entry in entries):
        items.append(
            "Obscura nlp is fake-gold-assisted and proves integration behavior, not model accuracy."
        )

    if any(entry["profile"] == "deterministic_plus" for entry in entries):
        items.append(
            "Obscura deterministic_plus uses context-limited local recognizers; it is not broad NER parity."
        )

    return items


def load_entry(
    spec: str, manifest: dict[str, Any], manifest_path: Path
) -> dict[str, Any]:
    label, separator, path = spec.partition("=")
    if not separator:
        raise SystemExit(f"Invalid --report value: {spec!r}; expected LABEL=PATH")
    report = json.loads(Path(path).read_text(encoding="utf-8"))
    manifest_entry = find_manifest_entry(Path(path), manifest, manifest_path)
    metrics = report["metrics"]
    latency = report.get("latency", {})
    return {
        "label": label,
        "path": path,
        "run_id": report["run_id"],
        "adapter": report.get("adapter"),
        "profile": report.get("profile"),
        "model": report.get("model"),
        "comparison_protocol": report.get("comparison_protocol"),
        "environment": manifest_entry.get("environment", {}),
        "runtime_backend": manifest_entry.get("runtime", {}).get("backend", {}),
        "repetitions": manifest_entry.get("repetitions", {}),
        "dataset": report.get("dataset", {}),
        "scope": report.get("dataset", {}).get("scope"),
        "template_split": report.get("dataset", {}).get("template_split"),
        "metrics": {
            "precision": metrics.get("precision"),
            "recall": metrics.get("recall"),
            "f1": metrics.get("f1"),
            "f2": metrics.get("f2"),
            "true_positives": metrics.get("true_positives"),
            "false_positives": metrics.get("false_positives"),
            "false_negatives": metrics.get("false_negatives"),
            "offset_mismatches": metrics.get("offset_mismatches"),
            "wrong_entity_type": metrics.get("wrong_entity_type"),
            "unsupported_expected_spans": metrics.get("unsupported_expected_spans"),
            "total_expected_spans": metrics.get("total_expected_spans"),
            "total_supported_expected_spans": metrics.get("total_supported_expected_spans"),
            "total_predicted_spans": metrics.get("total_predicted_spans"),
            "span_iou": metrics.get("span_iou"),
        },
        "latency": {
            "mean_ms": latency.get("mean_ms"),
            "p50_ms": latency.get("p50_ms"),
            "p95_ms": latency.get("p95_ms"),
            "max_ms": latency.get("max_ms"),
            "median_ms": latency.get("p50_ms"),
            "throughput_samples_per_second": throughput(latency.get("mean_ms")),
        },
    }


def find_manifest_entry(
    report_path: Path, manifest: dict[str, Any], manifest_path: Path
) -> dict[str, Any]:
    expected = report_path.resolve()
    root = manifest_path.resolve().parent
    for entry in manifest.get("reports", []):
        candidate = (root / entry["files"]["json"]).resolve()
        if candidate == expected:
            return entry
    raise SystemExit(f"report is not promoted in authoritative manifest: {report_path}")


def qualify_latency(
    entry: dict[str, Any], baseline: dict[str, Any]
) -> dict[str, Any]:
    environment = entry["environment"]
    baseline_environment = baseline["environment"]
    runtime = entry["runtime_backend"]
    baseline_runtime = baseline["runtime_backend"]
    same_machine = (
        environment.get("hardware_label") == baseline_environment.get("hardware_label")
        and environment.get("cpu") == baseline_environment.get("cpu")
        and normalized_architecture(environment.get("architecture"))
        == normalized_architecture(baseline_environment.get("architecture"))
    )
    device = actual_runtime_value(runtime, "actual_device")
    baseline_device = actual_runtime_value(baseline_runtime, "actual_device")
    same_device = device is not None and device == baseline_device
    comparable = same_machine and same_device
    entry["latency_comparable_to_baseline"] = comparable
    entry["latency_comparison_reason"] = (
        "same physical machine and CPU device"
        if comparable
        else "different or unproven execution device/backend conditions"
    )
    return entry


def markdown(report: dict[str, Any]) -> str:
    rows = "\n".join(metric_row(entry) for entry in report["entries"])
    latency_rows = "\n".join(latency_row(entry) for entry in report["entries"])
    samples = "\n".join(sample_row(entry) for entry in report["entries"])
    limitations = "\n".join(f"- {item}" for item in report["limitations"])
    return f"""# Presidio vs Obscura Comparison Report

- Run ID: {report["run_id"]}
- Same sample IDs: {str(report["same_samples"]).lower()}
- Same protocol fingerprints: {str(report["same_fingerprints"]).lower()}

## Sample Identity

{samples}

## Metrics

| Entry | Profile | Scope | Split | Precision | Recall | F1 | F2 | IoU F1 | TP | FP | FN | Offset mismatches | Wrong type | Unsupported |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
{rows}

## Latency

| Entry | Mean | Median | P95 | Throughput | Runs | Comparison |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
{latency_rows}

## Limitations

{limitations}
"""


def metric_row(entry: dict[str, Any]) -> str:
    metrics = entry["metrics"]
    return (
        f"| {entry['label']} | {entry['profile']} | {entry.get('scope') or 'n/a'} | "
        f"{template_split_name(entry.get('template_split'))} | {fmt(metrics['precision'])} | "
        f"{fmt(metrics['recall'])} | {fmt(metrics['f1'])} | {fmt(metrics['f2'])} | "
        f"{fmt((metrics['span_iou'] or {}).get('f1'))} | "
        f"{metrics['true_positives']} | {metrics['false_positives']} | "
        f"{metrics['false_negatives']} | {metrics['offset_mismatches']} | "
        f"{metrics['wrong_entity_type']} | {metrics['unsupported_expected_spans']} |"
    )


def sample_row(entry: dict[str, Any]) -> str:
    protocol = entry.get("comparison_protocol") or {}
    sample_ids = entry["dataset"].get(
        "sample_ids", entry["dataset"].get("ordered_sample_ids", [])
    )
    return (
        f"- {entry['label']}: {len(sample_ids)} ordered IDs; "
        f"SHA-256 `{protocol.get('sample_ids_sha256', 'n/a')}`"
    )


def latency_row(entry: dict[str, Any]) -> str:
    latency = entry["latency"]
    repetitions = entry["repetitions"]
    return (
        f"| {entry['label']} | {fmt_ms(latency['mean_ms'])} | "
        f"{fmt_ms(latency['median_ms'])} | {fmt_ms(latency['p95_ms'])} | "
        f"{fmt(latency['throughput_samples_per_second'])} samples/s | "
        f"{repetitions.get('measured_runs', 0)} | "
        f"{latency_qualification(entry)} |"
    )


def latency_qualification(entry: dict[str, Any]) -> str:
    status = "comparable" if entry["latency_comparable_to_baseline"] else "not comparable"
    return f"{status}: {entry['latency_comparison_reason']}"


def throughput(mean_ms: Any) -> float | None:
    if not isinstance(mean_ms, (int, float)) or mean_ms <= 0:
        return None
    return 1000.0 / mean_ms


def normalized_architecture(value: Any) -> str:
    value = str(value or "").lower()
    if value.startswith(("arm64", "aarch64")):
        return "arm64"
    return value


def actual_runtime_value(runtime: dict[str, Any], key: str) -> Any:
    return runtime.get(key, runtime.get("serving_backend_metadata", {}).get(key))


def fmt(value: Any) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.4f}"
    return str(value)


def fmt_ms(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{value:.4f}ms"


def template_split_name(split: Any) -> str:
    if not isinstance(split, dict):
        return "all"
    return str(split.get("name") or "all")


def write_json(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
