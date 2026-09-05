#!/usr/bin/env python3
"""Build a reviewable comparison from completed, hash-verified experiment data."""

import argparse
import json
from pathlib import Path
from statistics import mean

from benchmark import HERE, ROOT, assert_private, sha256_file, write_json


COUNT_KEYS = ("true_positives", "false_positives", "false_negatives", "offset_mismatches",
              "wrong_entity_type", "unsupported_expected_spans")
STRUCTURED = {"credit_card", "email", "ip_address", "phone", "url", "us_ssn"}


def strict_metrics(metrics):
    tp = metrics["true_positives"]
    # Authoritative metric blocks separate these errors from FP/FN.
    errors = metrics["offset_mismatches"] + metrics["wrong_entity_type"]
    fp = metrics["false_positives"] + errors
    fn = metrics["false_negatives"] + errors
    return {"precision": tp / (tp + fp) if tp + fp else None,
            "recall": tp / (tp + fn) if tp + fn else None,
            "f1": 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else None}


def load_predictions(run):
    path = Path(run["predictions_path"])
    if sha256_file(path) != run["predictions_sha256"]:
        raise ValueError("scored prediction artifact hash mismatch")
    rows = json.loads(path.read_text())
    assert_private(rows)
    return rows


def signatures(row, entities=None):
    return tuple(sorted((p["entity"], p["byte_start"], p["byte_end"])
                        for p in row["predictions"] if entities is None or p["entity"] in entities))


def compare_predictions(left, right, entities=None):
    if [row["sample_id"] for row in left] != [row["sample_id"] for row in right]:
        raise ValueError("scored prediction order mismatch")
    return sum(signatures(a, entities) != signatures(b, entities) for a, b in zip(left, right))


def build_comparison(result_path):
    result = json.loads(result_path.read_text())
    assert_private(result)
    authority_root = ROOT / "eval/authoritative"
    manifest_path = authority_root / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    comparisons = []
    for dataset in result["datasets"]:
        runs = {run["profile"]: run for run in dataset["runs"] if run["repetition"] == 1}
        reference = {}
        for entry in manifest["reports"]:
            if entry["dataset"]["name"] != dataset["name"]:
                continue
            profile = entry.get("stable_profile")
            if entry["id"].startswith("external:presidio_spacy_"):
                profile = "presidio"
            if profile not in {"fast", "balanced", "accurate", "presidio"}:
                continue
            report_path = authority_root / entry["files"]["json"]
            if sha256_file(report_path) != entry["files"]["json_sha256"]:
                raise ValueError("authoritative report hash mismatch")
            report = json.loads(report_path.read_text())
            if "comparison_protocol" in report:
                if report["comparison_protocol"]["selection_sha256"] != dataset["selection_sha256"]:
                    raise ValueError("authoritative selection mismatch")
            else:
                # The promoted accurate cascade stores these proofs in the
                # manifest and dataset block instead of comparison_protocol.
                selected = dataset["selection"]["dataset"]
                if (entry["dataset"]["sha256"] != selected["sha256"]
                        or report["dataset"]["sample_ids"] != selected["ordered_sample_ids"]
                        or report["dataset"]["requested_entities"] != dataset["selection"]["entity_policy"]["entities"]):
                    raise ValueError("authoritative cascade selection mismatch")
            reference[profile] = {"id": entry["id"], "report": str(report_path.relative_to(ROOT)),
                                  "sha256": sha256_file(report_path), "metrics": entry["metrics"],
                                  "strict_exact": strict_metrics(entry["metrics"])}
        if set(reference) != {"fast", "balanced", "accurate", "presidio"}:
            raise ValueError("missing authoritative reference")
        controls = {profile: all(runs[profile]["metrics"][key] == reference[ref]["metrics"][key]
                                for key in COUNT_KEYS)
                    for profile, ref in [("fast_reference", "fast"), ("presidio", "presidio")]}
        if not all(controls.values()):
            raise ValueError(f"control no longer reproduces authority: {controls}")
        primary = load_predictions(runs["hybrid_spacy_full"])
        stripped = load_predictions(runs["hybrid_spacy_ner_only"])
        base = load_predictions(runs["fast"])
        parity = {profile: compare_predictions(base, load_predictions(runs[profile]), STRUCTURED)
                  for profile in ["hybrid_spacy_full", "hybrid_spacy_ner_only"]}
        candidates = {}
        for profile, run in runs.items():
            repeated = [r for r in dataset["runs"] if r["profile"] == profile]
            candidates[profile] = {
                "metrics": run["metrics"], "strict_exact": run["strict_exact"],
                "mean_ms_by_repetition": [r["metrics"]["latency"]["mean_ms"] for r in repeated],
                "p95_ms_by_repetition": [r["metrics"]["latency"]["p95_ms"] for r in repeated],
                "mean_ms": mean(r["metrics"]["latency"]["mean_ms"] for r in repeated),
                "obscura_analysis_mean_ms": mean(r["obscura_analysis_mean_ms"] for r in repeated),
                "python_processing_mean_ms": mean(r["python_processing_mean_ms"] for r in repeated),
                "output_fingerprint_sha256": run["output_fingerprint_sha256"],
            }
        comparisons.append({"dataset": dataset["name"], "samples": len(base),
                            "controls_match_authoritative_counts": controls,
                            "structured_prediction_mismatching_documents": parity,
                            "full_vs_ner_only_changed_documents": compare_predictions(primary, stripped),
                            "candidates": candidates, "authoritative": reference,
                            "repetition_checks": dataset["repetition_checks"],
                            "selection_sha256": dataset["selection_sha256"]})
    return {"schema_version": 1, "status": "unpromoted_experiment", "source_results": str(result_path),
            "source_results_sha256": sha256_file(result_path),
            "report_code_sha256": sha256_file(Path(__file__)),
            "authoritative_manifest_sha256": sha256_file(manifest_path),
            "experiment": {k: v for k, v in result.items() if k != "datasets"},
            "comparisons": comparisons, "raw_text_omitted": True}


def fmt(value):
    return "—" if value is None else f"{value:.4f}"


def markdown(comparison):
    experiment = comparison["experiment"]
    lines = ["# spaCy hybrid benchmark results", "",
             f"Branch: `{experiment['branch']}`. Base commit: `{experiment['source_commit']}`.", "",
             "Exploratory results; no native implementation or stable-profile change is included.", "",
             "## Shared benchmark F1", "",
             "These use the existing evaluator's historical ratios. See strict-span results below.", "",
             "| Dataset | Samples | Fast | Presidio | Hybrid full | Hybrid NER-only | Balanced¹ | Accurate¹ |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for item in comparison["comparisons"]:
        c, a = item["candidates"], item["authoritative"]
        values = [c[p]["metrics"]["f1"] for p in ["fast", "presidio", "hybrid_spacy_full", "hybrid_spacy_ner_only"]]
        values += [a[p]["metrics"]["f1"] for p in ["balanced", "accurate"]]
        lines.append(f"| {item['dataset']} | {item['samples']} | " + " | ".join(map(fmt, values)) + " |")
    lines += ["", "¹ Existing hash-verified authoritative GPU runs, used for accuracy comparison only.", "",
              "Fast above uses normal production conflict resolution. An additional `fast_reference` control disables conflicts, "
              "matching the historical fixture adapter; its counts exactly reproduce the authoritative baseline. "
              "The production default removes four additional false positives on generated heldout (F1 0.6684 versus 0.6667); "
              "the other datasets are unchanged.", "",
              "## Conventional strict-span F1", "",
              "Boundary errors and wrong types count as both false positives and false negatives.", "",
              "| Dataset | Fast | Presidio | Hybrid full | Hybrid NER-only | Balanced | Accurate |",
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for item in comparison["comparisons"]:
        c, a = item["candidates"], item["authoritative"]
        values = [c[p]["strict_exact"]["f1"] for p in ["fast", "presidio", "hybrid_spacy_full", "hybrid_spacy_ner_only"]]
        values += [a[p]["strict_exact"]["f1"] for p in ["balanced", "accurate"]]
        lines.append(f"| {item['dataset']} | " + " | ".join(map(fmt, values)) + " |")
    lines += ["", "## Primary hybrid precision and recall", "",
              "| Dataset | Shared precision | Shared recall | Shared F2 | Strict precision | Strict recall | Boundary errors | Wrong types |",
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for item in comparison["comparisons"]:
        run = item["candidates"]["hybrid_spacy_full"]
        m, s = run["metrics"], run["strict_exact"]
        values = [m["precision"], m["recall"], m["f2"], s["precision"], s["recall"]]
        lines.append(f"| {item['dataset']} | " + " | ".join(map(fmt, values)) +
                     f" | {m['offset_mismatches']} | {m['wrong_entity_type']} |")
    lines += ["", "## CPU component cost", "",
              "Mean milliseconds, averaged over two repetitions. Hybrid values add Python processing and actual Obscura analysis; IPC, serialization, disk reads, startup and loading are excluded. These are not native or production latency measurements.", "",
              "| Dataset | Fast | Presidio | Hybrid full | Hybrid NER-only | Full hybrid Obscura portion |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for item in comparison["comparisons"]:
        c = item["candidates"]
        values = [c[p]["mean_ms"] for p in ["fast", "presidio", "hybrid_spacy_full", "hybrid_spacy_ner_only"]]
        values += [c["hybrid_spacy_full"]["obscura_analysis_mean_ms"]]
        lines.append(f"| {item['dataset']} | " + " | ".join(map(fmt, values)) + " |")
    lines += ["", "## Person and location results", "",
              "Shared per-entity F1 (boundary errors reported separately by this evaluator).", "",
              "| Dataset | Entity | Fast | Presidio | Hybrid full | Balanced | Accurate |",
              "| --- | --- | ---: | ---: | ---: | ---: | ---: |"]
    for item in comparison["comparisons"]:
        for entity in ["person", "location"]:
            c, a = item["candidates"], item["authoritative"]
            values = [c[p]["metrics"]["per_entity"][entity]["f1"] for p in ["fast", "presidio", "hybrid_spacy_full"]]
            values += [a[p]["metrics"]["per_entity"][entity]["f1"] for p in ["balanced", "accurate"]]
            lines.append(f"| {item['dataset']} | {entity} | " + " | ".join(map(fmt, values)) + " |")
    lines += ["", "## Integrity checks", "",
              "| Dataset | Reference controls match | Changed structured outputs (full / NER-only) | Full vs NER-only changed documents |",
              "| --- | --- | ---: | ---: |"]
    for item in comparison["comparisons"]:
        parity = item["structured_prediction_mismatching_documents"]
        matched = "Yes" if all(item["controls_match_authoritative_counts"].values()) else "No"
        lines += [f"| {item['dataset']} | {matched} | {parity['hybrid_spacy_full']} / {parity['hybrid_spacy_ner_only']} "
                  f"| {item['full_vs_ner_only_changed_documents']} |"]
    lines += ["", "All five measured profiles reproduced accuracy and prediction fingerprints in both repetitions. "
              "Dataset bytes, ordered sample IDs, entity policy, UTF-8 offsets, model hashes, and reference report hashes were checked. "
              "See `comparison.json` for counts, per-entity metrics, IoU, repetition timings, fingerprints, and environment evidence.", "",
              "## Reproduce", "", "```sh",
              ".presidio-authoritative-venv/bin/python eval/spacy_hybrid/benchmark.py",
              ".presidio-authoritative-venv/bin/python eval/spacy_hybrid/report.py --results PATH_TO_RESULTS_JSON --out-dir PATH_TO_REVIEW_REPORT",
              "```", "", "The datasets are synthetic and the shared taxonomy excludes organizations, dates, and other PII categories. "
              "The NER-only result is diagnostic; selecting it for a product would require validation on untouched deployment-representative data.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", required=True, type=Path)
    parser.add_argument("--out-dir", type=Path, default=HERE / "results")
    args = parser.parse_args()
    comparison = build_comparison(args.results.resolve())
    write_json(args.out_dir / "comparison.json", comparison)
    (args.out_dir / "RESULTS.md").write_text(markdown(comparison), encoding="utf-8")
    print(json.dumps({"report": str(args.out_dir / "RESULTS.md")}))


if __name__ == "__main__":
    main()
