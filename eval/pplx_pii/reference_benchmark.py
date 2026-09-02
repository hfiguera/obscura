#!/usr/bin/env python3
"""Evaluate Perplexity's pinned PII masking model against Obscura datasets."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.metadata
import importlib.util
import json
import platform
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PRESIDIO_ADAPTER = ROOT / "eval" / "presidio_adapter" / "real_presidio_benchmark.py"

MODEL_ID = "perplexity-ai/pplx-pii-masking"
MODEL_REVISION = "1e6bb1edd41e03668c6931122be96df893141965"
BACKBONE_ID = "perplexity-ai/pplx-embed-v1-0.6b"
BACKBONE_REVISION = "2c4d510dd4a732063c31a0f70193e35067b51fd8"

MODEL_HASHES = {
    "config.json": "8ea95a30e80050b92f9e6f0be34b8db2a092a3dab825fe9c4e8ee3c574f4bca8",
    "example_usage.py": "64f16301fb32ec5dc6a3a1d2b426d11a00b1ca14fef658d2f5d81a845d6e804d",
    "model.safetensors": "f6204155ec540c9323f706e284110ee848b462f0325dc1ece5c7263fc517bbd0",
    "tokenizer.json": "cae14d1c8dda080f23792355b0692b826bf1f1da3c86ebc1b37548a391cf6526",
    "tokenizer_config.json": "aa9c1b0a1c9b48c2f70bacdf64f7dab25194be4ffea0c6a6e4da262360a91d0a",
}

BACKBONE_HASHES = {
    "config.json": "f7865547ecc1c077c5b1f83913fb9816a6586c676ccf3e0f7f00105a1b0c1c6c",
    "configuration.py": "e914aa73614c91703364c77917313da0821ea04a14d73a7836b5cb40abab1671",
    "model.safetensors": "2c8d2f64f8268ccd5383b7f9bea8e660349aa6a151bd68a5a47f4c129f2a4974",
    "modeling.py": "baf57b645c7ca3f9e2bd57bd0de82c540c7b455665f1b0ef5ee2f29d60cb8ed5",
}

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

# This is intentionally conservative. account_number is broader than either
# credit_card or us_ssn, so pretending it is one of those would inflate typed
# compatibility. A hybrid can refine that label with deterministic recognizers.
ENTITY_MAP = {
    "private_person": "person",
    "private_email": "email",
    "private_phone": "phone",
    "private_address": "location",
    "private_url": "url",
    "private_date": "date_time",
    "account_number": "account_number",
    "secret": "secret",
    "other_pii": "other_pii",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=sorted(SELECTIONS), required=True)
    parser.add_argument("--device", choices=["cpu", "mps"], default="cpu")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--fix-tokenizer-regex", action="store_true")
    parser.add_argument(
        "--cache-dir", default=str(ROOT / ".cache" / "pplx-pii" / "benchmark")
    )
    parser.add_argument("--model-dir")
    parser.add_argument("--backbone-dir")
    parser.add_argument("--out-dir", default=str(ROOT / "eval" / "reports"))
    parser.add_argument(
        "--predictions-out",
        help="Write a raw-text-free prediction artifact for hybrid evaluation.",
    )
    parser.add_argument("--run-suffix", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    presidio = load_python_module("obscura_presidio_adapter", PRESIDIO_ADAPTER)
    loaded = presidio.load_dataset(args.dataset)
    selection_path = SELECTIONS[args.dataset]
    selection = presidio.load_selection(str(selection_path), loaded)
    samples = presidio.selected_samples_from_selection(loaded.samples, selection)
    if not args.full:
        samples = samples[: args.limit]

    model_dir, backbone_dir = resolve_model_dirs(args)
    verify_hashes(model_dir, MODEL_HASHES, "model")
    verify_hashes(backbone_dir, BACKBONE_HASHES, "backbone")
    reference = load_python_module("pplx_pii_reference", model_dir / "example_usage.py")
    reference.BACKBONE_REPO = str(backbone_dir)

    masker = reference.PiiMasker(model_dir, device=args.device)
    if args.fix_tokenizer_regex:
        from transformers import AutoTokenizer

        masker.tokenizer = AutoTokenizer.from_pretrained(
            model_dir, fix_mistral_regex=True
        )

    for _ in range(max(args.warmup, 0)):
        if samples:
            masker(samples[0]["text"])

    results = run_model(masker, samples, presidio.char_to_byte)
    if args.predictions_out:
        write_prediction_artifact(
            Path(args.predictions_out),
            args.dataset,
            selection_path,
            results,
        )
    supported_entities = selection["entity_policy"]["entities"]
    typed_results = typed_protocol_results(results, supported_entities)
    typed = presidio.score_results(typed_results, supported_entities)
    untyped_exact = score_untyped_exact(results)
    character = score_characters(results)
    report = build_report(
        args=args,
        loaded=loaded,
        selection=selection,
        selection_path=selection_path,
        samples=samples,
        results=results,
        typed=typed,
        untyped_exact=untyped_exact,
        character=character,
        model_dir=model_dir,
        backbone_dir=backbone_dir,
    )
    out_path = write_report(report, Path(args.out_dir))
    print(
        json.dumps(
            {
                "report": str(out_path),
                "samples": len(samples),
                "typed_exact": compact_metrics(typed),
                "label_agnostic_exact": untyped_exact,
                "label_agnostic_character": character,
                "latency": typed["latency"],
            },
            sort_keys=True,
        )
    )
    return 0


def resolve_model_dirs(args: argparse.Namespace) -> tuple[Path, Path]:
    if bool(args.model_dir) != bool(args.backbone_dir):
        raise SystemExit("--model-dir and --backbone-dir must be supplied together")
    if args.model_dir:
        return Path(args.model_dir).resolve(), Path(args.backbone_dir).resolve()

    from huggingface_hub import snapshot_download

    cache_dir = Path(args.cache_dir).resolve()
    model_dir = snapshot_download(
        repo_id=MODEL_ID,
        revision=MODEL_REVISION,
        local_dir=cache_dir / "model",
        local_files_only=args.offline,
    )
    backbone_dir = snapshot_download(
        repo_id=BACKBONE_ID,
        revision=BACKBONE_REVISION,
        local_dir=cache_dir / "backbone",
        local_files_only=args.offline,
        allow_patterns=[
            "config.json",
            "configuration.py",
            "model.safetensors",
            "modeling.py",
        ],
    )
    return Path(model_dir).resolve(), Path(backbone_dir).resolve()


def verify_hashes(directory: Path, expected: dict[str, str], label: str) -> None:
    for name, wanted in expected.items():
        path = directory / name
        if not path.is_file():
            raise SystemExit(f"missing pinned {label} file: {path}")
        actual = sha256_file(path)
        if actual != wanted:
            raise SystemExit(
                f"{label} hash mismatch for {name}: expected {wanted}, got {actual}"
            )


def load_python_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def run_model(
    masker: Any, samples: list[dict[str, Any]], char_to_byte: Any
) -> list[dict[str, Any]]:
    results = []
    for sample in samples:
        start = time.perf_counter()
        spans, sensitivity = masker(sample["text"])
        latency_ms = (time.perf_counter() - start) * 1000
        predicted = [
            {
                "entity": ENTITY_MAP[span.label],
                "source_entity": span.label,
                "char_start": span.start,
                "char_end": span.end,
                "byte_start": char_to_byte(sample["text"], span.start),
                "byte_end": char_to_byte(sample["text"], span.end),
                "score": span.score,
                "metadata": {},
            }
            for span in spans
        ]
        results.append(
            {
                "sample": {"id": sample["id"]},
                "expected": sample["spans"],
                "predicted": predicted,
                "sensitivity": sensitivity,
                "latency_ms": latency_ms,
            }
        )
    return results


def typed_protocol_results(
    results: list[dict[str, Any]], supported_entities: list[str]
) -> list[dict[str, Any]]:
    supported = set(supported_entities)
    return [
        {
            **result,
            "predicted": [
                span for span in result["predicted"] if span["entity"] in supported
            ],
        }
        for result in results
    ]


def write_prediction_artifact(
    path: Path,
    dataset: str,
    selection_path: Path,
    results: list[dict[str, Any]],
) -> None:
    artifact = {
        "schema_version": 1,
        "producer": "perplexity-ai/pplx-pii-masking",
        "model_revision": MODEL_REVISION,
        "dataset": dataset,
        "selection_sha256": sha256_file(selection_path),
        "rows": [
            {
                "sample_id": result["sample"]["id"],
                "latency_ms": result["latency_ms"],
                "predictions": [
                    {
                        "entity": span["entity"],
                        "source_entity": span["source_entity"],
                        "char_start": span["char_start"],
                        "char_end": span["char_end"],
                        "byte_start": span["byte_start"],
                        "byte_end": span["byte_end"],
                        "score": span["score"],
                    }
                    for span in result["predicted"]
                ],
            }
            for result in results
        ],
        "raw_text_omitted": True,
    }
    assert_raw_omitted(artifact)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def score_characters(results: list[dict[str, Any]]) -> dict[str, Any]:
    tp = fp = fn = 0
    pii_free_samples = pii_free_false_positives = 0
    for result in results:
        expected = character_positions(result["expected"])
        predicted = character_positions(result["predicted"])
        tp += len(expected & predicted)
        fp += len(predicted - expected)
        fn += len(expected - predicted)
        if not expected:
            pii_free_samples += 1
            if predicted:
                pii_free_false_positives += 1

    precision = divide(tp, tp + fp)
    recall = divide(tp, tp + fn)
    return {
        "true_positive_characters": tp,
        "false_positive_characters": fp,
        "false_negative_characters": fn,
        "precision": precision,
        "recall": recall,
        "f1": f1(precision, recall),
        "pii_free_samples": pii_free_samples,
        "pii_free_false_positive_samples": pii_free_false_positives,
        "pii_free_false_positive_rate": divide(
            pii_free_false_positives, pii_free_samples
        ),
    }


def score_untyped_exact(results: list[dict[str, Any]]) -> dict[str, Any]:
    tp = fp = fn = 0
    for result in results:
        expected = Counter(
            (span["char_start"], span["char_end"]) for span in result["expected"]
        )
        predicted = Counter(
            (span["char_start"], span["char_end"]) for span in result["predicted"]
        )
        matches = expected & predicted
        tp += sum(matches.values())
        fp += sum((predicted - expected).values())
        fn += sum((expected - predicted).values())

    precision = divide(tp, tp + fp)
    recall = divide(tp, tp + fn)
    return {
        "true_positives": tp,
        "false_positives": fp,
        "false_negatives": fn,
        "precision": precision,
        "recall": recall,
        "f1": f1(precision, recall),
    }


def character_positions(spans: Any) -> set[int]:
    positions: set[int] = set()
    for span in spans:
        positions.update(range(span["char_start"], span["char_end"]))
    return positions


def build_report(
    *,
    args: argparse.Namespace,
    loaded: Any,
    selection: dict[str, Any],
    selection_path: Path,
    samples: list[dict[str, Any]],
    results: list[dict[str, Any]],
    typed: dict[str, Any],
    untyped_exact: dict[str, Any],
    character: dict[str, Any],
    model_dir: Path,
    backbone_dir: Path,
) -> dict[str, Any]:
    sensitivity_values = sorted(result["sensitivity"] for result in results)
    predictions = [
        {
            "id": result["sample"]["id"],
            "spans": [
                {
                    "entity": span["entity"],
                    "source_entity": span["source_entity"],
                    "byte_start": span["byte_start"],
                    "byte_end": span["byte_end"],
                }
                for span in result["predicted"]
            ],
        }
        for result in results
    ]
    return {
        "schema_version": 1,
        "status": "complete",
        "phase": "pplx_pii_candidate",
        "timestamp": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "git_sha": git_value("rev-parse", "HEAD"),
        "dirty_worktree": bool(git_value("status", "--porcelain")),
        "command": command_line(),
        "model": {
            "id": MODEL_ID,
            "revision": MODEL_REVISION,
            "license": "MIT",
            "backbone_id": BACKBONE_ID,
            "backbone_revision": BACKBONE_REVISION,
            "decoder": "published constrained BIOES Viterbi",
            "tokenizer_regex": "fixed" if args.fix_tokenizer_regex else "published",
            "files": file_manifest(model_dir, MODEL_HASHES),
            "backbone_files": file_manifest(backbone_dir, BACKBONE_HASHES),
        },
        "runtime": {
            "requested_device": args.device,
            "actual_device": args.device,
            "python": platform.python_version(),
            "platform": platform.platform(),
            "architecture": platform.machine(),
            "packages": package_versions(
                ["huggingface-hub", "safetensors", "tokenizers", "torch", "transformers"]
            ),
        },
        "dataset": {
            "name": loaded.name,
            "source": relative_path(loaded.path),
            "sample_count": len(samples),
            "full_selection_count": len(selection["dataset"]["ordered_sample_ids"]),
            "scope": "full" if args.full else f"first_{len(samples)}",
            "sample_ids_sha256": sha256_json([sample["id"] for sample in samples]),
            "dataset_sha256": selection["dataset"]["sha256"],
            "selection_sha256": sha256_file(selection_path),
            "entity_policy_sha256": selection["entity_policy"]["sha256"],
            "scoring_sha256": selection["scoring"]["sha256"],
        },
        "entity_mapping": ENTITY_MAP,
        "metrics": {
            "typed_exact": compact_metrics(typed),
            "per_entity": typed["per_entity"],
            "label_agnostic_exact": untyped_exact,
            "label_agnostic_character": character,
            "latency": typed["latency"],
            "sensitivity": sensitivity_summary(sensitivity_values),
        },
        "output_fingerprint_sha256": sha256_json(predictions),
        "raw_text_omitted": True,
        "limitations": [
            (
                "Typed exact-span scoring is the Obscura compatibility test; "
                "label-agnostic character scoring is diagnostic."
            ),
            (
                "Typed scoring filters predictions to the eight entities in the "
                "shared comparison protocol."
            ),
            (
                "Label-agnostic exact scoring uses all annotated PII and estimates "
                "boundary quality without taxonomy compatibility."
            ),
            (
                "Label-agnostic character scoring uses all annotated PII classes "
                "in each selected sample."
            ),
            "account_number is intentionally not guessed as credit_card or us_ssn.",
            (
                "private_address maps to location, but the model intentionally "
                "excludes many public locations."
            ),
            "The model repository tokenizer emits a regex warning under Transformers 5.11.0.",
            "The published single-window implementation truncates inputs beyond 4096 tokens.",
        ],
    }


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
        "unsupported_expected_spans",
        "total_supported_expected_spans",
        "total_predicted_spans",
    ]
    return {key: metrics[key] for key in keys}


def sensitivity_summary(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "at_or_above_0_5": 0}
    return {
        "mean": sum(values) / len(values),
        "p50": percentile(values, 0.50),
        "p95": percentile(values, 0.95),
        "at_or_above_0_5": sum(value >= 0.5 for value in values),
    }


def percentile(values: list[float], quantile: float) -> float:
    index = int((len(values) - 1) * quantile + 0.9999999999)
    return values[index]


def write_report(report: dict[str, Any], out_dir: Path) -> Path:
    assert_raw_omitted(report)
    out_dir.mkdir(parents=True, exist_ok=True)
    suffix = ""
    command_parts = shlex.split(report["command"])
    if "--run-suffix" in command_parts:
        index = command_parts.index("--run-suffix")
        if index + 1 < len(command_parts):
            suffix = f"-{command_parts[index + 1]}"
    run_id = (
        f"pplx_pii_masking-{report['dataset']['name']}-{report['dataset']['scope']}"
        f"-{report['runtime']['actual_device']}{suffix}"
    )
    path = out_dir / f"{run_id}.json"
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def assert_raw_omitted(value: Any, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"text", "value"}:
                location = ".".join((*path, key))
                raise ValueError(f"raw report field is forbidden: {location}")
            assert_raw_omitted(child, (*path, key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_raw_omitted(child, (*path, str(index)))


def file_manifest(directory: Path, expected: dict[str, str]) -> dict[str, str]:
    return {name: sha256_file(directory / name) for name in sorted(expected)}


def package_versions(names: list[str]) -> dict[str, str]:
    versions = {}
    for name in names:
        try:
            versions[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            versions[name] = "not-installed"
    return versions


def relative_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return path.name


def command_line() -> str:
    return shlex.join(
        ["python", "eval/pplx_pii/reference_benchmark.py", *sys.argv[1:]]
    )


def git_value(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_json(value: Any) -> str:
    encoded = json.dumps(
        value, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def divide(numerator: int, denominator: int) -> float | None:
    return None if denominator == 0 else numerator / denominator


def f1(precision: float | None, recall: float | None) -> float | None:
    if precision is None or recall is None:
        return None
    return 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)


if __name__ == "__main__":
    raise SystemExit(main())
