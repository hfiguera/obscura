#!/usr/bin/env python3
"""Compare privacy-filter reports against Python reference and current best."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


METRIC_KEYS = [
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
    "total_supported_expected_spans",
    "total_predicted_spans",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare native privacy-filter, Python OPF reference, and current best Obscura reports."
    )
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--python-reference", required=True)
    parser.add_argument("--native", required=True)
    parser.add_argument("--hybrid", required=True)
    parser.add_argument("--current-best", required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-md", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    entries = {
        "python_reference": load_entry("python_reference", args.python_reference),
        "native_privacy_filter": load_entry("native_privacy_filter", args.native),
        "hybrid_privacy_filter": load_entry("hybrid_privacy_filter", args.hybrid),
        "current_best_obscura": load_entry("current_best_obscura", args.current_best),
    }
    report = build_report(args.run_id, entries)
    write_json(Path(args.out_json), report)
    Path(args.out_md).write_text(markdown(report), encoding="utf-8")
    print(json.dumps({"run_id": args.run_id, "same_samples": report["same_samples"]}, sort_keys=True))
    return 0


def build_report(run_id: str, entries: dict[str, dict[str, Any]]) -> dict[str, Any]:
    sample_sets = {label: entry["dataset"].get("sample_ids", []) for label, entry in entries.items()}
    first_samples = next(iter(sample_sets.values()))
    same_samples = all(samples == first_samples for samples in sample_sets.values())
    return {
        "run_id": run_id,
        "phase": "privacy_filter_comparison",
        "same_samples": same_samples,
        "sample_sets": sample_sets,
        "sample_summaries": {
            label: sample_summary(ids) for label, ids in sample_sets.items()
        },
        "entries": entries,
        "deltas": {
            "native_vs_python_reference": delta(
                entries["native_privacy_filter"], entries["python_reference"]
            ),
            "hybrid_vs_python_reference": delta(
                entries["hybrid_privacy_filter"], entries["python_reference"]
            ),
            "native_vs_current_best": delta(
                entries["native_privacy_filter"], entries["current_best_obscura"]
            ),
            "hybrid_vs_current_best": delta(
                entries["hybrid_privacy_filter"], entries["current_best_obscura"]
            ),
        },
        "limitations": limitations(entries, same_samples),
    }


def load_entry(label: str, path: str) -> dict[str, Any]:
    report = json.loads(Path(path).read_text(encoding="utf-8"))
    metrics = report.get("metrics", {})
    latency = report.get("latency", {})
    stage_latency = report.get("stage_latency", {})
    status = report_status(report)
    skip_reason = normalize_skip_reason(status, report)
    return {
        "label": label,
        "path": path,
        "run_id": report.get("run_id"),
        "phase": report.get("phase"),
        "status": status,
        "adapter": report.get("adapter"),
        "profile": report.get("profile"),
        "model": normalize_model_metadata(report.get("model")),
        "runtime_backend": report.get("runtime_backend", {}),
        "skip_reason": skip_reason,
        "dataset": report.get("dataset", {}),
        "metrics": {key: metrics.get(key) for key in METRIC_KEYS},
        "latency": {
            "mean_ms": latency.get("mean_ms"),
            "p50_ms": latency.get("p50_ms"),
            "p95_ms": latency.get("p95_ms"),
            "max_ms": latency.get("max_ms"),
        },
        "stage_latency": normalize_stage_latency(stage_latency),
    }


def normalize_skip_reason(status: str, report: dict[str, Any]) -> dict[str, Any] | None:
    skip_reason = report.get("skip_reason")
    if skip_reason:
        return skip_reason
    if status != "skipped":
        return None

    limitations = report.get("limitations", [])
    message = next((str(item) for item in limitations if item), "Report was skipped.")
    return {
        "category": skip_reason_category(message),
        "message": message,
    }


def skip_reason_category(message: str) -> str:
    if "missing optional dependency" in message:
        return "optional_dependency_missing"
    if "checkpoint" in message and "incomplete" in message:
        return "checkpoint_incomplete"
    if "checkpoint" in message and "missing" in message:
        return "checkpoint_missing"
    return "skipped"


def normalize_model_metadata(model: Any) -> dict[str, Any]:
    if not isinstance(model, dict):
        return {}

    normalized = dict(model)
    if "model_id" not in normalized and "id" in normalized:
        normalized["model_id"] = normalized["id"]
    if "checkpoint" not in normalized and "runtime_checkpoint" in normalized:
        normalized["checkpoint"] = normalized["runtime_checkpoint"]
    return normalized


def normalize_stage_latency(stage_latency: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        stage: {
            "mean_ms": values.get("mean_ms"),
            "p50_ms": values.get("p50_ms"),
            "p95_ms": values.get("p95_ms"),
            "max_ms": values.get("max_ms"),
        }
        for stage, values in sorted(stage_latency.items())
        if isinstance(values, dict)
    }


def report_status(report: dict[str, Any]) -> str:
    if report.get("status"):
        return str(report["status"])
    dataset = report.get("dataset", {})
    if dataset.get("status") == "skipped" or dataset.get("scope") == "skipped":
        return "skipped"
    run_id = str(report.get("run_id", ""))
    if "_skipped_" in run_id or run_id.endswith("_skipped"):
        return "skipped"
    limitations = " ".join(str(item) for item in report.get("limitations", []))
    if " was skipped:" in limitations or limitations.startswith("Skipped "):
        return "skipped"
    return "completed"


def delta(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    if left.get("status") == "skipped" or right.get("status") == "skipped":
        return {
            "precision": None,
            "recall": None,
            "f1": None,
            "f2": None,
            "latency_mean_ms": None,
            "latency_p95_ms": None,
        }

    output = {}
    for key in ["precision", "recall", "f1", "f2"]:
        output[key] = subtract(left["metrics"].get(key), right["metrics"].get(key))
    for key in ["mean_ms", "p95_ms"]:
        output[f"latency_{key}"] = subtract(left["latency"].get(key), right["latency"].get(key))
    return output


def subtract(left: Any, right: Any) -> float | None:
    if left is None or right is None:
        return None
    return float(left) - float(right)


def limitations(entries: dict[str, dict[str, Any]], same_samples: bool) -> list[str]:
    items = [
        "All entries are loaded from generated JSON reports.",
        "This comparison is valid only when same_samples is true.",
        "Python privacy-filter reference is evaluation-only and is not an Obscura runtime dependency.",
        "Native and hybrid privacy-filter profiles are opt-in and must not become defaults without benchmark evidence.",
    ]
    if not same_samples:
        items.append("At least one report uses a different dataset.sample_ids list.")
    skipped = [label for label, entry in entries.items() if entry.get("status") == "skipped"]
    if skipped:
        items.append(f"Skipped entries do not provide accuracy evidence: {', '.join(skipped)}.")
    return items


def markdown(report: dict[str, Any]) -> str:
    rows = "\n".join(entry_row(entry) for entry in report["entries"].values())
    settings_rows = "\n".join(settings_row(entry) for entry in report["entries"].values())
    latency_rows = "\n".join(latency_row(entry) for entry in report["entries"].values())
    stage_latency_rows = "\n".join(
        stage_latency_row(entry) for entry in report["entries"].values()
    )
    skipped_rows = skipped_entries_markdown(report["entries"])
    delta_rows = "\n".join(delta_row(label, values) for label, values in report["deltas"].items())
    samples = "\n".join(
        f"- {label}: {format_sample_summary(summary)}"
        for label, summary in report["sample_summaries"].items()
    )
    limitations = "\n".join(f"- {item}" for item in report["limitations"])
    return f"""# Privacy-Filter Comparison Report

- Run ID: {report["run_id"]}
- Same sample IDs: {str(report["same_samples"]).lower()}

## Sample IDs

{samples}

## Metrics

| Entry | Status | Profile | Precision | Recall | F1 | F2 | TP | FP | FN | Offset mismatches | Wrong type | Unsupported |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
{rows}

## Model And Runtime

| Entry | Model | Checkpoint | n_ctx | Pad windows | Decoder | Backend |
| --- | --- | --- | ---: | --- | --- | --- |
{settings_rows}

## Latency

| Entry | Mean | P50 | P95 | Max |
| --- | ---: | ---: | ---: | ---: |
{latency_rows}

## Stage Latency

| Entry | Tokenization mean | Tokenization P95 | Model mean | Model P95 | Decode mean | Decode P95 | Total mean | Total P95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
{stage_latency_rows}

{skipped_rows}

## Deltas

Positive metric deltas mean the left entry is higher. Positive latency deltas mean the left entry is slower.

| Comparison | Precision | Recall | F1 | F2 | Mean latency | P95 latency |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
{delta_rows}

## Limitations

{limitations}
"""


def sample_summary(ids: list[Any], edge_count: int = 5) -> dict[str, Any]:
    if len(ids) <= edge_count * 2:
        shown = ids
        omitted = 0
    else:
        shown = ids[:edge_count] + ids[-edge_count:]
        omitted = len(ids) - len(shown)

    return {
        "count": len(ids),
        "shown": shown,
        "omitted_count": omitted,
    }


def format_sample_summary(summary: dict[str, Any]) -> str:
    shown = ", ".join(str(item) for item in summary.get("shown", []))
    count = summary.get("count", 0)
    omitted = summary.get("omitted_count", 0)

    if count == 0:
        return "none"
    if omitted:
        return f"{shown} ({count} total; {omitted} omitted)"
    return f"{shown} ({count} total)"


def skipped_entries_markdown(entries: dict[str, dict[str, Any]]) -> str:
    rows = [
        skipped_entry_row(entry)
        for entry in entries.values()
        if entry.get("status") == "skipped" or entry.get("skip_reason")
    ]

    if not rows:
        return ""

    return """## Skipped Entries

| Entry | Category | Message |
| --- | --- | --- |
{}
""".format("\n".join(rows))


def skipped_entry_row(entry: dict[str, Any]) -> str:
    skip_reason = entry.get("skip_reason") or {}

    if isinstance(skip_reason, dict):
        category = skip_reason.get("category")
        message = skip_reason.get("message")
    else:
        category = "skipped"
        message = skip_reason

    return f"| {entry['label']} | {fmt_text(category)} | {fmt_text(message)} |"


def entry_row(entry: dict[str, Any]) -> str:
    metrics = entry["metrics"]
    return (
        f"| {entry['label']} | {entry['status']} | {entry.get('profile') or 'n/a'} | "
        f"{fmt(metrics['precision'])} | {fmt(metrics['recall'])} | {fmt(metrics['f1'])} | "
        f"{fmt(metrics['f2'])} | {fmt(metrics['true_positives'])} | "
        f"{fmt(metrics['false_positives'])} | {fmt(metrics['false_negatives'])} | "
        f"{fmt(metrics['offset_mismatches'])} | {fmt(metrics['wrong_entity_type'])} | "
        f"{fmt(metrics['unsupported_expected_spans'])} |"
    )


def latency_row(entry: dict[str, Any]) -> str:
    if entry.get("status") == "skipped":
        return f"| {entry['label']} | n/a | n/a | n/a | n/a |"

    latency = entry["latency"]
    return (
        f"| {entry['label']} | {fmt_ms(latency['mean_ms'])} | {fmt_ms(latency['p50_ms'])} | "
        f"{fmt_ms(latency['p95_ms'])} | {fmt_ms(latency['max_ms'])} |"
    )


def settings_row(entry: dict[str, Any]) -> str:
    model = entry.get("model") or {}
    backend = entry.get("runtime_backend") or {}

    return (
        f"| {entry['label']} | "
        f"{fmt_text(model.get('model_id') or model.get('model_alias') or model.get('name'))} | "
        f"{fmt_text(model.get('checkpoint'))} | "
        f"{fmt(model.get('n_ctx'))} | "
        f"{fmt_text(model.get('pad_windows'))} | "
        f"{fmt_text(model.get('decoder'))} | "
        f"{fmt_text(model.get('backend') or backend.get('adapter') or backend.get('backend'))} |"
    )


def stage_latency_row(entry: dict[str, Any]) -> str:
    if entry.get("status") == "skipped":
        return f"| {entry['label']} | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |"

    stages = entry.get("stage_latency", {})
    return (
        f"| {entry['label']} | "
        f"{fmt_stage_ms(stages, 'tokenization_ms', 'mean_ms')} | "
        f"{fmt_stage_ms(stages, 'tokenization_ms', 'p95_ms')} | "
        f"{fmt_stage_ms(stages, 'model_ms', 'mean_ms')} | "
        f"{fmt_stage_ms(stages, 'model_ms', 'p95_ms')} | "
        f"{fmt_stage_ms(stages, 'decode_ms', 'mean_ms')} | "
        f"{fmt_stage_ms(stages, 'decode_ms', 'p95_ms')} | "
        f"{fmt_stage_ms(stages, 'total_ms', 'mean_ms')} | "
        f"{fmt_stage_ms(stages, 'total_ms', 'p95_ms')} |"
    )


def delta_row(label: str, values: dict[str, Any]) -> str:
    return (
        f"| {label} | {fmt_delta(values['precision'])} | {fmt_delta(values['recall'])} | "
        f"{fmt_delta(values['f1'])} | {fmt_delta(values['f2'])} | "
        f"{fmt_delta_ms(values['latency_mean_ms'])} | {fmt_delta_ms(values['latency_p95_ms'])} |"
    )


def fmt(value: Any) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.4f}"
    return str(value)


def fmt_text(value: Any) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (list, tuple)):
        return ", ".join(str(item) for item in value) or "n/a"
    if isinstance(value, dict):
        return json.dumps(value, sort_keys=True)
    return str(value)


def fmt_ms(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.4f}ms"


def fmt_stage_ms(stages: dict[str, dict[str, Any]], stage: str, metric: str) -> str:
    return fmt_ms(stages.get(stage, {}).get(metric))


def fmt_delta(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):+.4f}"


def fmt_delta_ms(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):+.4f}ms"


def write_json(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
