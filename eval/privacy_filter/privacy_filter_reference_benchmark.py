#!/usr/bin/env python3
"""Run the Python OpenAI Privacy Filter reference against Obscura fixtures.

This adapter is evaluation-only. It imports the local `inspiration/privacy-filter`
package when available, requires an explicit local checkpoint, and writes an
Obscura-compatible skipped report when optional Python dependencies or model
assets are missing.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PRESIDIO_ADAPTER = ROOT / "eval" / "presidio_adapter"
PRIVACY_FILTER_SOURCE = ROOT / "inspiration" / "privacy-filter"
sys.path.insert(0, str(PRESIDIO_ADAPTER))

from real_presidio_benchmark import (  # noqa: E402
    LoadedDataset,
    build_run_id as presidio_build_run_id,
    char_to_byte,
    empty_counts,
    format_metric,
    git_sha,
    latency_summary,
    load_dataset,
    scope,
    score_results,
    select_samples,
    split_samples_by_template,
    template_split_markdown,
    template_summary,
    write_json,
    write_predictions,
)
from prepare_opf_reference_checkpoint import prepare_checkpoint  # noqa: E402


LABEL_MAP = {
    "account_number": "account_number",
    "age": "age",
    "api_key": "secret",
    "bank_routing_number": "financial_id",
    "biometric_identifier": "id",
    "certificate_license_number": "id",
    "city": "location",
    "company_name": "organization",
    "coordinate": "location",
    "country": "location",
    "county": "location",
    "credit_debit_card": "credit_card",
    "customer_id": "id",
    "cvv": "credit_card",
    "date_of_birth": "date_time",
    "date_time": "date_time",
    "device_identifier": "device_id",
    "employee_id": "employee_id",
    "fax_number": "phone",
    "first_name": "person",
    "health_plan_beneficiary_number": "health_id",
    "http_cookie": "secret",
    "ipv4": "ip_address",
    "ipv6": "ip_address",
    "last_name": "person",
    "license_plate": "vehicle_id",
    "mac_address": "device_id",
    "medical_record_number": "patient_id",
    "national_id": "id",
    "password": "secret",
    "phone_number": "phone",
    "pin": "secret",
    "postcode": "zip_code",
    "private_address": "address",
    "private_date": "date_time",
    "private_email": "email",
    "private_person": "person",
    "private_phone": "phone",
    "private_url": "url",
    "secret": "secret",
    "ssn": "us_ssn",
    "state": "location",
    "street_address": "street_address",
    "swift_bic": "financial_id",
    "tax_id": "id",
    "time": "date_time",
    "unique_id": "id",
    "user_name": "handle",
    "vehicle_identifier": "vehicle_id",
    "other_person": "person",
    "personal_url": "url",
    "other_url": "url",
    "personal_location": "location",
    "other_location": "location",
    "personal_email": "email",
    "other_email": "email",
    "personal_phone": "phone",
    "other_phone": "phone",
    "personal_date": "date_time",
    "other_date": "date_time",
    "personal_id": "id",
    "personal_name": "person",
    "personal_handle": "handle",
    "personal_org": "organization",
    "personal_gov_id": "id",
    "personal_fin_id": "financial_id",
    "personal_health_id": "health_id",
    "personal_device_id": "device_id",
    "personal_vehicle_id": "vehicle_id",
    "personal_property_id": "property_id",
    "personal_edu_id": "education_id",
    "personal_emp_id": "employee_id",
    "personal_membership_id": "membership_id",
    "personal_registry_id": "registry_id",
    "secret_url": "secret",
    "email": "email",
    "phone": "phone",
    "date": "date_time",
    "url": "url",
    "account": "account_number",
    "patient": "person",
    "staff": "person",
    "hospital": "organization",
    "hosp": "organization",
    "patorg": "organization",
    "id": "id",
}

IGNORED_LABELS = {
    "blood_type": "health attribute; not a current Obscura benchmark entity",
    "education_level": "attribute; not a current Obscura benchmark entity",
    "employment_status": "attribute; not a current Obscura benchmark entity",
    "gender": "sensitive attribute; not a current Obscura benchmark entity",
    "language": "attribute; not a current Obscura benchmark entity",
    "occupation": "attribute; not a current Obscura benchmark entity",
    "political_view": "sensitive attribute; not a current Obscura benchmark entity",
    "race_ethnicity": "sensitive attribute; not a current Obscura benchmark entity",
    "religious_belief": "sensitive attribute; not a current Obscura benchmark entity",
    "sexuality": "sensitive attribute; not a current Obscura benchmark entity",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Python privacy-filter reference and write Obscura-compatible reports."
    )
    parser.add_argument(
        "--dataset",
        default="generated_large",
        choices=["generated_small", "generated_large", "synth_dataset_v2", "nemotron_pii_test_subset"],
    )
    parser.add_argument("--checkpoint", default=os.environ.get("OBSCURA_PRIVACY_FILTER_CHECKPOINT") or os.environ.get("OPF_CHECKPOINT"))
    parser.add_argument("--model-id", default=os.environ.get("OBSCURA_PRIVACY_FILTER_MODEL_ID") or "openai/privacy-filter")
    parser.add_argument("--reference-checkpoint")
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--run-suffix", default="")
    parser.add_argument("--out-dir", default="eval/reports")
    parser.add_argument("--predictions-dir", default="eval/predictions")
    parser.add_argument("--template-split", default="template_heldout", choices=["all", "template_train", "template_heldout"])
    parser.add_argument("--template-train-ratio", type=float, default=0.7)
    parser.add_argument("--sample-ids")
    parser.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    parser.add_argument("--n-ctx", type=int, default=128)
    parser.add_argument("--decode-mode", default="viterbi", choices=["viterbi", "argmax"])
    parser.add_argument("--no-trim-whitespace", action="store_true")
    parser.add_argument("--discard-overlapping-spans", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    loaded = load_dataset(args.dataset)
    selected_samples, split = split_samples_by_template(
        loaded.samples, args.template_split, args.template_train_ratio
    )
    supported_entities = sorted(set(LABEL_MAP.values()))
    samples = select_samples(selected_samples, supported_entities, args)
    run_id = build_run_id(args.dataset, args.model_id, scope(args), args.run_suffix)
    predictions_path = Path(args.predictions_dir) / f"{run_id}.jsonl"

    try:
        redactor = build_redactor(args)
    except Exception as error:
        return write_skipped_report(args, loaded, samples, split, predictions_path, error)

    try:
        results = run_privacy_filter(redactor, samples, args)
    except Exception as error:
        return write_skipped_report(args, loaded, samples, split, predictions_path, error)

    write_predictions(predictions_path, results)
    metrics = score_results(results, supported_entities)
    report = build_report(
        run_id=run_id,
        args=args,
        loaded=loaded,
        samples=samples,
        split=split,
        supported_entities=supported_entities,
        metrics=metrics,
        predictions_path=predictions_path,
    )
    out_dir = Path(args.out_dir)
    write_json(out_dir / f"{run_id}.json", report)
    (out_dir / f"{run_id}.md").write_text(markdown(report), encoding="utf-8")
    print(json.dumps({"run_id": run_id, "samples": len(samples), "metrics": report["metrics"]}, sort_keys=True))
    return 0


def build_redactor(args: argparse.Namespace) -> Any:
    checkpoint = args.checkpoint
    if not checkpoint:
        raise RuntimeError("missing --checkpoint, OBSCURA_PRIVACY_FILTER_CHECKPOINT, or OPF_CHECKPOINT")
    checkpoint_path = Path(checkpoint)
    if not checkpoint_path.is_dir():
        raise RuntimeError(f"checkpoint directory not found: {checkpoint}")
    if not (checkpoint_path / "config.json").is_file():
        raise RuntimeError(f"missing checkpoint config: {checkpoint_path / 'config.json'}")
    if not any(checkpoint_path.glob("*.safetensors")):
        raise RuntimeError(f"checkpoint directory has no .safetensors files: {checkpoint}")

    runtime_checkpoint = prepare_runtime_checkpoint(checkpoint_path, args)
    setattr(args, "runtime_checkpoint", str(runtime_checkpoint))

    sys.path.insert(0, str(PRIVACY_FILTER_SOURCE))
    try:
        from opf import OPF
    except Exception as error:
        raise RuntimeError(f"missing optional Python privacy-filter dependencies: {error}") from error

    return OPF(
        model=str(runtime_checkpoint),
        context_window_length=args.n_ctx,
        trim_whitespace=not args.no_trim_whitespace,
        device=args.device,
        output_mode="typed",
        decode_mode=args.decode_mode,
        discard_overlapping_predicted_spans=args.discard_overlapping_spans,
        output_text_only=False,
    )


def prepare_runtime_checkpoint(checkpoint_path: Path, args: argparse.Namespace) -> Path:
    output = (
        Path(args.reference_checkpoint)
        if args.reference_checkpoint
        else checkpoint_path.with_name(f"{checkpoint_path.name}-opf-reference")
    )

    summary = prepare_checkpoint(checkpoint_path, output)
    setattr(args, "reference_checkpoint_summary", summary)
    return output


def run_privacy_filter(redactor: Any, samples: list[dict[str, Any]], args: argparse.Namespace) -> list[dict[str, Any]]:
    results = []
    for sample in samples:
        start = time.perf_counter()
        raw_result = redactor.redact(sample["text"])
        latency_ms = (time.perf_counter() - start) * 1000
        predictions = normalize_predictions(sample["text"], raw_result, args)
        results.append(
            {
                "sample": sample,
                "expected": sample["spans"],
                "predicted": predictions,
                "latency_ms": latency_ms,
            }
        )
    return results


def normalize_predictions(text: str, raw_result: Any, args: argparse.Namespace) -> list[dict[str, Any]]:
    predictions = []
    for span in getattr(raw_result, "detected_spans", ()):
        label = str(getattr(span, "label", ""))
        entity = LABEL_MAP.get(label)
        if not entity:
            continue
        start = int(getattr(span, "start"))
        end = int(getattr(span, "end"))
        if start < 0 or end <= start:
            continue
        predictions.append(
            {
                "entity": entity,
                "byte_start": char_to_byte(text, start),
                "byte_end": char_to_byte(text, end),
                "char_start": start,
                "char_end": end,
                "source_entity": label,
                "score": None,
                "value": text[start:end],
                "metadata": {
                    "adapter": "python_opf",
                    "decode_mode": args.decode_mode,
                    "n_ctx": args.n_ctx,
                },
            }
        )
    return sorted(predictions, key=lambda item: (item["byte_start"], item["byte_end"], item["entity"]))


def write_skipped_report(
    args: argparse.Namespace,
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
    predictions_path: Path,
    error: Exception,
) -> int:
    run_id = build_run_id(args.dataset, args.model_id, f"skipped_{scope(args)}", args.run_suffix)
    report = skipped_report(run_id, args, loaded, samples, split, predictions_path, error)
    out_dir = Path(args.out_dir)
    write_json(out_dir / f"{run_id}.json", report)
    (out_dir / f"{run_id}.md").write_text(markdown(report), encoding="utf-8")
    print(json.dumps({"run_id": run_id, "status": "skipped", "reason": report["limitations"][0]}, sort_keys=True))
    return 0


def skipped_report(
    run_id: str,
    args: argparse.Namespace,
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
    predictions_path: Path,
    error: Exception,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "phase": "privacy_filter_python_reference",
        "timestamp": "2026-06-11T00:00:00Z",
        "git_sha": git_sha(),
        "adapter": "Python.OPF",
        "profile": "privacy_filter_python_reference",
        "status": "skipped",
        "model": model_metadata(args),
        "policy": policy_metadata(args),
        "dataset": dataset_metadata(args, loaded, samples, split),
        "entity_mapping": entity_mapping(),
        "offset_mode": offset_mode(),
        "metrics": empty_metrics(len(samples)),
        "per_entity": {},
        "latency": latency_summary([]),
        "examples": {},
        "predictions_path": str(predictions_path),
        "skip_reason": skip_reason(error),
        "limitations": [
            f"Skipped optional Python privacy-filter reference run: {error}",
            "This adapter is evaluation-only and is not an Obscura runtime dependency.",
            "The runner requires an explicit local checkpoint and will not auto-download model assets.",
            "Raw text and detected values are omitted from committed reports and prediction exports.",
        ],
    }


def skip_reason(error: Exception) -> dict[str, str]:
    message = str(error)
    return {
        "category": skip_reason_category(message),
        "message": f"Skipped optional Python privacy-filter reference run: {message}",
    }


def skip_reason_category(message: str) -> str:
    lowered = message.lower()
    if "optional" in lowered and "depend" in lowered:
        return "optional_dependency_missing"
    if "no .safetensors" in lowered or "missing" in lowered and "safetensors" in lowered:
        return "checkpoint_missing"
    if "encoding must be" in lowered or "missing checkpoint config" in lowered:
        return "checkpoint_config_invalid"
    if "incomplete" in lowered or "safetensor" in lowered and "header" in lowered:
        return "checkpoint_incomplete"
    return "run_failed"


def build_report(
    *,
    run_id: str,
    args: argparse.Namespace,
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
    supported_entities: list[str],
    metrics: dict[str, Any],
    predictions_path: Path,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "phase": "privacy_filter_python_reference",
        "timestamp": "2026-06-11T00:00:00Z",
        "git_sha": git_sha(),
        "adapter": "Python.OPF",
        "profile": "privacy_filter_python_reference",
        "status": "completed",
        "model": model_metadata(args),
        "policy": policy_metadata(args),
        "dataset": dataset_metadata(args, loaded, samples, split),
        "entity_mapping": {**entity_mapping(), "supported_entities": supported_entities},
        "offset_mode": offset_mode(),
        "metrics": {key: value for key, value in metrics.items() if key not in {"per_entity", "latency", "examples"}},
        "per_entity": metrics["per_entity"],
        "latency": metrics["latency"],
        "examples": metrics["examples"],
        "predictions_path": str(predictions_path),
        "limitations": [
            "Python privacy-filter reference run using local OPF runtime.",
            "This adapter is evaluation-only and is not an Obscura runtime dependency.",
            "Scoring mirrors Obscura exact byte-span metrics for direct report comparison.",
            "Raw text and detected values are omitted from committed reports and prediction exports.",
        ],
    }


def model_metadata(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "backend": "PyTorch",
        "id": args.model_id,
        "architecture": "OpenAIPrivacyFilterForTokenClassification",
        "license": "apache-2.0",
        "runtime": f"Python {sys.version_info.major}.{sys.version_info.minor}",
        "checkpoint": args.checkpoint,
        "runtime_checkpoint": getattr(args, "runtime_checkpoint", None),
        "reference_checkpoint_summary": getattr(args, "reference_checkpoint_summary", None),
        "source": str(PRIVACY_FILTER_SOURCE),
    }


def policy_metadata(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "decode_mode": args.decode_mode,
        "n_ctx": args.n_ctx,
        "device": args.device,
        "trim_whitespace": not args.no_trim_whitespace,
        "discard_overlapping_spans": args.discard_overlapping_spans,
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


def entity_mapping() -> dict[str, Any]:
    return {
        "version": "privacy_filter_python_reference_v1",
        "label_map": LABEL_MAP,
        "ignored_labels": IGNORED_LABELS,
        "supported_source_entities": sorted(LABEL_MAP),
        "supported_entities": sorted(set(LABEL_MAP.values())),
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
    counts = empty_counts(total_samples)
    return {**counts, "precision": None, "recall": None, "f1": None, "f2": None}


def markdown(report: dict[str, Any]) -> str:
    metrics = report["metrics"]
    dataset = report["dataset"]
    latency = report["latency"]
    return f"""# Python Privacy-Filter Reference Evaluation Report

- Run ID: {report["run_id"]}
- Status: {report["status"]}
- Adapter: {report["adapter"]}
- Profile: {report["profile"]}
- Model: {report["model"]["id"]}
- Dataset: {dataset["name"]}
- Samples: {dataset["sample_count"]}
- Scope: {dataset["scope"]}
- Sample IDs: {", ".join(str(item) for item in dataset["sample_ids"])}
- Predictions: {report["predictions_path"]}
- Policy: decode_mode={report["policy"]["decode_mode"]}, n_ctx={report["policy"]["n_ctx"]}, device={report["policy"]["device"]}

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


def limitation_lines(limitations: list[str]) -> str:
    return "\n".join(f"- {item}" for item in limitations)


def build_run_id(dataset: str, model: str, run_scope: str, suffix: str) -> str:
    base = presidio_build_run_id(dataset, model, run_scope, suffix)
    return base.replace("presidio_python_", "privacy_filter_python_", 1)


if __name__ == "__main__":
    sys.exit(main())
