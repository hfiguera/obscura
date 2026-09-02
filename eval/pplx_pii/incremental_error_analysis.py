#!/usr/bin/env python3
"""Explain what Perplexity adds to Obscura's accurate profile."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import re
import sys
from typing import Any, Callable
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
PRESIDIO_ADAPTER = ROOT / "eval" / "presidio_adapter" / "real_presidio_benchmark.py"
HYBRID_BENCHMARK = ROOT / "eval" / "pplx_pii" / "hybrid_benchmark.py"
CONTACT_ENTITIES = frozenset({"email", "phone", "url"})
TRAILING_URL_PUNCTUATION = ".,;:!?"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--predictions-dir",
        default=str(ROOT / "eval" / "predictions" / "hybrid"),
    )
    parser.add_argument(
        "--out",
        default=str(
            ROOT
            / "eval"
            / "reports"
            / "pplx_incremental_error_analysis.json"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    presidio = load_python_module("obscura_incremental_presidio", PRESIDIO_ADAPTER)
    hybrid = load_python_module("obscura_incremental_hybrid", HYBRID_BENCHMARK)
    predictions_dir = Path(args.predictions_dir)

    datasets = {}
    for dataset, selection_path in hybrid.SELECTIONS.items():
        loaded = presidio.load_dataset(dataset)
        selection = presidio.load_selection(str(selection_path), loaded)
        samples = presidio.selected_samples_from_selection(
            loaded.samples, selection
        )
        artifacts = load_artifacts(
            dataset, selection_path, predictions_dir, hybrid
        )
        datasets[dataset] = analyze_dataset(
            samples,
            selection["entity_policy"]["entities"],
            artifacts,
            presidio,
            hybrid,
        )

    report = {
        "schema_version": 1,
        "status": "complete",
        "phase": "pplx_pii_incremental_error_analysis",
        "timestamp": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "question": (
            "Does Perplexity add model-dependent capability, or structured "
            "formats suitable for deterministic recognition?"
        ),
        "datasets": datasets,
        "aggregate": aggregate(datasets),
        "raw_text_omitted": True,
        "limitations": [
            (
                "The URL rule is an analysis probe, not a production recognizer "
                "or a promoted policy."
            ),
            (
                "Phone parser results use the existing optional ex_phone_number "
                "adapter and its default regions and context gate."
            ),
            (
                "The model contact policy and deterministic probes were examined "
                "on evaluation data and require untouched validation before use."
            ),
        ],
    }
    assert_raw_omitted(report)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    out.write_text(rendered, encoding="utf-8")
    summary = {"out": str(out), "aggregate": report["aggregate"]}
    print(json.dumps(summary, sort_keys=True))
    return 0


def load_artifacts(
    dataset: str,
    selection_path: Path,
    predictions_dir: Path,
    hybrid: Any,
) -> dict[str, dict[str, Any]]:
    paths = {
        "base": predictions_dir / f"accurate-{dataset}.json",
        "pplx": predictions_dir / f"pplx-{dataset}.json",
        "phone_parser": predictions_dir
        / f"accurate-phone-parser-{dataset}.json",
    }
    return {
        name: hybrid.load_artifact(path, dataset, selection_path)
        for name, path in paths.items()
    }


def analyze_dataset(
    samples: list[dict[str, Any]],
    supported_entities: list[str],
    artifacts: dict[str, dict[str, Any]],
    presidio: Any,
    hybrid: Any,
) -> dict[str, Any]:
    base_rows = hybrid.rows_by_id(artifacts["base"])
    pplx_rows = hybrid.rows_by_id(artifacts["pplx"])
    parser_rows = hybrid.rows_by_id(artifacts["phone_parser"])
    classifications: Counter[tuple[str, str]] = Counter()
    broad_classifications: Counter[tuple[str, str]] = Counter()
    wrong_type_targets: Counter[tuple[str, str]] = Counter()
    phone_formats: Counter[str] = Counter()
    phone_formats_recovered: Counter[str] = Counter()
    phone_digit_lengths: Counter[int] = Counter()
    exact_phone = 0
    parser_recovered_phone = 0
    exact_url = 0
    url_probe_recovered = 0
    url_schemes: Counter[str] = Counter()
    url_suffixes: Counter[str] = Counter()
    shape_classifications: Counter[tuple[str, str]] = Counter()
    parser_added_classifications: Counter[tuple[str, str]] = Counter()
    parser_removed_classifications: Counter[tuple[str, str]] = Counter()
    parser_wrong_type_targets: Counter[tuple[str, str]] = Counter()
    url_probe_classifications: Counter[tuple[str, str]] = Counter()
    base_results = []
    shape_results = []
    parser_results = []
    url_probe_results = []

    for sample in samples:
        sample_id = str(sample["id"])
        base_row = hybrid.require_row(base_rows, sample_id, "Obscura")
        pplx_row = hybrid.require_row(pplx_rows, sample_id, "Perplexity")
        parser_row = hybrid.require_row(parser_rows, sample_id, "phone parser")
        base_results.append(
            score_row(sample, base_row["predictions"], base_row["latency_ms"])
        )
        additions, _predicted = merge_candidates(
            base_row["predictions"], pplx_row["predictions"], hybrid.overlaps
        )
        broad_additions, _broad_predictions = merge_candidates(
            base_row["predictions"],
            pplx_row["predictions"],
            hybrid.overlaps,
            admitted_entities=frozenset(supported_entities),
        )

        for candidate in broad_additions:
            classification = classify(candidate, sample["spans"], hybrid.overlaps)
            broad_classifications[(candidate["entity"], classification)] += 1

        for candidate in additions:
            classification = classify(candidate, sample["spans"], hybrid.overlaps)
            classifications[(candidate["entity"], classification)] += 1
            if classification == "wrong_entity_type":
                count_wrong_type_targets(
                    wrong_type_targets, candidate, sample["spans"], hybrid.overlaps
                )

            if classification == "exact" and candidate["entity"] == "phone":
                exact_phone += 1
                recovered = contains_exact(parser_row["predictions"], candidate)
                parser_recovered_phone += int(recovered)
                value = byte_slice(sample["text"], candidate)
                phone_digit_lengths[len(re.findall(r"\d", value))] += 1
                for feature in phone_format_features(value):
                    phone_formats[feature] += 1
                    phone_formats_recovered[feature] += int(recovered)

            if classification == "exact" and candidate["entity"] == "url":
                exact_url += 1
                value = byte_slice(sample["text"], candidate)
                url_schemes[urlsplit(value).scheme.lower()] += 1
                url_suffixes[url_suffix(sample["text"], candidate)] += 1
                url_probe_recovered += int(
                    contains_exact(url_probe_predictions(sample["text"]), candidate)
                )

        shape_additions, shape_predictions = merge_candidates(
            base_row["predictions"],
            pplx_row["predictions"],
            hybrid.overlaps,
            lambda candidate: valid_contact_shape(
                byte_slice(sample["text"], candidate), candidate["entity"]
            ),
        )
        shape_results.append(
            score_row(sample, shape_predictions, base_row["latency_ms"])
        )
        for candidate in shape_additions:
            classification = classify(candidate, sample["spans"], hybrid.overlaps)
            shape_classifications[(candidate["entity"], classification)] += 1

        for candidate in parser_row["predictions"]:
            if not contains_exact(base_row["predictions"], candidate):
                classification = classify(
                    candidate, sample["spans"], hybrid.overlaps
                )
                parser_added_classifications[(candidate["entity"], classification)] += 1
                if classification == "wrong_entity_type":
                    count_wrong_type_targets(
                        parser_wrong_type_targets,
                        candidate,
                        sample["spans"],
                        hybrid.overlaps,
                    )
        for candidate in base_row["predictions"]:
            if not contains_exact(parser_row["predictions"], candidate):
                parser_removed_classifications[
                    (
                        candidate["entity"],
                        classify(candidate, sample["spans"], hybrid.overlaps),
                    )
                ] += 1

        parser_results.append(
            score_row(sample, parser_row["predictions"], parser_row["latency_ms"])
        )
        url_additions, url_predictions = merge_candidates(
            base_row["predictions"],
            url_probe_predictions(sample["text"]),
            hybrid.overlaps,
        )
        url_probe_results.append(
            score_row(sample, url_predictions, base_row["latency_ms"])
        )
        for candidate in url_additions:
            classification = classify(candidate, sample["spans"], hybrid.overlaps)
            url_probe_classifications[(candidate["entity"], classification)] += 1

    exact_additions = sum(
        count
        for (entity, classification), count in classifications.items()
        if entity in CONTACT_ENTITIES and classification == "exact"
    )
    return {
        "sample_count": len(samples),
        "accepted_model_additions": sum(classifications.values()),
        "classification": nested_classification(classifications),
        "wrong_entity_targets": nested_targets(wrong_type_targets),
        "exact_contact_additions": {
            "total": exact_additions,
            "phone": exact_phone,
            "url": exact_url,
            "email": classifications[("email", "exact")],
        },
        "broad_supported_diagnostic": {
            "accepted_model_additions": sum(broad_classifications.values()),
            "classification": nested_classification(
                broad_classifications, frozenset(supported_entities)
            ),
            "exact_by_entity": exact_counts(broad_classifications),
        },
        "base_metrics": compact_metrics(
            presidio.score_results(base_results, supported_entities)
        ),
        "shape_gated_contact_hybrid": {
            "metrics": compact_metrics(
                presidio.score_results(shape_results, supported_entities)
            ),
            "accepted_classification": nested_classification(
                shape_classifications
            ),
        },
        "existing_phone_parser": {
            "metrics": compact_metrics(
                presidio.score_results(parser_results, supported_entities)
            ),
            "exact_model_phone_additions_recovered": parser_recovered_phone,
            "exact_model_phone_additions_total": exact_phone,
            "recovery_rate": ratio(parser_recovered_phone, exact_phone),
            "prediction_delta": {
                "added": nested_classification(parser_added_classifications),
                "removed": nested_classification(parser_removed_classifications),
                "added_wrong_entity_targets": nested_targets(
                    parser_wrong_type_targets
                ),
            },
            "format_features": {
                feature: {
                    "total": count,
                    "recovered": phone_formats_recovered[feature],
                }
                for feature, count in sorted(phone_formats.items())
            },
            "digit_lengths": {
                str(length): count
                for length, count in sorted(phone_digit_lengths.items())
            },
        },
        "deterministic_url_probe": {
            "metrics": compact_metrics(
                presidio.score_results(url_probe_results, supported_entities)
            ),
            "exact_model_url_additions_recovered": url_probe_recovered,
            "exact_model_url_additions_total": exact_url,
            "recovery_rate": ratio(url_probe_recovered, exact_url),
            "accepted_classification": nested_classification(
                url_probe_classifications
            ),
            "schemes": dict(sorted(url_schemes.items())),
            "following_character": dict(sorted(url_suffixes.items())),
        },
    }


def merge_candidates(
    base: list[dict[str, Any]],
    candidates: list[dict[str, Any]],
    overlaps: Callable[[dict[str, Any], dict[str, Any]], bool],
    accept: Callable[[dict[str, Any]], bool] | None = None,
    admitted_entities: frozenset[str] = CONTACT_ENTITIES,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    predicted = list(base)
    accepted = []
    for candidate in candidates:
        if candidate["entity"] not in admitted_entities:
            continue
        if accept is not None and not accept(candidate):
            continue
        if any(overlaps(candidate, current) for current in predicted):
            continue
        predicted.append(candidate)
        accepted.append(candidate)
    return accepted, predicted


def classify(
    candidate: dict[str, Any],
    expected: list[dict[str, Any]],
    overlaps: Callable[[dict[str, Any], dict[str, Any]], bool],
) -> str:
    if any(same_typed_span(candidate, span) for span in expected):
        return "exact"
    if any(
        candidate["entity"] == span["entity"] and overlaps(candidate, span)
        for span in expected
    ):
        return "boundary_mismatch"
    if any(overlaps(candidate, span) for span in expected):
        return "wrong_entity_type"
    return "false_positive"


def same_typed_span(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return (
        left["entity"] == right["entity"]
        and left["byte_start"] == right["byte_start"]
        and left["byte_end"] == right["byte_end"]
    )


def contains_exact(
    predictions: list[dict[str, Any]], candidate: dict[str, Any]
) -> bool:
    return any(same_typed_span(prediction, candidate) for prediction in predictions)


def valid_contact_shape(value: str, entity: str) -> bool:
    if entity == "email":
        return bool(re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value))
    if entity == "phone":
        if not re.fullmatch(
            r"\+?[\d().\- \t]+(?:\s*(?:ext\.?|extension|x)\s*\d{1,7})?",
            value,
            flags=re.IGNORECASE,
        ):
            return False
        return 7 <= len(re.findall(r"\d", value)) <= 16
    if entity == "url":
        parsed = urlsplit(value)
        return parsed.scheme.lower() in {"http", "https", "ftp"} and bool(
            parsed.hostname
        )
    return False


def url_probe_predictions(text: str) -> list[dict[str, Any]]:
    predictions = []
    for match in re.finditer(r"(?i)\b(?:https?|ftp)://[^\s<>\"']+", text):
        value = trim_url_punctuation(match.group(0))
        if not valid_contact_shape(value, "url"):
            continue
        char_start = match.start()
        char_end = char_start + len(value)
        predictions.append(
            {
                "entity": "url",
                "char_start": char_start,
                "char_end": char_end,
                "byte_start": len(text[:char_start].encode("utf-8")),
                "byte_end": len(text[:char_end].encode("utf-8")),
            }
        )
    return predictions


def trim_url_punctuation(value: str) -> str:
    value = value.rstrip(TRAILING_URL_PUNCTUATION)
    pairs = (("(", ")"), ("[", "]"), ("{", "}"))
    changed = True
    while changed and value:
        changed = False
        for opening, closing in pairs:
            if value.endswith(closing) and value.count(closing) > value.count(opening):
                value = value[:-1]
                changed = True
    return value


def url_suffix(text: str, candidate: dict[str, Any]) -> str:
    suffix = text[candidate["char_end"] : candidate["char_end"] + 1]
    if not suffix:
        return "end_of_text"
    if suffix in TRAILING_URL_PUNCTUATION or suffix in ")]}":
        return "punctuation"
    return "other"


def phone_format_features(value: str) -> list[str]:
    features = []
    if value.lstrip().startswith("+"):
        features.append("leading_plus")
    if "(" in value or ")" in value:
        features.append("parentheses")
    if "-" in value:
        features.append("hyphen")
    if "." in value:
        features.append("dot")
    if re.search(r"\s", value):
        features.append("space")
    if not features:
        features.append("digits_only")
    return features


def byte_slice(text: str, span: dict[str, Any]) -> str:
    return text.encode("utf-8")[span["byte_start"] : span["byte_end"]].decode(
        "utf-8"
    )


def score_row(
    sample: dict[str, Any], predictions: list[dict[str, Any]], latency_ms: float
) -> dict[str, Any]:
    return {
        "sample": {"id": sample["id"]},
        "expected": sample["spans"],
        "predicted": predictions,
        "latency_ms": latency_ms,
    }


def nested_classification(
    classifications: Counter[tuple[str, str]],
    entities: frozenset[str] = CONTACT_ENTITIES,
) -> dict[str, dict[str, int]]:
    return {
        entity: {
            classification: classifications[(entity, classification)]
            for classification in (
                "exact",
                "boundary_mismatch",
                "wrong_entity_type",
                "false_positive",
            )
        }
        for entity in sorted(entities)
    }


def exact_counts(
    classifications: Counter[tuple[str, str]],
) -> dict[str, int]:
    return {
        entity: count
        for (entity, classification), count in sorted(classifications.items())
        if classification == "exact" and count > 0
    }


def count_wrong_type_targets(
    counts: Counter[tuple[str, str]],
    candidate: dict[str, Any],
    expected: list[dict[str, Any]],
    overlaps: Callable[[dict[str, Any], dict[str, Any]], bool],
) -> None:
    for span in expected:
        if candidate["entity"] != span["entity"] and overlaps(candidate, span):
            counts[(candidate["entity"], span["entity"])] += 1


def nested_targets(
    counts: Counter[tuple[str, str]],
) -> dict[str, dict[str, int]]:
    sources = sorted({source for source, _target in counts})
    return {
        source: {
            target: count
            for (candidate_source, target), count in sorted(counts.items())
            if candidate_source == source
        }
        for source in sources
    }


def compact_metrics(metrics: dict[str, Any]) -> dict[str, Any]:
    keys = [
        "precision",
        "recall",
        "f1",
        "true_positives",
        "false_positives",
        "false_negatives",
        "offset_mismatches",
        "wrong_entity_type",
    ]
    return {key: metrics[key] for key in keys}


def aggregate(datasets: dict[str, dict[str, Any]]) -> dict[str, Any]:
    exact_by_entity = {
        entity: sum(
            dataset["exact_contact_additions"][entity]
            for dataset in datasets.values()
        )
        for entity in ("email", "phone", "url")
    }
    exact_total = sum(exact_by_entity.values())
    parser_recovered = sum(
        dataset["existing_phone_parser"][
            "exact_model_phone_additions_recovered"
        ]
        for dataset in datasets.values()
    )
    url_recovered = sum(
        dataset["deterministic_url_probe"][
            "exact_model_url_additions_recovered"
        ]
        for dataset in datasets.values()
    )
    deterministic_recovered = parser_recovered + url_recovered
    broad_exact_by_entity: Counter[str] = Counter()
    broad_nonexact_by_entity: Counter[str] = Counter()
    for dataset in datasets.values():
        diagnostic = dataset["broad_supported_diagnostic"]
        broad_exact_by_entity.update(diagnostic["exact_by_entity"])
        for entity, classifications in diagnostic["classification"].items():
            broad_nonexact_by_entity[entity] += sum(
                count
                for classification, count in classifications.items()
                if classification != "exact"
            )
    return {
        "exact_contact_additions": exact_total,
        "exact_contact_additions_by_entity": exact_by_entity,
        "existing_phone_parser_recovered": parser_recovered,
        "deterministic_url_probe_recovered": url_recovered,
        "deterministic_probe_recovered_total": deterministic_recovered,
        "deterministic_probe_recovery_rate": ratio(
            deterministic_recovered, exact_total
        ),
        "exact_additions_not_recovered_by_current_probes": (
            exact_total - deterministic_recovered
        ),
        "broad_diagnostic": {
            "exact_by_entity": dict(sorted(broad_exact_by_entity.items())),
            "nonexact_by_entity": dict(sorted(broad_nonexact_by_entity.items())),
        },
        "conclusion": (
            "The gains behind the contact hybrid are structured phone and URL "
            "formats. Broader semantic policies find some exact spans but add "
            "many more errors and are not responsible for the candidate gain."
        ),
    }


def ratio(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def assert_raw_omitted(value: Any, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in {"text", "value"}:
                raise ValueError(
                    f"raw report field is forbidden: {'.'.join((*path, key))}"
                )
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


if __name__ == "__main__":
    raise SystemExit(main())
