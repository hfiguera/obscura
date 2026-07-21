#!/usr/bin/env python3
"""Run GLiNER directly against Presidio-Research fixtures.

This is an evaluation-only Python reference for Obscura's planned optional
GLiNER Ortex adapter. It intentionally does not import or modify Obscura
recognizer code. The goal is to prove what the Python GLiNER model can do
before we implement the Elixir/Ortex adapter.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from real_presidio_benchmark import (
    LoadedDataset,
    build_run_id,
    char_to_byte,
    format_metric,
    git_sha,
    latency_summary,
    load_dataset,
    sanitize_examples,
    scope,
    score_results,
    select_samples,
    split_samples_by_template,
    template_split_markdown,
    template_summary,
    write_json,
    write_predictions,
)


MODEL_CONFIGS: dict[str, dict[str, Any]] = {
    "knowledgator_gliner_pii_base_v1": {
        "model_id": "knowledgator/gliner-pii-base-v1.0",
        "architecture": "GLiNER UniEncoder span model",
        "license": "Apache-2.0",
        "label_profile": "generated_large_pii",
    },
    "knowledgator_gliner_pii_edge_v1": {
        "model_id": "knowledgator/gliner-pii-edge-v1.0",
        "architecture": "GLiNER PII Edge UniEncoder span model",
        "license": "Apache-2.0",
        "label_profile": "generated_large_pii",
    },
    "urchade_gliner_multi_pii_v1": {
        "model_id": "urchade/gliner_multi_pii-v1",
        "architecture": "GLiNER PII span model",
        "license": "Apache-2.0",
        "label_profile": "generated_large_pii",
    },
    "nvidia_gliner_pii_v1": {
        "model_id": "nvidia/gliner-PII",
        "revision": "bd23e8ef4425fd04e34c5204ab49ffaa706eae79",
        "architecture": "GLiNER large-v2.1 PII/PHI span model",
        "license": "NVIDIA Open Model License",
        "label_profile": "generated_large_pii",
    },
    "fastino_gliner2_privacy_filter_pii_multi": {
        "model_id": "fastino/gliner2-privacy-filter-PII-multi",
        "local_path": ".cache/obscura-research/models/fastino-gliner2-privacy-filter-PII-multi",
        "architecture": "GLiNER2 PII schema-conditioned span model",
        "license": "Apache-2.0",
        "label_profile": "gliner2_obscura_pii",
        "runtime": "gliner2",
    }
}

LABEL_PROFILES: dict[str, dict[str, str]] = {
    "generated_large_pii": {
        "person": "person",
        "street address": "street_address",
        "location": "location",
        "organization": "organization",
        "credit card number": "credit_card",
        "date time": "date_time",
        "title": "title",
        "phone number": "phone",
        "age": "age",
        "nationality": "nationality",
        "email address": "email",
        "zip code": "zip_code",
        "domain name": "domain",
        "url": "url",
        "iban code": "iban",
        "social security number": "us_ssn",
        "ip address": "ip_address",
        "driver license": "us_driver_license",
    },
    "hybrid_core": {
        "person": "person",
        "organization": "organization",
        "location": "location",
        "email address": "email",
        "phone number": "phone",
        "credit card number": "credit_card",
        "iban code": "iban",
        "social security number": "us_ssn",
        "ip address": "ip_address",
        "domain name": "domain",
        "url": "url",
    },
    "open_class": {
        "person": "person",
        "organization": "organization",
        "location": "location",
    },
    "edge_open_class": {
        "name": "person",
        "organization": "organization",
        "location": "location",
        "location address": "location",
        "location city": "location",
        "location state": "location",
        "location country": "location",
    },
    "nvidia_nemotron_core": {
        "first_name": "person",
        "last_name": "person",
        "city": "location",
        "country": "location",
        "county": "location",
        "state": "location",
        "coordinate": "location",
        "credit_debit_card": "credit_card",
        "cvv": "credit_card",
        "email": "email",
        "ipv4": "ip_address",
        "ipv6": "ip_address",
        "phone_number": "phone",
        "fax_number": "phone",
        "url": "url",
        "ssn": "us_ssn",
    },
    "gliner2_obscura_pii": {
        "person": "person",
        "full_name": "person",
        "first_name": "person",
        "last_name": "person",
        "organization": "organization",
        "company": "organization",
        "employer": "organization",
        "hospital": "organization",
        "location": "location",
        "city": "location",
        "state_or_region": "location",
        "country": "location",
        "address": "street_address",
        "street_address": "street_address",
        "email": "email",
        "phone_number": "phone",
        "url": "url",
        "domain": "domain",
        "ip_address": "ip_address",
        "payment_card": "credit_card",
        "card_number": "credit_card",
        "ssn": "us_ssn",
        "social_security_number": "us_ssn",
        "government_id": "id",
        "national_id_number": "id",
        "passport_number": "id",
        "drivers_license_number": "us_driver_license",
        "iban": "iban",
        "account_number": "id",
        "bank_account": "id",
        "medical_record_number": "id",
        "patient_id": "id",
        "date_of_birth": "date_time",
        "sensitive_date": "date_time",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Python GLiNER reference inference and write Obscura-compatible reports."
    )
    parser.add_argument(
        "--dataset",
        default="generated_large",
        choices=[
            "generated_small",
            "generated_large",
            "synth_dataset_v2",
            "nemotron_pii_test_subset",
        ],
    )
    parser.add_argument("--model", default="knowledgator_gliner_pii_base_v1", choices=sorted(MODEL_CONFIGS))
    parser.add_argument("--label-profile", default="generated_large_pii", choices=sorted(LABEL_PROFILES))
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--per-label-thresholds", default="")
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--device", default="cpu", choices=["cpu", "mps", "cuda"])
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--run-suffix", default="")
    parser.add_argument("--out-dir", default="eval/reports")
    parser.add_argument("--predictions-dir", default="eval/predictions")
    parser.add_argument("--template-split", default="template_heldout", choices=["all", "template_train", "template_heldout"])
    parser.add_argument("--template-train-ratio", type=float, default=0.7)
    parser.add_argument("--sample-ids")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = MODEL_CONFIGS[args.model]
    labels = LABEL_PROFILES[args.label_profile]
    loaded = load_dataset(args.dataset)
    selected_samples, split = split_samples_by_template(
        loaded.samples, args.template_split, args.template_train_ratio
    )
    supported_entities = sorted(set(labels.values()))
    samples = select_samples(selected_samples, supported_entities, args)
    run_id = build_gliner_run_id(args.dataset, config["model_id"], scope(args), args.run_suffix)
    predictions_path = Path(args.predictions_dir) / f"{run_id}.jsonl"

    try:
        model = build_model(config, args)
    except Exception as error:
        return write_skipped_report(args, config, loaded, samples, split, labels, predictions_path, error)

    results = run_gliner(model, samples, labels, args)
    write_predictions(predictions_path, results)
    metrics = score_results(results, supported_entities)
    report = build_report(
        run_id=run_id,
        args=args,
        config=config,
        loaded=loaded,
        samples=samples,
        split=split,
        labels=labels,
        supported_entities=supported_entities,
        metrics=metrics,
        predictions_path=predictions_path,
    )
    out_dir = Path(args.out_dir)
    write_json(out_dir / f"{run_id}.json", report)
    (out_dir / f"{run_id}.md").write_text(markdown(report), encoding="utf-8")
    print(
        json.dumps(
            {
                "run_id": run_id,
                "samples": len(samples),
                "metrics": report["metrics"],
                "latency": report["latency"],
            },
            sort_keys=True,
        )
    )
    return 0


def build_model(config: dict[str, Any], args: argparse.Namespace) -> Any:
    if config.get("runtime") == "gliner2":
        try:
            from gliner2 import GLiNER2
        except Exception as error:
            raise RuntimeError(f"missing optional dependency gliner2/torch/transformers: {error}") from error

        model_path = config.get("local_path") or config["model_id"]
        model = GLiNER2.from_pretrained(model_path)
        if args.device != "cpu":
            model.to(args.device)
        return model

    try:
        from gliner import GLiNER
    except Exception as error:
        raise RuntimeError(f"missing optional dependency gliner/torch/transformers: {error}") from error

    load_options = {}
    if config.get("revision"):
        load_options["revision"] = config["revision"]
    model = GLiNER.from_pretrained(config["model_id"], **load_options)
    if args.device != "cpu":
        model.to(args.device)
    return model


def run_gliner(
    model: Any,
    samples: list[dict[str, Any]],
    labels: dict[str, str],
    args: argparse.Namespace,
) -> list[dict[str, Any]]:
    results = []
    label_names = list(labels.keys())
    for sample in samples:
        start = time.perf_counter()
        raw_predictions = predict_entities(model, sample["text"], label_names, args)
        latency_ms = (time.perf_counter() - start) * 1000
        predictions = normalize_predictions(sample["text"], raw_predictions, labels, args)
        results.append(
            {
                "sample": sample,
                "expected": sample["spans"],
                "predicted": predictions,
                "latency_ms": latency_ms,
            }
        )
    return results


def predict_entities(model: Any, text: str, label_names: list[str], args: argparse.Namespace) -> list[dict[str, Any]]:
    if hasattr(model, "extract_entities"):
        result = model.extract_entities(
            text,
            label_names,
            threshold=args.threshold,
            include_confidence=True,
            include_spans=True,
        )
        return flatten_gliner2_result(result)

    return model.predict_entities(
        text,
        label_names,
        threshold=args.threshold,
        flat_ner=True,
        multi_label=False,
        batch_size=args.batch_size,
    )


def flatten_gliner2_result(result: Any) -> list[dict[str, Any]]:
    entities = result.get("entities", {}) if isinstance(result, dict) else {}
    flattened: list[dict[str, Any]] = []

    for label, values in entities.items():
        for value in values or []:
            if not isinstance(value, dict):
                continue
            flattened.append(
                {
                    "label": label,
                    "start": value.get("start"),
                    "end": value.get("end"),
                    "score": value.get("confidence", value.get("score", 0.0)),
                }
            )

    return flattened


def normalize_predictions(
    text: str,
    raw_predictions: list[dict[str, Any]],
    labels: dict[str, str],
    args: argparse.Namespace,
) -> list[dict[str, Any]]:
    predictions = []
    per_label_thresholds = parse_per_label_thresholds(args.per_label_thresholds)
    for prediction in raw_predictions:
        raw_label = normalize_label(prediction.get("label"))
        entity = labels.get(raw_label)
        if not entity:
            continue
        score = float(prediction.get("score", 0.0))
        if score < per_label_thresholds.get(raw_label, args.threshold):
            continue
        start = prediction.get("start")
        end = prediction.get("end")
        if start is None or end is None or start >= end:
            continue
        predictions.append(
            {
                "entity": entity,
                "byte_start": char_to_byte(text, start),
                "byte_end": char_to_byte(text, end),
                "char_start": start,
                "char_end": end,
                "source_entity": raw_label,
                "score": score,
                "value": text[start:end],
                "metadata": {
                    "adapter": "python_gliner",
                    "label_profile": args.label_profile,
                    "threshold": args.threshold,
                },
            }
        )
    return sorted(predictions, key=lambda item: (item["byte_start"], item["byte_end"], item["entity"]))


def parse_per_label_thresholds(value: str) -> dict[str, float]:
    if not value:
        return {}
    return {
        normalize_label(label): float(threshold)
        for item in value.split(",")
        for label, threshold in [item.split("=", 1)]
    }


def normalize_label(label: Any) -> str:
    return str(label or "").strip().lower()


def write_skipped_report(
    args: argparse.Namespace,
    config: dict[str, Any],
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
    labels: dict[str, str],
    predictions_path: Path,
    error: Exception,
) -> int:
    run_id = build_gliner_run_id(args.dataset, config["model_id"], f"skipped_{scope(args)}", args.run_suffix)
    report = skipped_report(run_id, args, config, loaded, samples, split, labels, predictions_path, error)
    out_dir = Path(args.out_dir)
    write_json(out_dir / f"{run_id}.json", report)
    (out_dir / f"{run_id}.md").write_text(markdown(report), encoding="utf-8")
    print(json.dumps({"run_id": run_id, "status": "skipped", "reason": report["limitations"][0]}, sort_keys=True))
    return 0


def skipped_report(
    run_id: str,
    args: argparse.Namespace,
    config: dict[str, Any],
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
    labels: dict[str, str],
    predictions_path: Path,
    error: Exception,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "phase": "python_gliner_reference",
        "timestamp": "2026-06-09T00:00:00Z",
        "git_sha": git_sha(),
        "adapter": "GLiNER.predict_entities",
        "profile": "python_gliner_reference",
        "status": "skipped",
        "model": model_metadata(args, config),
        "dataset": dataset_metadata(args, loaded, samples, split),
        "entity_mapping": entity_mapping(args, labels),
        "offset_mode": offset_mode(),
        "metrics": empty_metrics(len(samples)),
        "per_entity": {},
        "latency": latency_summary([]),
        "examples": {},
        "predictions_path": str(predictions_path),
        "limitations": [
            f"Skipped optional Python GLiNER reference run: {error}",
            "This is a reference benchmark only and is not an Obscura runtime dependency.",
            "Raw text, detected values, credentials, and provider payloads were not written.",
        ],
    }


def build_report(
    *,
    run_id: str,
    args: argparse.Namespace,
    config: dict[str, Any],
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
    labels: dict[str, str],
    supported_entities: list[str],
    metrics: dict[str, Any],
    predictions_path: Path,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "phase": "python_gliner_reference",
        "timestamp": "2026-06-09T00:00:00Z",
        "git_sha": git_sha(),
        "adapter": "GLiNER.predict_entities",
        "profile": "python_gliner_reference",
        "status": "completed",
        "model": model_metadata(args, config),
        "dataset": dataset_metadata(args, loaded, samples, split),
        "entity_mapping": {**entity_mapping(args, labels), "supported_entities": supported_entities},
        "offset_mode": offset_mode(),
        "metrics": {key: value for key, value in metrics.items() if key not in {"per_entity", "latency", "examples"}},
        "per_entity": metrics["per_entity"],
        "latency": metrics["latency"],
        "examples": metrics["examples"],
        "predictions_path": str(predictions_path),
        "limitations": [
            "Direct Python GLiNER reference evaluation run.",
            "This is not Presidio default behavior and is not an Obscura runtime dependency.",
            "Scoring mirrors Obscura exact byte-span metrics for direct report comparison.",
            "Raw text and detected values are omitted from committed reports and prediction exports.",
        ],
    }


def model_metadata(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    return {
        "backend": "Python GLiNER",
        "id": config["model_id"],
        "alias": args.model,
        "architecture": config["architecture"],
        "license": config["license"],
        "runtime": f"Python {sys.version_info.major}.{sys.version_info.minor}",
        "device": args.device,
        "threshold": args.threshold,
        "per_label_thresholds": parse_per_label_thresholds(args.per_label_thresholds),
        "batch_size": args.batch_size,
    }


def dataset_metadata(
    args: argparse.Namespace,
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
) -> dict[str, Any]:
    return {
        "name": loaded.name,
        "source": str(loaded.path),
        "version": loaded.version,
        "sample_count": len(samples),
        "sample_ids": [sample["id"] for sample in samples],
        "full_sample_count": len(loaded.samples),
        "original_sample_count": loaded.original_sample_count,
        "invalid_sample_count": len(loaded.invalid_samples),
        "template_split": split,
        "template_summary": template_summary(samples),
        "smoke": not args.full,
        "scope": scope(args),
    }


def entity_mapping(args: argparse.Namespace, labels: dict[str, str]) -> dict[str, Any]:
    return {
        "version": "python_gliner_reference_v1",
        "label_profile": args.label_profile,
        "source_labels": list(labels.keys()),
        "label_to_obscura_entity": labels,
    }


def offset_mode() -> dict[str, str]:
    return {
        "input": "character",
        "internal": "byte",
        "scoring": "byte",
        "conversion": "validated",
        "matching": "exact_byte_span",
    }


def empty_metrics(total_samples: int) -> dict[str, Any]:
    return {
        "precision": None,
        "recall": None,
        "f1": None,
        "f2": None,
        "true_positives": 0,
        "false_positives": 0,
        "false_negatives": 0,
        "offset_mismatches": 0,
        "wrong_entity_type": 0,
        "unsupported_expected_spans": 0,
        "total_expected_spans": 0,
        "total_supported_expected_spans": 0,
        "total_predicted_spans": 0,
        "total_samples": total_samples,
    }


def build_gliner_run_id(dataset: str, model: str, report_scope: str, suffix: str) -> str:
    run_id = build_run_id(dataset, model, report_scope, suffix)
    return run_id.replace("presidio_python_", "python_gliner_", 1)


def markdown(report: dict[str, Any]) -> str:
    metrics = report["metrics"]
    dataset = report["dataset"]
    latency = report["latency"]
    return f"""# Python GLiNER Reference Evaluation Report

- Run ID: {report["run_id"]}
- Status: {report["status"]}
- Adapter: {report["adapter"]}
- Profile: {report["profile"]}
- Model: {report["model"]["id"]}
- Architecture: {report["model"]["architecture"]}
- Device: {report["model"]["device"]}
- Threshold: {report["model"]["threshold"]}
- Label profile: {report["entity_mapping"]["label_profile"]}
- Dataset: {dataset["name"]}
- Samples: {dataset["sample_count"]}
- Scope: {dataset["scope"]}
- Sample IDs: {", ".join(str(item) for item in dataset["sample_ids"])}
- Predictions: {report["predictions_path"]}

## Metrics

| Metric | Value |
| --- | ---: |
| Precision | {format_metric(metrics["precision"])} |
| Recall | {format_metric(metrics["recall"])} |
| F1 | {format_metric(metrics["f1"])} |
| F2 | {format_metric(metrics["f2"])} |
| True positives | {metrics["true_positives"]} |
| False positives | {metrics["false_positives"]} |
| False negatives | {metrics["false_negatives"]} |
| Offset mismatches | {metrics["offset_mismatches"]} |
| Wrong entity type | {metrics["wrong_entity_type"]} |
| Unsupported expected spans | {metrics["unsupported_expected_spans"]} |

{template_split_markdown(dataset.get("template_split"))}

## Per Entity

{per_entity_markdown(report.get("per_entity", {}))}

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


def per_entity_markdown(per_entity: dict[str, Any]) -> str:
    if not per_entity:
        return "_No per-entity metrics available._"

    lines = [
        "| Entity | Precision | Recall | F1 | F2 | TP | FP | FN | Offset mismatches | Support | Predictions |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for entity, metrics in sorted(per_entity.items()):
        lines.append(
            "| "
            + " | ".join(
                [
                    entity,
                    format_metric(metrics.get("precision")),
                    format_metric(metrics.get("recall")),
                    format_metric(metrics.get("f1")),
                    format_metric(metrics.get("f2")),
                    str(metrics.get("true_positives", 0)),
                    str(metrics.get("false_positives", 0)),
                    str(metrics.get("false_negatives", 0)),
                    str(metrics.get("offset_mismatches", 0)),
                    str(metrics.get("support_count", 0)),
                    str(metrics.get("prediction_count", 0)),
                ]
            )
            + " |"
        )
    return "\n".join(lines)


def limitation_lines(limitations: list[str]) -> str:
    return "\n".join(f"- {item}" for item in limitations)


if __name__ == "__main__":
    sys.exit(main())
