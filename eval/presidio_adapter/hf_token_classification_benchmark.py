#!/usr/bin/env python3
"""Run optional Hugging Face token-classification models against Presidio-Research fixtures.

This adapter is evaluation-only. It is intentionally not a runtime dependency for
Obscura, and it writes skipped reports when optional Python dependencies or model
architectures are unavailable.
"""

from __future__ import annotations

import argparse
import json
import string
import subprocess
import sys
import time
from datetime import datetime, timezone
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
    safe_name,
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
    "openai_privacy_filter": {
        "model_id": "openai/privacy-filter",
        "architecture": "OpenAIPrivacyFilterForTokenClassification",
        "license": "apache-2.0",
        "label_map": {
            "private_person": "person",
            "private_address": "location",
            "private_email": "email",
            "private_phone": "phone",
            "private_url": "url",
            "private_date": "date_time",
        },
    },
    "openmed_privacy_filter_nemotron": {
        "model_id": "OpenMed/privacy-filter-nemotron",
        "architecture": "OpenAIPrivacyFilterForTokenClassification",
        "license": "apache-2.0",
        "label_map": "openmed",
    },
    "openmed_pii_superclinical_small": {
        "model_id": "OpenMed/OpenMed-PII-SuperClinical-Small-44M-v1",
        "architecture": "DebertaV2ForTokenClassification",
        "license": "apache-2.0",
        "label_map": "openmed",
    },
    "openmed_pii_superclinical_large": {
        "model_id": "OpenMed/OpenMed-PII-SuperClinical-Large-434M-v1",
        "architecture": "DebertaV2ForTokenClassification",
        "license": "apache-2.0",
        "label_map": "openmed",
    },
    "openmed_pii_bigmed_large": {
        "model_id": "OpenMed/OpenMed-PII-BigMed-Large-560M-v1",
        "architecture": "XLMRobertaForTokenClassification",
        "license": "apache-2.0",
        "label_map": "openmed",
    },
    "stanford_deidentifier_base": {
        "model_id": "StanfordAIMI/stanford-deidentifier-base",
        "architecture": "Bert/AutoModel token-classification config",
        "license": "mit",
        "label_map": {
            "PATIENT": "person",
            "HCW": "person",
            "VENDOR": "organization",
            "HOSPITAL": "location",
            "DATE": "date_time",
            "PHONE": "phone",
        },
        "notes": [
            "Presidio transformers.yaml maps ID to ID with low confidence; Obscura ignores ID here because there is no stable generic ID entity in this profile.",
            "The current model id2label does not emit STAFF, HOSP, PATORG, FACILITY, EMAIL, or TIME even though Presidio's generic transformer mapping includes those aliases.",
        ],
    },
    "piiranha_v1": {
        "model_id": "iiiorg/piiranha-v1-detect-personal-information",
        "revision": "255acde67a2f34cf452eb42e365b24d2957352fc",
        "architecture": "DebertaV2ForTokenClassification",
        "license": "cc-by-nc-nd-4.0",
        "max_length": 256,
        "label_map": "piiranha",
        "notes": [
            "The checkpoint is non-commercial and no-derivatives; it is evaluation-only.",
            "The model has no organization label and cannot improve organization recall directly.",
        ],
    },
}

OPENMED_LABEL_MAP = {
    "first_name": "person",
    "last_name": "person",
    "company_name": "organization",
    "city": "location",
    "coordinate": "location",
    "country": "location",
    "county": "location",
    "postcode": "location",
    "state": "location",
    "street_address": "location",
    "private_address": "location",
    "email": "email",
    "private_email": "email",
    "phone_number": "phone",
    "fax_number": "phone",
    "private_phone": "phone",
    "credit_debit_card": "credit_card",
    "cvv": "credit_card",
    "ssn": "us_ssn",
    "ipv4": "ip_address",
    "ipv6": "ip_address",
    "url": "url",
    "private_url": "url",
    "date": "date_time",
    "date_of_birth": "date_time",
    "date_time": "date_time",
    "time": "date_time",
    "private_date": "date_time",
    "medical_record_number": "patient_id",
    "health_plan_beneficiary_number": "patient_id",
}

PIIRANHA_LABEL_MAP = {
    "ACCOUNTNUM": "id",
    "BUILDINGNUM": "street_address",
    "CITY": "location",
    "CREDITCARDNUMBER": "credit_card",
    "DATEOFBIRTH": "date_time",
    "DRIVERLICENSENUM": "us_driver_license",
    "EMAIL": "email",
    "GIVENNAME": "person",
    "IDCARDNUM": "id",
    "PASSWORD": "password",
    "SOCIALNUM": "us_ssn",
    "STREET": "street_address",
    "SURNAME": "person",
    "TAXNUM": "id",
    "TELEPHONENUM": "phone",
    "USERNAME": "username",
    "ZIPCODE": "zip_code",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run optional HF token-classification models and write Obscura-compatible reports."
    )
    parser.add_argument(
        "--dataset",
        default="generated_large",
        choices=["generated_small", "generated_large", "synth_dataset_v2", "nemotron_pii_test_subset"],
    )
    parser.add_argument("--model", required=True, choices=sorted(MODEL_CONFIGS))
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--run-suffix", default="")
    parser.add_argument("--out-dir", default="eval/reports")
    parser.add_argument("--predictions-dir", default="eval/predictions")
    parser.add_argument("--template-split", default="template_heldout", choices=["all", "template_train", "template_heldout"])
    parser.add_argument("--template-train-ratio", type=float, default=0.7)
    parser.add_argument("--sample-ids")
    parser.add_argument("--device", type=int, default=-1)
    parser.add_argument("--trust-remote-code", action="store_true")
    parser.add_argument("--min-score", type=float, default=0.0)
    parser.add_argument(
        "--trim-boundaries",
        action="store_true",
        help="Trim leading/trailing whitespace and punctuation from predicted spans before scoring.",
    )
    parser.add_argument(
        "--per-label-thresholds",
        default="",
        help="Comma-separated normalized label thresholds, for example HCW=0.90,HOSPITAL=0.98",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = MODEL_CONFIGS[args.model]
    loaded = load_dataset(args.dataset)
    selected_samples, split = split_samples_by_template(
        loaded.samples, args.template_split, args.template_train_ratio
    )
    supported_entities = sorted(set(label_map(config).values()))
    samples = select_samples(selected_samples, supported_entities, args)
    run_id = build_run_id(args.dataset, config["model_id"], scope(args), args.run_suffix)
    predictions_path = Path(args.predictions_dir) / f"{run_id}.jsonl"

    try:
        classifier = build_pipeline(config, args)
    except Exception as error:
        return write_skipped_report(args, config, loaded, samples, split, predictions_path, error)

    results = run_classifier(classifier, samples, config, args)
    write_predictions(predictions_path, results)
    metrics = score_results(results, supported_entities)
    report = build_report(
        run_id=run_id,
        args=args,
        config=config,
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


def build_pipeline(config: dict[str, Any], args: argparse.Namespace) -> Any:
    try:
        from transformers import AutoTokenizer, pipeline
    except Exception as error:
        raise RuntimeError(f"missing optional dependency transformers/torch: {error}") from error

    kwargs = {
        "task": "token-classification",
        "model": config["model_id"],
        "tokenizer": config["model_id"],
        "aggregation_strategy": "simple",
        "device": args.device,
    }
    if config.get("max_length"):
        tokenizer = AutoTokenizer.from_pretrained(
            config["model_id"], revision=config.get("revision"), use_fast=True
        )
        tokenizer.model_max_length = config["max_length"]
        kwargs["tokenizer"] = tokenizer
    if config.get("revision"):
        kwargs["revision"] = config["revision"]
    if args.trust_remote_code:
        kwargs["trust_remote_code"] = True
    return pipeline(**kwargs)


def run_classifier(
    classifier: Any, samples: list[dict[str, Any]], config: dict[str, Any], args: argparse.Namespace
) -> list[dict[str, Any]]:
    results = []
    for sample in samples:
        start = time.perf_counter()
        raw_predictions = classifier(sample["text"])
        latency_ms = (time.perf_counter() - start) * 1000
        predictions = normalize_predictions(sample["text"], raw_predictions, config, args)
        results.append(
            {
                "sample": sample,
                "expected": sample["spans"],
                "predicted": predictions,
                "latency_ms": latency_ms,
            }
        )
    return results


def normalize_predictions(
    text: str, raw_predictions: list[dict[str, Any]], config: dict[str, Any], args: argparse.Namespace
) -> list[dict[str, Any]]:
    predictions = []
    mapping = label_map(config)
    thresholds = parse_label_thresholds(args.per_label_thresholds)
    for prediction in raw_predictions:
        raw_label = prediction.get("entity_group") or prediction.get("entity") or prediction.get("label")
        label = normalize_label(raw_label)
        entity = mapping.get(label)
        if not entity:
            continue
        score = float(prediction.get("score", 0.0))
        threshold = thresholds.get(label, args.min_score)
        if score < threshold:
            continue
        start = prediction.get("start")
        end = prediction.get("end")
        if start is None or end is None or start >= end:
            continue
        adjusted_start, adjusted_end = trim_boundaries(text, start, end) if args.trim_boundaries else (start, end)
        if adjusted_start >= adjusted_end:
            continue
        predictions.append(
            {
                "entity": entity,
                "byte_start": char_to_byte(text, adjusted_start),
                "byte_end": char_to_byte(text, adjusted_end),
                "char_start": adjusted_start,
                "char_end": adjusted_end,
                "source_entity": raw_label,
                "score": score,
                "value": text[adjusted_start:adjusted_end],
                "metadata": {
                    "model_id": config["model_id"],
                    "score_threshold": threshold,
                    "threshold_label": label if label in thresholds else None,
                    "boundary_trimmed": (adjusted_start, adjusted_end) != (start, end),
                    "raw_char_start": start,
                    "raw_char_end": end,
                },
            }
        )
    return sorted(predictions, key=lambda item: (item["byte_start"], item["byte_end"], item["entity"]))


def trim_boundaries(text: str, start: int, end: int) -> tuple[int, int]:
    trim_chars = set(string.whitespace + ".,;:!?()[]{}<>\"'`")
    while start < end and text[start] in trim_chars:
        start += 1
    while end > start and text[end - 1] in trim_chars:
        end -= 1
    return start, end


def normalize_label(label: Any) -> str:
    value = str(label or "")
    for prefix in ("B-", "I-", "E-", "S-"):
        if value.startswith(prefix):
            return value[len(prefix):]
    return value


def label_map(config: dict[str, Any]) -> dict[str, str]:
    configured = config["label_map"]
    if configured == "openmed":
        return OPENMED_LABEL_MAP
    if configured == "piiranha":
        return PIIRANHA_LABEL_MAP
    return configured


def timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_label_thresholds(value: str) -> dict[str, float]:
    if not value:
        return {}
    thresholds: dict[str, float] = {}
    for item in value.split(","):
        if not item.strip():
            continue
        if "=" not in item:
            raise ValueError(f"invalid --per-label-thresholds item {item!r}")
        label, threshold = item.split("=", 1)
        thresholds[label.strip()] = float(threshold)
    return thresholds


def write_skipped_report(
    args: argparse.Namespace,
    config: dict[str, Any],
    loaded: LoadedDataset,
    samples: list[dict[str, Any]],
    split: dict[str, Any],
    predictions_path: Path,
    error: Exception,
) -> int:
    run_id = build_run_id(args.dataset, config["model_id"], f"skipped_{scope(args)}", args.run_suffix)
    report = skipped_report(run_id, args, config, loaded, samples, split, predictions_path, error)
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
    predictions_path: Path,
    error: Exception,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "phase": "hf_token_classification_compatibility",
        "timestamp": timestamp(),
        "git_sha": git_sha(),
        "adapter": "HuggingFace.Transformers.TokenClassificationPipeline",
        "profile": "hf_token_classification",
        "status": "skipped",
        "model": model_metadata(args, config),
        "policy": policy_metadata(args),
        "dataset": dataset_metadata(args, loaded, samples, split),
        "entity_mapping": {
            "version": "presidio_quality_v11_hf_token_classification",
            "supported_entities": sorted(set(label_map(config).values())),
        },
        "offset_mode": offset_mode(),
        "metrics": empty_metrics(len(samples)),
        "per_entity": {},
        "latency": latency_summary([]),
        "examples": {},
        "predictions_path": str(predictions_path),
        "limitations": [
            f"Skipped optional Python/HF token-classification run: {error}",
            "This adapter is evaluation-only and is not a default Obscura runtime dependency.",
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
    supported_entities: list[str],
    metrics: dict[str, Any],
    predictions_path: Path,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "phase": "hf_token_classification_compatibility",
        "timestamp": timestamp(),
        "git_sha": git_sha(),
        "adapter": "HuggingFace.Transformers.TokenClassificationPipeline",
        "profile": "hf_token_classification",
        "status": "completed",
        "model": model_metadata(args, config),
        "policy": policy_metadata(args),
        "dataset": dataset_metadata(args, loaded, samples, split),
        "entity_mapping": {
            "version": "presidio_quality_v11_hf_token_classification",
            "supported_entities": supported_entities,
        },
        "offset_mode": offset_mode(),
        "metrics": {key: value for key, value in metrics.items() if key not in {"per_entity", "latency", "examples"}},
        "per_entity": metrics["per_entity"],
        "latency": metrics["latency"],
        "examples": metrics["examples"],
        "predictions_path": str(predictions_path),
        "limitations": [
            "Optional local Python/HF token-classification evaluation run.",
            "This adapter is not a default Obscura runtime dependency.",
            "Scoring mirrors Obscura exact byte-span metrics for direct report comparison.",
            "Raw text and detected values are omitted from committed reports and prediction exports.",
        ],
    }


def model_metadata(args: argparse.Namespace, config: dict[str, Any]) -> dict[str, Any]:
    return {
        "backend": "HuggingFace Transformers",
        "id": config["model_id"],
        "alias": args.model,
        "architecture": config["architecture"],
        "license": config["license"],
        "runtime": f"Python {sys.version_info.major}.{sys.version_info.minor}",
        "trust_remote_code": args.trust_remote_code,
        "revision": config.get("revision"),
        "max_length": config.get("max_length"),
    }


def policy_metadata(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "min_score": args.min_score,
        "per_label_thresholds": parse_label_thresholds(args.per_label_thresholds),
        "trim_boundaries": args.trim_boundaries,
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


def markdown(report: dict[str, Any]) -> str:
    metrics = report["metrics"]
    dataset = report["dataset"]
    latency = report["latency"]
    return f"""# Hugging Face Token Classification Evaluation Report

- Run ID: {report["run_id"]}
- Status: {report["status"]}
- Adapter: {report["adapter"]}
- Profile: {report["profile"]}
- Model: {report["model"]["id"]}
- Architecture: {report["model"]["architecture"]}
- Dataset: {dataset["name"]}
- Samples: {dataset["sample_count"]}
- Scope: {dataset["scope"]}
- Sample IDs: {", ".join(str(item) for item in dataset["sample_ids"])}
- Predictions: {report["predictions_path"]}
- Policy: min_score={report["policy"]["min_score"]}, per_label_thresholds={report["policy"]["per_label_thresholds"]}

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


if __name__ == "__main__":
    sys.exit(main())
